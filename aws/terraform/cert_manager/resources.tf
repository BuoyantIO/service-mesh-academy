# ============================================================
# AWSPCAClusterIssuer — root CA (trust anchor)
# ============================================================

resource "local_file" "pca_root_ca_cluster_issuer_yaml" {
  filename = "${path.module}/.terraform/rendered/pca-root-ca-cluster-issuer.yaml"
  content = templatefile("${path.root}/../manifests/pca-root-ca-cluster-issuer.yaml.tmpl", {
    pca_root_ca_arn = var.pca_root_ca_arn
    region          = var.aws_region
  })
}

resource "null_resource" "pca_root_ca_cluster_issuer" {
  depends_on = [
    null_resource.await_pca_crd,
    local_file.pca_root_ca_cluster_issuer_yaml,
  ]
  triggers = {
    yaml_sha = sha256(local_file.pca_root_ca_cluster_issuer_yaml.content)
  }
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command     = "set -euo pipefail; aws eks update-kubeconfig --name ${var.cluster_name} --region ${var.aws_region} --profile ${var.aws_profile} --alias ${var.cluster_name}; kubectl apply -f ${local_file.pca_root_ca_cluster_issuer_yaml.filename}"
  }
}

# ============================================================
# AWSPCAClusterIssuer — subordinate CA (identity issuer)
# ============================================================

resource "local_file" "pca_cluster_issuer_yaml" {
  filename = "${path.module}/.terraform/rendered/pca-cluster-issuer.yaml"
  content = templatefile("${path.root}/../manifests/pca-cluster-issuer.yaml.tmpl", {
    pca_issuer_ca_arn = var.pca_issuer_ca_arn
    region            = var.aws_region
  })
}

resource "null_resource" "pca_cluster_issuer" {
  depends_on = [
    null_resource.await_pca_crd,
    local_file.pca_cluster_issuer_yaml,
  ]
  triggers = {
    yaml_sha = sha256(local_file.pca_cluster_issuer_yaml.content)
  }
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command     = "set -euo pipefail; aws eks update-kubeconfig --name ${var.cluster_name} --region ${var.aws_region} --profile ${var.aws_profile} --alias ${var.cluster_name}; kubectl apply -f ${local_file.pca_cluster_issuer_yaml.filename}"
  }
}
