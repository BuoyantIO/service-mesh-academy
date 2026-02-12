locals {
  # ============================================================
  # Project and Cluster Definitions
  # ============================================================

  project_suffix   = "sma"
  eks_cluster_name = "${local.project_suffix}-eks-1"

  # ============================================================
  # Network Configuration Bases
  # ============================================================

  pod_cidr_base     = "10.240.0.0/12"
  service_cidr_base = "10.16.0.0/12"
  vnet_cidr_base    = "10.0.0.0/8"
  aws_vpc_cidr      = cidrsubnet(local.vnet_cidr_base, 2, 2)
}
