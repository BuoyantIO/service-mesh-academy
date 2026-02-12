# ============================================================
# Amazon Managed Prometheus (AMP)
# ============================================================

resource "aws_prometheus_workspace" "prometheus" {
  alias = var.project_suffix

  tags = {
    Name = "${var.project_suffix}-prometheus"
  }
}

resource "aws_iam_role" "prometheus_role" {
  name = "${var.project_suffix}-prometheus-role"

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
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:alloy:alloy"
        }
      }
    }]
  })
}

resource "aws_iam_policy" "prometheus_policy" {
  name = "${var.project_suffix}-prometheus-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "aps:RemoteWrite",
          "aps:QueryMetrics",
          "aps:GetSeries",
          "aps:GetLabels",
          "aps:GetMetricMetadata"
        ]
        Resource = aws_prometheus_workspace.prometheus.arn
      },
      {
        Effect = "Allow"
        Action = [
          "aps:ListWorkspaces"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "aps:DescribeWorkspace"
        ]
        Resource = aws_prometheus_workspace.prometheus.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups"
        ]
        Resource = [
          aws_cloudwatch_log_group.emojivoto.arn,
          "${aws_cloudwatch_log_group.emojivoto.arn}:*",
          aws_cloudwatch_log_group.linkerd.arn,
          "${aws_cloudwatch_log_group.linkerd.arn}:*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "prometheus_policy" {
  policy_arn = aws_iam_policy.prometheus_policy.arn
  role       = aws_iam_role.prometheus_role.name
}
