# ============================================================
# Elastic Container Registry (ECR) – one repository per image
# ============================================================

resource "aws_ecr_repository" "images" {
  for_each             = var.mirror_images
  name                 = "${var.project_suffix}/${each.key}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project_suffix}-${each.key}"
  }
}

resource "aws_ecr_lifecycle_policy" "images" {
  for_each   = aws_ecr_repository.images
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 30 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 30
      }
      action = {
        type = "expire"
      }
    }]
  })
}

# ============================================================
# Mirror container images into their ECR repositories
# ============================================================

locals {
  ecr_registry = length(aws_ecr_repository.images) > 0 ? split("/", values(aws_ecr_repository.images)[0].repository_url)[0] : ""
}

resource "null_resource" "mirror_images" {
  for_each = var.mirror_images
  triggers = {
    source_image = each.value.source
    ecr_tag      = each.value.tag
  }
  depends_on = [aws_ecr_repository.images]
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<-EOT
      set -eo pipefail
      CFGDIR=$(mktemp -d)
      trap 'rm -rf "$CFGDIR"' EXIT
      echo '{"credsStore":""}' > "$CFGDIR/config.json"
      export DOCKER_CONFIG="$CFGDIR"
      export AWS_PROFILE=${var.aws_profile}
      ECR_PASSWORD=$(aws ecr get-login-password --region ${var.region})
      echo "$ECR_PASSWORD" | crane auth login ${local.ecr_registry} --username AWS --password-stdin
      crane copy ${each.value.source} ${aws_ecr_repository.images[each.key].repository_url}:${each.value.tag}
    EOT
  }
}
