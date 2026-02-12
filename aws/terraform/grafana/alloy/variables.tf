# ============================================================
# Alloy Configuration Variables
# ============================================================

variable "prometheus_remote_write_url" {
  description = "AMP remote write URL"
  type        = string
}

variable "prometheus_role_arn" {
  description = "IAM role ARN for the Alloy service account (IRSA)"
  type        = string
}

variable "aws_region" {
  description = "AWS region for SigV4 signing"
  type        = string
}

variable "cloudwatch_log_group_emojivoto" {
  description = "CloudWatch log group name for emojivoto namespace logs"
  type        = string
}

variable "cloudwatch_log_group_linkerd" {
  description = "CloudWatch log group name for linkerd namespace logs"
  type        = string
}
