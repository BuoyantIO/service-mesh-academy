# ============================================================
# Amazon Managed Grafana (AMG)
# ============================================================

resource "aws_grafana_workspace" "grafana" {
  name                     = "${var.project_suffix}-grafana-003"
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["SAML"]
  permission_type          = "CUSTOMER_MANAGED"
  role_arn                 = aws_iam_role.grafana_role.arn
  data_sources             = ["CLOUDWATCH", "PROMETHEUS"]

  configuration = jsonencode({
    plugins = {
      pluginAdminEnabled = true
    }
    unifiedAlerting = {
      enabled = true
    }
  })

  tags = {
    Name = "${var.project_suffix}-grafana"
  }
}

# ============================================================
# Grafana API Key (enables dashboard provisioning before SAML)
# ============================================================

resource "aws_grafana_workspace_api_key" "terraform" {
  key_name        = "terraform"
  key_role        = "ADMIN"
  seconds_to_live = 2592000 # 30 days
  workspace_id    = aws_grafana_workspace.grafana.id
}
