<#
.SYNOPSIS
  Waits for Keycloak to be ready and its JWKS endpoint to serve keys.

.DESCRIPTION
  This script polls for a Keycloak pod to exist, waits for it to become ready,
  then uses kubectl port-forward to poll the JWKS endpoint until it returns keys.
  It faithfully mirrors the inline bash used by the keycloak_jwks_wait null_resource.

.PARAMETER Namespace
  Kubernetes namespace where Keycloak is deployed.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Namespace
)

$ErrorActionPreference = 'Stop'

# ── Phase 1: Wait for Keycloak pod to exist ──────────────────────────────────
Write-Host "Waiting for Keycloak pod to exist..."
$Timeout  = 300
$Interval = 5
$Elapsed  = 0

while ($Elapsed -lt $Timeout) {
    $lines = kubectl get pods -n $Namespace -l app.kubernetes.io/instance=keycloak --no-headers 2>$null
    $count = if ($lines) { @($lines).Count } else { 0 }

    if ($count -gt 0) {
        Write-Host "Keycloak pod found after $Elapsed seconds."
        break
    }

    Write-Host "No Keycloak pod yet ($Elapsed/$Timeout s). Waiting..."
    Start-Sleep -Seconds $Interval
    $Elapsed += $Interval
}

if ($Elapsed -ge $Timeout) {
    Write-Error "ERROR: Keycloak pod did not appear within $Timeout seconds."
    exit 1
}

# ── Phase 2: Wait for Keycloak pod readiness ─────────────────────────────────
Write-Host "Waiting for Keycloak pod to become ready..."
kubectl wait --for=condition=Ready pod `
    -n $Namespace -l app.kubernetes.io/instance=keycloak `
    --timeout=600s

if ($LASTEXITCODE -ne 0) {
    Write-Error "ERROR: kubectl wait failed with exit code $LASTEXITCODE."
    exit 1
}

Write-Host "Keycloak pod is ready. Waiting for JWKS endpoint (realm import)..."

# ── Phase 3: Port-forward and poll JWKS endpoint ─────────────────────────────
$portForwardProc = $null

try {
    # Start kubectl port-forward as a background process
    $portForwardProc = Start-Process kubectl `
        -ArgumentList "port-forward", "svc/keycloak", "-n", $Namespace, "28080:80" `
        -NoNewWindow -PassThru

    # Give the port-forward a moment to establish
    Start-Sleep -Seconds 3

    $JwksUrl  = "http://localhost:28080/realms/osdu/protocol/openid-connect/certs"
    $Timeout  = 600
    $Interval = 5
    $Elapsed  = 0

    while ($Elapsed -lt $Timeout) {
        $result = $null
        try {
            $result = Invoke-RestMethod -Uri $JwksUrl -TimeoutSec 5 -ErrorAction SilentlyContinue
        } catch {
            # Request failed; endpoint not ready yet — continue polling.
        }

        if ($result -and $result.keys) {
            Write-Host "Keycloak JWKS endpoint is serving keys. Realm import complete."
            exit 0
        }

        Write-Host "JWKS not ready yet ($Elapsed/$Timeout s). Retrying in $Interval s..."
        Start-Sleep -Seconds $Interval
        $Elapsed += $Interval
    }

    Write-Error "ERROR: Keycloak JWKS endpoint did not become available within $Timeout seconds."
    exit 1
} finally {
    # Clean up the port-forward process
    if ($portForwardProc -and -not $portForwardProc.HasExited) {
        Stop-Process -Id $portForwardProc.Id -Force -ErrorAction SilentlyContinue
    }
}
