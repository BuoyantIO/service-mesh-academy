terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.25.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.7.1"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    grafana = {
      source  = "grafana/grafana"
      version = ">= 3.0.0"
    }
  }
}

# ============================================================
# Providers
# ============================================================

provider "aws" {
  region  = var.aws_region
  profile = "buoyant"
}

provider "kubernetes" {
  alias                  = "sma_eks_1"
  host                   = module.aws_infrastructure.kube_config.host
  cluster_ca_certificate = base64decode(module.aws_infrastructure.kube_config.cluster_ca_certificate)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # Use the same AWS profile as the AWS provider so the token is issued with the right identity.
    args = ["eks", "get-token", "--cluster-name", local.eks_cluster_name, "--region", var.aws_region, "--profile", "buoyant"]
  }
}

provider "grafana" {
  alias = "amg"
  url   = "https://${module.aws_infrastructure.grafana_endpoint}"
  auth  = module.aws_infrastructure.grafana_api_key
}

provider "helm" {
  alias = "sma_eks_1"
  kubernetes = {
    host                   = module.aws_infrastructure.kube_config.host
    cluster_ca_certificate = base64decode(module.aws_infrastructure.kube_config.cluster_ca_certificate)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # Ensure Helm uses the same AWS profile for cluster authentication.
      args = ["eks", "get-token", "--cluster-name", local.eks_cluster_name, "--region", var.aws_region, "--profile", "buoyant"]
    }
  }
}
