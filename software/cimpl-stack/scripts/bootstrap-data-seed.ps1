<#
.SYNOPSIS
  Launches a Kubernetes Job to create a default legal tag and load OSDU
  reference data into the platform.

.DESCRIPTION
  Tier 1 platform bootstrap — orchestrates an in-cluster Kubernetes Job that:
    1. Obtains a Keycloak token via in-cluster FQDN (no port-forward)
    2. Creates the default legal tag via the Legal API
    3. Downloads reference-data manifests from the data-definitions GitLab repo
    4. Loads records via the Storage API in batches

  The deployer's machine only runs kubectl commands to launch, monitor, and
  clean up the Job. All OSDU API traffic stays inside the cluster.

  See ADR 0022 for the rationale behind this approach.

.PARAMETER PlatformNamespace
  Kubernetes namespace where middleware (Keycloak) is deployed.

.PARAMETER OsduNamespace
  Kubernetes namespace where OSDU services are deployed.

.PARAMETER CimplTenant
  Data partition ID (e.g., "osdu").

.PARAMETER LegalTagName
  Name of the default legal tag to create (default: "osdu-demo-legaltag").

.PARAMETER DataBranch
  Git ref of the data-definitions repo to download (default: "v0.27.0").

.PARAMETER BatchSize
  Number of records per Storage API PUT request (default: 500).
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$PlatformNamespace,

    [Parameter(Mandatory = $true)]
    [string]$OsduNamespace,

    [Parameter(Mandatory = $true)]
    [string]$CimplTenant,

    [string]$LegalTagName = "osdu-demo-legaltag",

    [string]$DataBranch = "v0.27.0",

    [int]$BatchSize = 500
)

$ErrorActionPreference = 'Stop'

$JobName = "bootstrap-data-seed-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

# ─── Pre-flight checks ──────────────────────────────────────────────────────

Write-Host "`n══════════════════════════════════════════════════════"
Write-Host "  Pre-flight: verifying cluster resources"
Write-Host "══════════════════════════════════════════════════════"

$cmCheck = kubectl get configmap bootstrap-data-script -n $OsduNamespace -o name 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "ConfigMap 'bootstrap-data-script' not found in namespace '$OsduNamespace'. Ensure Terraform has created it."
}
Write-Host "  ConfigMap 'bootstrap-data-script' found."

$secCheck = kubectl get secret datafier-secret -n $OsduNamespace -o name 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Secret 'datafier-secret' not found in namespace '$OsduNamespace'."
}
Write-Host "  Secret 'datafier-secret' found."

# ─── Delete any previous Job with the same prefix ───────────────────────────

$existing = kubectl get jobs -n $OsduNamespace -l app.kubernetes.io/component=bootstrap-data -o name 2>$null
if ($existing) {
    Write-Host "  Cleaning up previous bootstrap Job(s)..."
    kubectl delete jobs -n $OsduNamespace -l app.kubernetes.io/component=bootstrap-data --ignore-not-found 2>$null | Out-Null
    # Brief wait for pods to terminate
    Start-Sleep -Seconds 3
}

# ─── Build and apply the Job manifest ────────────────────────────────────────

Write-Host "`n══════════════════════════════════════════════════════"
Write-Host "  Launching bootstrap Job: $JobName"
Write-Host "══════════════════════════════════════════════════════"

$jobYaml = @"
apiVersion: batch/v1
kind: Job
metadata:
  name: $JobName
  namespace: $OsduNamespace
  labels:
    app.kubernetes.io/managed-by: terraform
    app.kubernetes.io/component: bootstrap-data
spec:
  backoffLimit: 2
  activeDeadlineSeconds: 1800
  ttlSecondsAfterFinished: 300
  template:
    metadata:
      labels:
        app.kubernetes.io/component: bootstrap-data
      annotations:
        sidecar.istio.io/inject: "false"
    spec:
      restartPolicy: Never
      serviceAccountName: bootstrap-sa
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: loader
          image: python:3.12-slim
          command: ["sh", "-c", "pip install --no-cache-dir --target /tmp/pylibs requests && PYTHONPATH=/tmp/pylibs python /scripts/load.py"]
          env:
            - name: PYTHONUNBUFFERED
              value: "1"
            - name: KEYCLOAK_URL
              value: "http://keycloak.${PlatformNamespace}.svc.cluster.local"
            - name: LEGAL_URL
              value: "http://legal.${OsduNamespace}.svc.cluster.local"
            - name: STORAGE_URL
              value: "http://storage.${OsduNamespace}.svc.cluster.local"
            - name: DATA_PARTITION
              value: "$CimplTenant"
            - name: LEGAL_TAG_NAME
              value: "$LegalTagName"
            - name: DATA_BRANCH
              value: "$DataBranch"
            - name: BATCH_SIZE
              value: "$BatchSize"
          envFrom:
            - secretRef:
                name: datafier-secret
          volumeMounts:
            - name: script
              mountPath: /scripts
              readOnly: true
          resources:
            requests:
              cpu: 500m
              memory: 512Mi
            limits:
              cpu: "2"
              memory: 1Gi
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
      volumes:
        - name: script
          configMap:
            name: bootstrap-data-script
"@

$jobYaml | kubectl apply -f - 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Failed to create Job '$JobName'."
}
Write-Host "  Job created."

# ─── Stream logs ─────────────────────────────────────────────────────────────

Write-Host "`n══════════════════════════════════════════════════════"
Write-Host "  Streaming Job logs"
Write-Host "══════════════════════════════════════════════════════"

# Wait for the pod to be created and start running
$deadline = [datetime]::UtcNow.AddSeconds(120)
$podReady = $false
while ([datetime]::UtcNow -lt $deadline) {
    $podPhase = kubectl get pods -n $OsduNamespace -l "job-name=$JobName" -o jsonpath='{.items[0].status.phase}' 2>$null
    if ($podPhase -eq "Running" -or $podPhase -eq "Succeeded" -or $podPhase -eq "Failed") {
        $podReady = $true
        break
    }
    Start-Sleep -Seconds 3
}

if ($podReady) {
    # Stream logs — this blocks until the pod completes
    kubectl logs -n $OsduNamespace -l "job-name=$JobName" --follow 2>$null
} else {
    Write-Host "  WARNING: Pod not ready after 120s, skipping log streaming."
}

# ─── Wait for Job completion and check result ────────────────────────────────

Write-Host "`n══════════════════════════════════════════════════════"
Write-Host "  Waiting for Job completion"
Write-Host "══════════════════════════════════════════════════════"

kubectl wait --for=condition=complete --timeout=1800s job/$JobName -n $OsduNamespace 2>$null
$jobSucceeded = $LASTEXITCODE -eq 0

if (-not $jobSucceeded) {
    # Check if it failed (vs timed out)
    $jobFailed = kubectl wait --for=condition=failed --timeout=5s job/$JobName -n $OsduNamespace 2>$null
    # Capture final logs if we didn't stream them
    if (-not $podReady) {
        Write-Host "  Final Job logs:"
        kubectl logs -n $OsduNamespace -l "job-name=$JobName" --tail=50 2>$null
    }
}

# ─── Cleanup ─────────────────────────────────────────────────────────────────

Write-Host "`n  Cleaning up Job '$JobName'..."
kubectl delete job $JobName -n $OsduNamespace --ignore-not-found 2>$null | Out-Null

if (-not $jobSucceeded) {
    throw "Bootstrap data seed Job failed. Check logs above for details."
}

Write-Host "`n  Bootstrap data seed completed successfully.`n"
