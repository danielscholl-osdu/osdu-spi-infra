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

# ─── Bootstrap data seeding ──────────────────────────────────────────────────
# Creates a default legal tag and loads OSDU reference data via the Storage API.
# Runs as a Kubernetes Job inside the cluster — no kubectl port-forward needed
# for OSDU API calls. The deployer only uses kubectl to launch, monitor, and
# clean up the Job.
# See ADR 0022 for the rationale behind this approach.

resource "kubernetes_config_map_v1" "bootstrap_data_script" {
  count = local.deploy_bootstrap_data ? 1 : 0

  metadata {
    name      = "bootstrap-data-script"
    namespace = local.osdu_namespace
    labels    = local.common_labels
  }

  data = {
    "load.py" = file("${path.module}/scripts/bootstrap-data-seed-job.py")
  }

  depends_on = [module.osdu_common]
}

resource "null_resource" "bootstrap_data_seed" {
  count = local.deploy_bootstrap_data ? 1 : 0

  triggers = {
    script_hash = filesha256("${path.module}/scripts/bootstrap-data-seed.ps1")
    job_hash    = filesha256("${path.module}/scripts/bootstrap-data-seed-job.py")
    data_branch = local.bootstrap_data_branch
  }

  provisioner "local-exec" {
    interpreter = ["pwsh", "-Command"]
    command     = "& '${path.module}/scripts/bootstrap-data-seed.ps1' -PlatformNamespace '${local.platform_namespace}' -OsduNamespace '${local.osdu_namespace}' -CimplTenant '${var.cimpl_tenant}' -DataBranch '${local.bootstrap_data_branch}'"
  }

  depends_on = [
    kubernetes_config_map_v1.bootstrap_data_script,
    module.osdu_common,
    module.keycloak,
    module.entitlements,
    module.legal,
    module.storage,
  ]
}
