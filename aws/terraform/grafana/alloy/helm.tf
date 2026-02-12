# ============================================================
# Grafana Alloy – Linkerd proxy metrics → AMP
#                  + namespace logs → CloudWatch
# ============================================================

resource "helm_release" "alloy" {
  name             = "alloy"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "alloy"
  namespace        = "alloy"
  create_namespace = true

  values = [yamlencode({
    serviceAccount = {
      annotations = {
        "eks.amazonaws.com/role-arn" = var.prometheus_role_arn
      }
    }

    alloy = {
      clustering = {
        enabled = true
      }

      configMap = {
        content = templatefile("${path.module}/config.alloy", {
          remote_write_url       = var.prometheus_remote_write_url
          aws_region             = var.aws_region
          cw_log_group_emojivoto = var.cloudwatch_log_group_emojivoto
          cw_log_group_linkerd   = var.cloudwatch_log_group_linkerd
        })
      }
    }

    # loki.source.kubernetes needs the pods/log subresource
    rbac = {
      extraClusterRoleRules = [{
        apiGroups = [""]
        resources = ["pods/log"]
        verbs     = ["get"]
      }]
    }
  })]
}
