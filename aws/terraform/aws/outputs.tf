# ============================================================
# Cluster Outputs
# ============================================================

output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.eks_cluster.name
}

output "kube_config" {
  description = "Kube config for the EKS cluster"
  value = {
    host                   = aws_eks_cluster.eks_cluster.endpoint
    cluster_ca_certificate = aws_eks_cluster.eks_cluster.certificate_authority[0].data
  }
  sensitive = true
}

# ============================================================
# ECR Outputs
# ============================================================

output "ecr_repository_urls" {
  description = "Map of image name → ECR repository URL"
  value       = { for k, v in aws_ecr_repository.images : k => v.repository_url }
}

output "ecr_registry_url" {
  description = "Base ECR registry URL (e.g. <account>.dkr.ecr.<region>.amazonaws.com)"
  value       = local.ecr_registry
}

# ============================================================
# AWS Private CA Outputs
# ============================================================

output "pca_root_ca_arn" {
  description = "ARN of the root CA (trust anchor)"
  value       = aws_acmpca_certificate_authority.root.arn
}

output "pca_root_ca_cert_pem" {
  description = "Root CA certificate PEM (Linkerd trust anchor)"
  value       = aws_acmpca_certificate.root.certificate
  sensitive   = true
}

output "pca_issuer_ca_arn" {
  description = "ARN of the subordinate CA (identity issuer)"
  value       = aws_acmpca_certificate_authority.issuer.arn
}

output "pca_issuer_role_arn" {
  description = "IAM role ARN for the aws-privateca-issuer service account"
  value       = aws_iam_role.pca_issuer_role.arn
}

# ============================================================
# OIDC Outputs
# ============================================================

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider for EKS"
  value       = aws_iam_openid_connect_provider.eks.arn
}

# ============================================================
# CloudWatch Outputs
# ============================================================

output "cloudwatch_log_group_eks" {
  description = "CloudWatch log group name for EKS cluster"
  value       = aws_cloudwatch_log_group.eks_cluster.name
}

output "cloudwatch_log_group_application" {
  description = "CloudWatch log group name for application logs"
  value       = aws_cloudwatch_log_group.application.name
}

output "cloudwatch_agent_role_arn" {
  description = "IAM role ARN for CloudWatch agent"
  value       = aws_iam_role.cloudwatch_agent_role.arn
}

output "cloudwatch_log_group_emojivoto" {
  description = "CloudWatch log group name for emojivoto logs"
  value       = aws_cloudwatch_log_group.emojivoto.name
}

output "cloudwatch_log_group_linkerd" {
  description = "CloudWatch log group name for linkerd logs"
  value       = aws_cloudwatch_log_group.linkerd.name
}

# ============================================================
# Prometheus Outputs
# ============================================================

output "prometheus_workspace_id" {
  description = "The ID of the Amazon Managed Prometheus workspace"
  value       = aws_prometheus_workspace.prometheus.id
}

output "prometheus_endpoint" {
  description = "The endpoint URL for the Amazon Managed Prometheus workspace"
  value       = aws_prometheus_workspace.prometheus.prometheus_endpoint
}

output "prometheus_remote_write_url" {
  description = "The remote write URL for Prometheus"
  value       = "${aws_prometheus_workspace.prometheus.prometheus_endpoint}api/v1/remote_write"
}

output "prometheus_role_arn" {
  description = "IAM role ARN for Prometheus service account"
  value       = aws_iam_role.prometheus_role.arn
}

# ============================================================
# Grafana Outputs
# ============================================================

output "grafana_workspace_id" {
  description = "The ID of the Amazon Managed Grafana workspace"
  value       = aws_grafana_workspace.grafana.id
}

output "grafana_endpoint" {
  description = "The endpoint URL for the Amazon Managed Grafana workspace"
  value       = aws_grafana_workspace.grafana.endpoint
}

output "grafana_api_key" {
  description = "Grafana workspace API key for programmatic access (dashboard provisioning)"
  value       = aws_grafana_workspace_api_key.terraform.key
  sensitive   = true
}

output "grafana_service_provider_identifier_url" {
  description = "Service provider identifier (Entity ID) for the Amazon Managed Grafana workspace SAML configuration"
  value       = "https://${aws_grafana_workspace.grafana.endpoint}/saml/metadata"
}

output "grafana_service_provider_reply_url" {
  description = "Service provider reply URL (Assertion Consumer Service URL) for the Amazon Managed Grafana workspace SAML configuration"
  value       = "https://${aws_grafana_workspace.grafana.endpoint}/saml/acs"
}

output "grafana_sign_on_url" {
  description = "Service provider-initiated sign-on URL for the Amazon Managed Grafana workspace"
  value       = "https://${aws_grafana_workspace.grafana.endpoint}/login/saml"
}

output "grafana_documentation_url" {
  description = "AWS Grafana service SAML authentication"
  value       = "https://docs.aws.amazon.com/grafana/latest/userguide/authentication-in-AMG-SAML.html#authentication-in-AMG-SAML-providers"
}

output "azure_metadata_url" {
  description = "Azure Metadata URL Template"
  value       = "https://login.microsoftonline.com/00434baa-68ec-4d73-b0a2-fec5bac28891/federationmetadata/2007-06/federationmetadata.xml?appid=APP_ID"
}

