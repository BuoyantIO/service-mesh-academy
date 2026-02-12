variable "pca_root_ca_arn" {
  description = "ARN of the AWS PCA root CA (trust anchor)"
  type        = string
  default     = ""
}

variable "pca_issuer_ca_arn" {
  description = "ARN of the AWS PCA subordinate CA for identity issuance"
  type        = string
  default     = ""
}

variable "pca_issuer_role_arn" {
  description = "IAM role ARN for the aws-privateca-issuer service account (IRSA)"
  type        = string
  default     = ""
}

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-northeast-2"
}

variable "cluster_name" {
  description = "Name of the EKS cluster (for kubectl authentication in local-exec)"
  type        = string
}

variable "aws_profile" {
  description = "AWS CLI profile for kubectl authentication"
  type        = string
}
