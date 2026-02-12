# ============================================================
# Project and Cluster Definitions
# ============================================================

variable "project_suffix" {
  description = "Project name"
  type        = string
  default     = "sma"
}

variable "kubernetes_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.31"
}

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-northeast-2"
}

variable "linkerd_enterprise_license" {
  description = "Linkerd Enterprise license key"
  type        = string
  sensitive   = true
}

variable "aws_profile" {
  description = "AWS CLI profile "
  type        = string
  default     = "buoyant"
}
