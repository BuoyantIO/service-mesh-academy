# ============================================================
# Prometheus Data Source
# ============================================================

resource "grafana_data_source" "prometheus" {
  type = "grafana-amazonprometheus-datasource"
  name = "Amazon Managed Prometheus"
  url  = var.prometheus_endpoint

  json_data_encoded = jsonencode({
    httpMethod    = "GET"
    sigV4Auth     = true
    sigV4Region   = var.aws_region
    sigV4AuthType = "workspace-iam-role"
  })
}

# ============================================================
# Linkerd Dashboards (from grafana.com)
# ============================================================

locals {
  dashboards = {
    linkerd_authority  = 15482
    linkerd_deployment = 15475
    linkerd_namespace  = 15478
    linkerd_service    = 15480
  }
}

data "http" "dashboards" {
  for_each = local.dashboards
  url      = "https://grafana.com/api/dashboards/${each.value}/revisions/latest/download"

  request_headers = {
    Accept = "application/json"
  }
}

resource "grafana_dashboard" "linkerd" {
  for_each = local.dashboards

  config_json = replace(
    data.http.dashboards[each.key].response_body,
    "\"$${DS_PROMETHEUS}\"",
    jsonencode(grafana_data_source.prometheus.uid)
  )

  overwrite = true
}
