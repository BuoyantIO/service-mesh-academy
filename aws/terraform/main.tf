
module "aws_infrastructure" {
  source             = "./aws"
  project_suffix     = local.project_suffix
  kubernetes_version = var.kubernetes_version
  cluster_name       = local.eks_cluster_name
  vpc_cidr_base      = local.aws_vpc_cidr
  region             = var.aws_region
  aws_profile        = "buoyant"

  mirror_images = {
    linkerd-controller = {
      source = "ghcr.io/buoyantio/controller:enterprise-2.19.4"
      tag    = "enterprise-2.19.4"
    }
    linkerd-proxy = {
      source = "ghcr.io/buoyantio/proxy:enterprise-2.19.4"
      tag    = "enterprise-2.19.4"
    }
    linkerd-proxy-init = {
      source = "ghcr.io/buoyantio/proxy-init:enterprise-2.19.4"
      tag    = "enterprise-2.19.4"
    }
  }
}

# ============================================================
# cert-manager + AWS PCA Issuer
# ============================================================

module "cert_manager" {
  source     = "./cert_manager"
  depends_on = [module.aws_infrastructure]
  providers = {
    helm = helm.sma_eks_1
  }

  pca_root_ca_arn     = module.aws_infrastructure.pca_root_ca_arn
  pca_issuer_ca_arn   = module.aws_infrastructure.pca_issuer_ca_arn
  pca_issuer_role_arn = module.aws_infrastructure.pca_issuer_role_arn
  cluster_name        = local.eks_cluster_name
  aws_profile         = "buoyant"
}

# ============================================================
# Linkerd certificates (namespace + cert-manager Certificates)
# ============================================================

module "linkerd_certs" {
  source     = "./linkerd/certificates"
  depends_on = [module.cert_manager]
  providers = {
    kubernetes = kubernetes.sma_eks_1
  }
}

# ============================================================
# trust-manager
# ============================================================

module "trust_manager" {
  source     = "./trust_manager"
  depends_on = [module.linkerd_certs]
  providers = {
    helm = helm.sma_eks_1
  }
}

# ============================================================
# Linkerd Enterprise
# ============================================================

module "linkerd" {
  source = "./linkerd/components"
  depends_on = [
    module.linkerd_certs,
    module.trust_manager,
  ]
  providers = {
    helm = helm.sma_eks_1
  }

  linkerd_enterprise_license = var.linkerd_enterprise_license
  trust_anchor_pem           = module.aws_infrastructure.pca_root_ca_cert_pem
  ecr_repository_urls        = module.aws_infrastructure.ecr_repository_urls
}

# ============================================================
# Grafana Alloy (metrics → AMP, logs → CloudWatch)
# ============================================================

module "alloy" {
  source     = "./grafana/alloy"
  depends_on = [module.linkerd]
  providers = {
    helm = helm.sma_eks_1
  }

  prometheus_remote_write_url    = module.aws_infrastructure.prometheus_remote_write_url
  prometheus_role_arn            = module.aws_infrastructure.prometheus_role_arn
  aws_region                     = var.aws_region
  cloudwatch_log_group_emojivoto = module.aws_infrastructure.cloudwatch_log_group_emojivoto
  cloudwatch_log_group_linkerd   = module.aws_infrastructure.cloudwatch_log_group_linkerd
}

# ============================================================
# Grafana Dashboards (Linkerd dashboards from grafana.com)
# ============================================================

module "grafana_dashboards" {
  source     = "./grafana/dashboard"
  depends_on = [module.alloy]
  providers = {
    grafana = grafana.amg
  }

  grafana_endpoint    = module.aws_infrastructure.grafana_endpoint
  grafana_api_key     = module.aws_infrastructure.grafana_api_key
  prometheus_endpoint = module.aws_infrastructure.prometheus_endpoint
  aws_region          = var.aws_region
}

# ============================================================
# emojivoto – Linkerd demo application
# ============================================================

# module "emojivoto" {
#   source     = "./emojivoto"
#   depends_on = [module.linkerd]
#   providers = {
#     kubernetes = kubernetes.sma_eks_1
#   }

#   ecr_repository_url = module.aws_infrastructure.ecr_repository_url
# }
