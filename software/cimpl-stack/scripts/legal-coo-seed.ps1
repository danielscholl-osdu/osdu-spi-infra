<#
.SYNOPSIS
  Uploads Legal_COO.json to MinIO and registers the bucket in the partition service.

.DESCRIPTION
  This script performs two steps:
    1. Port-forwards to MinIO, creates the bucket (if it doesn't exist), and uploads
       Legal_COO.json using AWS Signature V4 signing.
    2. Port-forwards to the partition service and PATCHes the legal.bucket.name
       property so the legal service can locate the file.

  MinIO credentials are read from the legal-minio-secret Kubernetes secret
  (not passed as command-line arguments) to avoid Terraform sensitive-value
  output suppression.

.PARAMETER PlatformNamespace
  Kubernetes namespace where MinIO is deployed.

.PARAMETER OsduNamespace
  Kubernetes namespace where the partition service is deployed.

.PARAMETER CimplTenant
  Tenant name used in the partition API path and data-partition-id header.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$PlatformNamespace,

    [Parameter(Mandatory = $true)]
    [string]$OsduNamespace,

    [Parameter(Mandatory = $true)]
    [string]$CimplTenant
)

$ErrorActionPreference = 'Stop'

# ─── Read MinIO credentials from cluster secret ─────────────────────────────

Write-Host "Reading MinIO credentials from legal-minio-secret..."
$MinioRootUser = kubectl get secret legal-minio-secret -n $OsduNamespace -o jsonpath='{.data.MINIO_ACCESS_KEY}' 2>$null
$MinioRootPassword = kubectl get secret legal-minio-secret -n $OsduNamespace -o jsonpath='{.data.MINIO_SECRET_KEY}' 2>$null

if (-not $MinioRootUser -or -not $MinioRootPassword) {
    throw "Failed to read legal-minio-secret from namespace '$OsduNamespace'. Ensure the secret exists."
}

$MinioRootUser = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($MinioRootUser))
$MinioRootPassword = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($MinioRootPassword))
Write-Host "  Credentials loaded."

# ─── Constants ────────────────────────────────────────────────────────────────
$Bucket   = "refi-osdu-legal-config"
$Region   = "us-east-1"
$Service  = "s3"
$Endpoint = "http://localhost:19000"
$Host_    = "localhost:19000"

$LegalCooJson = '[{"name": "Malaysia", "alpha2": "MY", "numeric": 458, "residencyRisk": "Client consent required"}]'

# ─── Helper: SHA256 hex digest of a byte array ───────────────────────────────
function Get-Sha256Hex([byte[]]$Data) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($Data)
        return [System.BitConverter]::ToString($hash).Replace('-', '').ToLower()
    } finally {
        $sha.Dispose()
    }
}

# ─── Helper: HMAC-SHA256 (returns raw bytes) ─────────────────────────────────
function Get-HmacSha256([byte[]]$Key, [string]$Message) {
    $hmac = New-Object System.Security.Cryptography.HMACSHA256
    $hmac.Key = $Key
    try {
        return $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Message))
    } finally {
        $hmac.Dispose()
    }
}

# ─── Helper: AWS Signature V4 signing ────────────────────────────────────────
function Get-Aws4AuthHeaders([string]$Method, [string]$Path, [byte[]]$Payload = @()) {
    $now       = [System.DateTime]::UtcNow
    $dateStamp = $now.ToString("yyyyMMdd")
    $amzDate   = $now.ToString("yyyyMMddTHHmmssZ")
    $scope     = "$dateStamp/$Region/$Service/aws4_request"

    # Payload hash
    $payloadHash = Get-Sha256Hex $Payload

    # Canonical headers (must be sorted by header name, terminated with newline)
    $canonicalHeaders = "host:$Host_`nx-amz-content-sha256:$payloadHash`nx-amz-date:$amzDate`n"
    $signedHeaders    = "host;x-amz-content-sha256;x-amz-date"

    # Canonical request
    $canonicalRequest = "$Method`n$Path`n`n$canonicalHeaders`n$signedHeaders`n$payloadHash"

    # String to sign
    $canonicalRequestHash = Get-Sha256Hex ([System.Text.Encoding]::UTF8.GetBytes($canonicalRequest))
    $stringToSign = "AWS4-HMAC-SHA256`n$amzDate`n$scope`n$canonicalRequestHash"

    # Derive signing key: AWS4<secret> -> date -> region -> service -> aws4_request
    $kSecret  = [System.Text.Encoding]::UTF8.GetBytes("AWS4$MinioRootPassword")
    $kDate    = Get-HmacSha256 $kSecret    $dateStamp
    $kRegion  = Get-HmacSha256 $kDate      $Region
    $kService = Get-HmacSha256 $kRegion    $Service
    $kSigning = Get-HmacSha256 $kService   "aws4_request"

    # Signature
    $signatureBytes = Get-HmacSha256 $kSigning $stringToSign
    $signature = [System.BitConverter]::ToString($signatureBytes).Replace('-', '').ToLower()

    return @{
        "Authorization"        = "AWS4-HMAC-SHA256 Credential=$MinioRootUser/$scope, SignedHeaders=$signedHeaders, Signature=$signature"
        "x-amz-date"           = $amzDate
        "x-amz-content-sha256" = $payloadHash
    }
}

# ─── Phase 1: Upload Legal_COO.json to MinIO ─────────────────────────────────
Write-Host "Phase 1: Uploading Legal_COO.json to MinIO..."

$minioPortForward = $null

try {
    # Start kubectl port-forward to MinIO
    $minioPortForward = Start-Process kubectl `
        -ArgumentList @("port-forward", "-n", $PlatformNamespace, "svc/minio", "19000:9000") `
        -NoNewWindow -PassThru

    # Give the port-forward a moment to establish
    Start-Sleep -Seconds 2

    # ── Create bucket (ignore "BucketAlreadyOwnedByYou") ──
    Write-Host "Creating bucket '$Bucket'..."
    $headers = Get-Aws4AuthHeaders "PUT" "/$Bucket"
    try {
        Invoke-WebRequest -Uri "$Endpoint/$Bucket" -Method PUT -Headers $headers -UseBasicParsing -SkipHeaderValidation | Out-Null
        Write-Host "Bucket '$Bucket' created."
    } catch {
        # PowerShell 7 populates ErrorDetails.Message with the response body
        $body = if ($_.ErrorDetails) { $_.ErrorDetails.Message } else { "" }
        if ($body -match "BucketAlreadyOwnedByYou") {
            Write-Host "Bucket '$Bucket' already exists (owned by us). Continuing."
        } else {
            throw
        }
    }

    # ── Upload Legal_COO.json ──
    Write-Host "Uploading Legal_COO.json..."
    $cooBytes = [System.Text.Encoding]::UTF8.GetBytes($LegalCooJson)
    $headers  = Get-Aws4AuthHeaders "PUT" "/$Bucket/Legal_COO.json" $cooBytes
    Invoke-WebRequest -Uri "$Endpoint/$Bucket/Legal_COO.json" `
        -Method PUT -Headers $headers -Body $cooBytes -UseBasicParsing -SkipHeaderValidation | Out-Null
    Write-Host "Legal_COO.json uploaded to MinIO."
} finally {
    # Clean up MinIO port-forward
    if ($minioPortForward -and -not $minioPortForward.HasExited) {
        Stop-Process -Id $minioPortForward.Id -Force -ErrorAction SilentlyContinue
    }
}

# ─── Phase 2: Register legal.bucket.name in partition service ─────────────────
Write-Host "Phase 2: Registering legal.bucket.name in partition service..."

$partitionPortForward = $null

try {
    # Start kubectl port-forward to partition service
    $partitionPortForward = Start-Process kubectl `
        -ArgumentList @("port-forward", "-n", $OsduNamespace, "svc/partition", "19080:80") `
        -NoNewWindow -PassThru

    # Give the port-forward a moment to establish
    Start-Sleep -Seconds 2

    $uri  = "http://localhost:19080/api/partition/v1/partitions/$CimplTenant"
    $body = '{"properties": {"legal.bucket.name": {"sensitive": false, "value": "refi-osdu-legal-config"}}}'

    $response = Invoke-WebRequest -Uri $uri `
        -Method Patch `
        -Body $body `
        -ContentType "application/json" `
        -Headers @{ "data-partition-id" = $CimplTenant } `
        -UseBasicParsing

    $statusCode = $response.StatusCode

    if ($statusCode -eq 200 -or $statusCode -eq 204) {
        Write-Host "Partition property legal.bucket.name set successfully."
    } else {
        Write-Warning "Partition property update returned HTTP $statusCode."
    }
} catch {
    # Extract status code from the exception if available
    $statusCode = $null
    if ($_.Exception.Response) {
        $statusCode = [int]$_.Exception.Response.StatusCode
    }

    if ($statusCode -eq 200 -or $statusCode -eq 204) {
        Write-Host "Partition property legal.bucket.name set successfully."
    } else {
        $msg = if ($statusCode) { "HTTP $statusCode" } else { $_.Exception.Message }
        Write-Warning "Partition property update returned $msg."
    }
} finally {
    # Clean up partition port-forward
    if ($partitionPortForward -and -not $partitionPortForward.HasExited) {
        Stop-Process -Id $partitionPortForward.Id -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "Legal COO seed complete."
