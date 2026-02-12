# ============================================================
# CloudWatch
# ============================================================

resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = 30

  tags = {
    Name = "${var.cluster_name}-logs"
  }
}

resource "aws_cloudwatch_log_group" "application" {
  name              = "/aws/${var.project_suffix}/application"
  retention_in_days = 30

  tags = {
    Name = "${var.project_suffix}-application-logs"
  }
}

resource "aws_cloudwatch_log_group" "emojivoto" {
  name              = "/aws/${var.project_suffix}/emojivoto"
  retention_in_days = 30

  tags = {
    Name = "${var.project_suffix}-emojivoto-logs"
  }
}

resource "aws_cloudwatch_log_group" "linkerd" {
  name              = "/aws/${var.project_suffix}/linkerd"
  retention_in_days = 30

  tags = {
    Name = "${var.project_suffix}-linkerd-logs"
  }
}

# Pre-create log streams used by Alloy's OTLP → CloudWatch pipeline.
# The OTLP HTTP endpoint returns a 400 if a referenced log stream does not exist,
# so we provision the shared stream name ahead of time.
resource "aws_cloudwatch_log_stream" "emojivoto_alloy" {
  name           = "alloy"
  log_group_name = aws_cloudwatch_log_group.emojivoto.name
}

resource "aws_cloudwatch_log_stream" "linkerd_alloy" {
  name           = "alloy"
  log_group_name = aws_cloudwatch_log_group.linkerd.name
}

resource "aws_iam_role" "cloudwatch_agent_role" {
  name = "${var.project_suffix}-cloudwatch-agent-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:amazon-cloudwatch:cloudwatch-agent"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent_policy" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = aws_iam_role.cloudwatch_agent_role.name
}

resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name                = aws_eks_cluster.eks_cluster.name
  addon_name                  = "amazon-cloudwatch-observability"
  service_account_role_arn    = aws_iam_role.cloudwatch_agent_role.arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.linux_node_group]
}
