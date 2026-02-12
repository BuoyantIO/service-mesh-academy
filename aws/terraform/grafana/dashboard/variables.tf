variable "grafana_endpoint" {
  description = "Amazon Managed Grafana workspace endpoint"
  type        = string
}

variable "grafana_api_key" {
  description = "Grafana API key for programmatic access"
  type        = string
  sensitive   = true
}

variable "prometheus_endpoint" {
  description = "Amazon Managed Prometheus endpoint URL"
  type        = string
}

variable "aws_region" {
  description = "AWS region for SigV4 authentication"
  type        = string
}
