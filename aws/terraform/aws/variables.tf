# ============================================================
# Project and Cluster Definitions
# ============================================================

variable "project_suffix" {
  description = "Project name"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "vpc_cidr_base" {
  description = "AWS VPC CIDR base"
  type        = string
}

variable "region" {
  description = "AWS region (used by the image mirror local-exec)"
  type        = string
}

variable "aws_profile" {
  description = "AWS CLI profile used by local-exec provisioners"
  type        = string
}

variable "mirror_images" {
  description = "Map of repo name → {source, tag} to create ECR repositories and mirror images"
  type = map(object({
    source = string
    tag    = string
  }))
  default = {}
}

