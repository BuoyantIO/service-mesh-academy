# ============================================================
# Cluster Outputs
# ============================================================

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.aws_infrastructure.cluster_name
}

output "kube_config" {
  description = "Kube config for the EKS cluster"
  value       = module.aws_infrastructure.kube_config
  sensitive   = true
}

# ============================================================
# ECR Outputs
# ============================================================

output "ecr_repository_urls" {
  description = "Map of image name → ECR repository URL"
  value       = module.aws_infrastructure.ecr_repository_urls
}

# ============================================================
# CloudWatch Outputs
# ============================================================

output "cloudwatch_log_group_eks" {
  description = "CloudWatch log group name for EKS cluster"
  value       = module.aws_infrastructure.cloudwatch_log_group_eks
}

output "cloudwatch_log_group_application" {
  description = "CloudWatch log group name for application logs"
  value       = module.aws_infrastructure.cloudwatch_log_group_application
}

output "cloudwatch_agent_role_arn" {
  description = "IAM role ARN for CloudWatch agent"
  value       = module.aws_infrastructure.cloudwatch_agent_role_arn
}

# ============================================================
# Prometheus Outputs
# ============================================================

output "prometheus_workspace_id" {
  description = "The ID of the Amazon Managed Prometheus workspace"
  value       = module.aws_infrastructure.prometheus_workspace_id
}

output "prometheus_endpoint" {
  description = "The endpoint URL for the Amazon Managed Prometheus workspace"
  value       = module.aws_infrastructure.prometheus_endpoint
}

output "prometheus_remote_write_url" {
  description = "The remote write URL for Prometheus"
  value       = module.aws_infrastructure.prometheus_remote_write_url
}

output "prometheus_role_arn" {
  description = "IAM role ARN for Prometheus service account"
  value       = module.aws_infrastructure.prometheus_role_arn
}

# ============================================================
# Grafana Outputs
# ============================================================

output "grafana_service_provider_identifier_url" {
  description = "Service provider identifier (Entity ID) for the Amazon Managed Grafana workspace SAML configuration"
  value       = module.aws_infrastructure.grafana_service_provider_identifier_url
}

output "grafana_service_provider_reply_url" {
  description = "Service provider reply URL (Assertion Consumer Service URL) for the Amazon Managed Grafana workspace SAML configuration"
  value       = module.aws_infrastructure.grafana_service_provider_reply_url
}

output "grafana_sign_on_url" {
  description = "Service provider-initiated sign-on URL for the Amazon Managed Grafana workspace"
  value       = module.aws_infrastructure.grafana_sign_on_url
}

# ============================================================
# Grafana SAML Setup Guide
# ============================================================

output "grafana_saml_setup_instructions" {
  description = "Step-by-step guide to configure Azure AD SAML SSO for Amazon Managed Grafana"
  value = <<-EOT
  1) Login to Azure
  2) Select Microsoft Entra
  3) Select Enterprise applications
  4) New Application
  5) Search for Amazon Managed Grafana
  6) Click Create
  7) From the Enterprise Applications list select Amazon Managed Grafana
  8) Click Single Sign-on
  9) In Basic SAML Configuration set:
     - Identifier (Entity ID): https://${module.aws_infrastructure.grafana_endpoint}/saml/metadata
     - Reply URL (Assertion Consumer Service URL): https://${module.aws_infrastructure.grafana_endpoint}/saml/acs
     - Sign on URL: https://${module.aws_infrastructure.grafana_endpoint}/login/saml
 10) In Attributes & Claims add:
     - Claim Name: grafana_role
     - Source attribute: user.displayname
 11) In AWS Console open the Grafana Workspace, Authentication tab, click SAML configuration
 12) Metadata URL: https://login.microsoftonline.com/TENANT_ID/federationmetadata/2007-06/federationmetadata.xml?appid=APP_ID
 13) Assertion attribute role: grafana_role
 14) Admin role values: Admin
  EOT
}
