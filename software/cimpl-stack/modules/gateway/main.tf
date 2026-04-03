# Copyright 2026, Microsoft
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Stack-specific Gateway listeners, HTTPRoutes, and TLS Certificates
#
# Extends the shared Istio Gateway with HTTPS listeners for:
#   - Kibana (always, when gateway is enabled)
#   - OSDU API (conditional, path-based routing to individual services)
#   - Keycloak UI (conditional)
#   - Airflow UI (conditional)

# ─── Gateway HTTPS listeners ──────────────────────────────────────────────────
# Builds the Gateway spec as a Terraform data structure, then applies it as JSON.
# This avoids heredoc/template indentation issues with conditional YAML blocks.
# Uses always_run trigger to ensure listeners are re-applied every deploy,
# since the foundation layer or other processes could reset the Gateway to HTTP-only.

locals {
  # Helper to build an HTTPS listener entry
  _https_listener = {
    for name, cfg in {
      "https-stack-${var.stack_label}"          = { hostname = var.kibana_hostname, secret = "kibana-tls-stack-${var.stack_label}", enabled = true }
      "https-osdu-stack-${var.stack_label}"     = { hostname = var.osdu_hostname, secret = "osdu-tls-stack-${var.stack_label}", enabled = var.enable_osdu_api && var.osdu_hostname != "" }
      "https-keycloak-stack-${var.stack_label}" = { hostname = var.keycloak_hostname, secret = "keycloak-tls-stack-${var.stack_label}", enabled = var.enable_keycloak && var.keycloak_hostname != "" }
      "https-airflow-stack-${var.stack_label}"  = { hostname = var.airflow_hostname, secret = "airflow-tls-stack-${var.stack_label}", enabled = var.enable_airflow && var.airflow_hostname != "" }
    } : name => cfg if cfg.enabled
  }

  gateway_spec = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"
    metadata = {
      name      = "istio"
      namespace = "aks-istio-ingress"
    }
    spec = {
      gatewayClassName = "istio"
      addresses        = [{ value = "aks-istio-ingressgateway-external", type = "Hostname" }]
      listeners = concat(
        [{
          name          = "http"
          protocol      = "HTTP"
          port          = 80
          allowedRoutes = { namespaces = { from = "All" } }
        }],
        [for name, cfg in local._https_listener : {
          name     = name
          protocol = "HTTPS"
          port     = 443
          hostname = cfg.hostname
          tls = {
            mode = "Terminate"
            certificateRefs = [{
              kind      = "Secret"
              name      = cfg.secret
              namespace = var.namespace
            }]
          }
          allowedRoutes = { namespaces = { from = "All" } }
        }],
        var.additional_listeners
      )
    }
  }
}

resource "kubectl_manifest" "gateway_https_listener" {
  yaml_body = jsonencode(local.gateway_spec)

  server_side_apply = true
  force_conflicts   = true
}

# ─── HTTP → HTTPS redirect ─────────────────────────────────────────────────────
# Redirect all HTTP traffic to HTTPS with 307 (Temporary Redirect).
# On ROSA, OpenShift's router provides this automatically; on AKS we must
# configure it explicitly via an Istio EnvoyFilter. Gateway API's HTTPRoute
# RequestRedirect filter only supports 301/302, and VirtualService cannot
# target Gateway API gateways on AKS managed Istio. The EnvoyFilter inserts
# a Lua script on the port-80 listener that intercepts requests before routing:
#   - ACME HTTP-01 challenge paths → pass through (cert-manager needs 200)
#   - With Authorization header → 307 redirect to HTTPS (preserves method/body)
#   - Without Authorization header → 401 Unauthorized (rejects unauthenticated
#     callers without revealing the HTTPS endpoint)
# This matches OSDU service acceptance test expectations. See ADR-0014.

resource "kubectl_manifest" "https_redirect" {
  yaml_body = <<-YAML
    apiVersion: networking.istio.io/v1alpha3
    kind: EnvoyFilter
    metadata:
      name: https-redirect-307
      namespace: aks-istio-ingress
    spec:
      workloadSelector:
        labels:
          app: aks-istio-ingressgateway-external
      configPatches:
        - applyTo: HTTP_FILTER
          match:
            context: GATEWAY
            listener:
              portNumber: 80
              filterChain:
                filter:
                  name: envoy.filters.network.http_connection_manager
                  subFilter:
                    name: envoy.filters.http.router
          patch:
            operation: INSERT_BEFORE
            value:
              name: envoy.lua.https_redirect
              typed_config:
                "@type": type.googleapis.com/envoy.extensions.filters.http.lua.v3.Lua
                inline_code: |
                  function envoy_on_request(request_handle)
                    local host = request_handle:headers():get(":authority")
                    local path = request_handle:headers():get(":path")
                    local auth = request_handle:headers():get("authorization")

                    -- Allow ACME HTTP-01 challenges through for cert-manager
                    if path and string.sub(path, 1, 28) == "/.well-known/acme-challenge/" then
                      return
                    end

                    if auth and auth ~= "" then
                      request_handle:respond(
                        {[":status"] = "307", ["location"] = "https://" .. host .. path},
                        ""
                      )
                    else
                      request_handle:respond(
                        {[":status"] = "401"},
                        ""
                      )
                    end
                  end
  YAML

  server_side_apply = true
  force_conflicts   = true

  depends_on = [kubectl_manifest.gateway_https_listener]
}

# ─── Kibana ────────────────────────────────────────────────────────────────────

resource "kubectl_manifest" "kibana_route" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: kibana-route-stack-${var.stack_label}
      namespace: aks-istio-ingress
    spec:
      parentRefs:
        - name: istio
          namespace: aks-istio-ingress
      hostnames:
        - "${var.kibana_hostname}"
      rules:
        - matches:
            - path:
                type: PathPrefix
                value: /
          backendRefs:
            - name: kibana-kb-http
              namespace: ${var.namespace}
              port: 5601
  YAML

  server_side_apply = true
  force_conflicts   = true

  depends_on = [kubectl_manifest.gateway_https_listener]
}

resource "kubectl_manifest" "kibana_reference_grant" {
  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1beta1
    kind: ReferenceGrant
    metadata:
      name: allow-istio-ingress-stack-${var.stack_label}
      namespace: ${var.namespace}
    spec:
      from:
        - group: gateway.networking.k8s.io
          kind: HTTPRoute
          namespace: aks-istio-ingress
      to:
        - group: ""
          kind: Service
          name: kibana-kb-http
  YAML
}

# ─── OSDU API (path-based routing) ────────────────────────────────────────────

resource "kubectl_manifest" "osdu_api_route" {
  for_each = var.enable_osdu_api ? {
    for route in var.osdu_api_routes : route.service_name => route
  } : {}

  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: osdu-${each.value.service_name}-route-stack-${var.stack_label}
      namespace: aks-istio-ingress
    spec:
      parentRefs:
        - name: istio
          namespace: aks-istio-ingress
      hostnames:
        - "${var.osdu_hostname}"
      rules:
        - matches:
            - path:
                type: PathPrefix
                value: ${each.value.path_prefix}
          backendRefs:
            - name: ${each.value.service_name}
              namespace: ${var.osdu_namespace}
              port: 80
  YAML

  server_side_apply = true
  force_conflicts   = true

  depends_on = [kubectl_manifest.gateway_https_listener]
}

# ReferenceGrant: allow HTTPRoutes in aks-istio-ingress to reach services in osdu namespace
resource "kubectl_manifest" "osdu_reference_grant" {
  count = var.enable_osdu_api && length(var.osdu_api_routes) > 0 ? 1 : 0

  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1beta1
    kind: ReferenceGrant
    metadata:
      name: allow-istio-ingress-osdu-stack-${var.stack_label}
      namespace: ${var.osdu_namespace}
    spec:
      from:
        - group: gateway.networking.k8s.io
          kind: HTTPRoute
          namespace: aks-istio-ingress
      to:
        - group: ""
          kind: Service
  YAML
}

# ─── Keycloak ──────────────────────────────────────────────────────────────────

resource "kubectl_manifest" "keycloak_route" {
  count = var.enable_keycloak && var.keycloak_hostname != "" ? 1 : 0

  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: keycloak-route-stack-${var.stack_label}
      namespace: aks-istio-ingress
    spec:
      parentRefs:
        - name: istio
          namespace: aks-istio-ingress
      hostnames:
        - "${var.keycloak_hostname}"
      rules:
        - matches:
            - path:
                type: PathPrefix
                value: /
          backendRefs:
            - name: keycloak
              namespace: ${var.namespace}
              port: 8080
  YAML

  server_side_apply = true
  force_conflicts   = true

  depends_on = [kubectl_manifest.gateway_https_listener]
}

resource "kubectl_manifest" "keycloak_reference_grant" {
  count = var.enable_keycloak && var.keycloak_hostname != "" ? 1 : 0

  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1beta1
    kind: ReferenceGrant
    metadata:
      name: allow-istio-ingress-keycloak-stack-${var.stack_label}
      namespace: ${var.namespace}
    spec:
      from:
        - group: gateway.networking.k8s.io
          kind: HTTPRoute
          namespace: aks-istio-ingress
      to:
        - group: ""
          kind: Service
          name: keycloak
  YAML
}

# ─── Airflow ───────────────────────────────────────────────────────────────────

resource "kubectl_manifest" "airflow_route" {
  count = var.enable_airflow && var.airflow_hostname != "" ? 1 : 0

  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1
    kind: HTTPRoute
    metadata:
      name: airflow-route-stack-${var.stack_label}
      namespace: aks-istio-ingress
    spec:
      parentRefs:
        - name: istio
          namespace: aks-istio-ingress
      hostnames:
        - "${var.airflow_hostname}"
      rules:
        - matches:
            - path:
                type: PathPrefix
                value: /
          backendRefs:
            - name: airflow-webserver
              namespace: ${var.namespace}
              port: 8080
  YAML

  server_side_apply = true
  force_conflicts   = true

  depends_on = [kubectl_manifest.gateway_https_listener]
}

resource "kubectl_manifest" "airflow_reference_grant" {
  count = var.enable_airflow && var.airflow_hostname != "" ? 1 : 0

  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1beta1
    kind: ReferenceGrant
    metadata:
      name: allow-istio-ingress-airflow-stack-${var.stack_label}
      namespace: ${var.namespace}
    spec:
      from:
        - group: gateway.networking.k8s.io
          kind: HTTPRoute
          namespace: aks-istio-ingress
      to:
        - group: ""
          kind: Service
          name: airflow-webserver
  YAML
}

# ─── TLS Certificates ─────────────────────────────────────────────────────────
# Created in the stack namespace (not aks-istio-ingress) because AKS Automatic's
# ValidatingAdmissionPolicy blocks cert-manager from operating in managed system
# namespaces. The Gateway references secrets cross-namespace via ReferenceGrants.

# Kibana TLS
resource "kubectl_manifest" "kibana_certificate" {
  count = var.enable_cert_manager ? 1 : 0

  yaml_body = <<-YAML
    apiVersion: cert-manager.io/v1
    kind: Certificate
    metadata:
      name: kibana-tls-stack-${var.stack_label}
      namespace: ${var.namespace}
    spec:
      secretName: kibana-tls-stack-${var.stack_label}
      duration: 2160h
      renewBefore: 360h
      commonName: "${var.kibana_hostname}"
      dnsNames:
        - "${var.kibana_hostname}"
      issuerRef:
        name: ${var.active_cluster_issuer}
        kind: ClusterIssuer
  YAML
}

# OSDU API TLS
resource "kubectl_manifest" "osdu_certificate" {
  count = var.enable_cert_manager && var.enable_osdu_api && var.osdu_hostname != "" ? 1 : 0

  yaml_body = <<-YAML
    apiVersion: cert-manager.io/v1
    kind: Certificate
    metadata:
      name: osdu-tls-stack-${var.stack_label}
      namespace: ${var.namespace}
    spec:
      secretName: osdu-tls-stack-${var.stack_label}
      duration: 2160h
      renewBefore: 360h
      commonName: "${var.osdu_hostname}"
      dnsNames:
        - "${var.osdu_hostname}"
      issuerRef:
        name: ${var.active_cluster_issuer}
        kind: ClusterIssuer
  YAML
}

# Keycloak TLS
resource "kubectl_manifest" "keycloak_certificate" {
  count = var.enable_cert_manager && var.enable_keycloak && var.keycloak_hostname != "" ? 1 : 0

  yaml_body = <<-YAML
    apiVersion: cert-manager.io/v1
    kind: Certificate
    metadata:
      name: keycloak-tls-stack-${var.stack_label}
      namespace: ${var.namespace}
    spec:
      secretName: keycloak-tls-stack-${var.stack_label}
      duration: 2160h
      renewBefore: 360h
      commonName: "${var.keycloak_hostname}"
      dnsNames:
        - "${var.keycloak_hostname}"
      issuerRef:
        name: ${var.active_cluster_issuer}
        kind: ClusterIssuer
  YAML
}

# Airflow TLS
resource "kubectl_manifest" "airflow_certificate" {
  count = var.enable_cert_manager && var.enable_airflow && var.airflow_hostname != "" ? 1 : 0

  yaml_body = <<-YAML
    apiVersion: cert-manager.io/v1
    kind: Certificate
    metadata:
      name: airflow-tls-stack-${var.stack_label}
      namespace: ${var.namespace}
    spec:
      secretName: airflow-tls-stack-${var.stack_label}
      duration: 2160h
      renewBefore: 360h
      commonName: "${var.airflow_hostname}"
      dnsNames:
        - "${var.airflow_hostname}"
      issuerRef:
        name: ${var.active_cluster_issuer}
        kind: ClusterIssuer
  YAML
}

# ─── TLS ReferenceGrants ──────────────────────────────────────────────────────
# Allow the Gateway in aks-istio-ingress to read TLS secrets from the stack
# namespace (needed because Certificates/Secrets live here, not in the managed
# aks-istio-ingress namespace).

resource "kubectl_manifest" "kibana_tls_reference_grant" {
  count = var.enable_cert_manager ? 1 : 0

  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1beta1
    kind: ReferenceGrant
    metadata:
      name: allow-gateway-tls-stack-${var.stack_label}
      namespace: ${var.namespace}
    spec:
      from:
        - group: gateway.networking.k8s.io
          kind: Gateway
          namespace: aks-istio-ingress
      to:
        - group: ""
          kind: Secret
          name: kibana-tls-stack-${var.stack_label}
  YAML
}

resource "kubectl_manifest" "osdu_tls_reference_grant" {
  count = var.enable_cert_manager && var.enable_osdu_api && var.osdu_hostname != "" ? 1 : 0

  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1beta1
    kind: ReferenceGrant
    metadata:
      name: allow-gateway-osdu-tls-stack-${var.stack_label}
      namespace: ${var.namespace}
    spec:
      from:
        - group: gateway.networking.k8s.io
          kind: Gateway
          namespace: aks-istio-ingress
      to:
        - group: ""
          kind: Secret
          name: osdu-tls-stack-${var.stack_label}
  YAML
}

resource "kubectl_manifest" "keycloak_tls_reference_grant" {
  count = var.enable_cert_manager && var.enable_keycloak && var.keycloak_hostname != "" ? 1 : 0

  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1beta1
    kind: ReferenceGrant
    metadata:
      name: allow-gateway-keycloak-tls-stack-${var.stack_label}
      namespace: ${var.namespace}
    spec:
      from:
        - group: gateway.networking.k8s.io
          kind: Gateway
          namespace: aks-istio-ingress
      to:
        - group: ""
          kind: Secret
          name: keycloak-tls-stack-${var.stack_label}
  YAML
}

resource "kubectl_manifest" "airflow_tls_reference_grant" {
  count = var.enable_cert_manager && var.enable_airflow && var.airflow_hostname != "" ? 1 : 0

  yaml_body = <<-YAML
    apiVersion: gateway.networking.k8s.io/v1beta1
    kind: ReferenceGrant
    metadata:
      name: allow-gateway-airflow-tls-stack-${var.stack_label}
      namespace: ${var.namespace}
    spec:
      from:
        - group: gateway.networking.k8s.io
          kind: Gateway
          namespace: aks-istio-ingress
      to:
        - group: ""
          kind: Secret
          name: airflow-tls-stack-${var.stack_label}
  YAML
}
