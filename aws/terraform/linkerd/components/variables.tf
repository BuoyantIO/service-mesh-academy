variable "linkerd_enterprise_license" {
  description = "Linkerd Enterprise license key"
  type        = string
  sensitive   = true
}

variable "trust_anchor_pem" {
  description = "PEM-encoded trust anchor certificate from AWS PCA"
  type        = string
  sensitive   = true
  default     = ""
}

variable "ecr_repository_urls" {
  description = "Map of image name → ECR repository URL"
  type        = map(string)
}
