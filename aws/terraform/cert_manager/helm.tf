# ============================================================
# cert-manager
# ============================================================

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  set = [
    {
      name  = "crds.enabled"
      value = "true"
    },
  ]
}

# ============================================================
# AWS PCA Issuer for cert-manager
# ============================================================

resource "helm_release" "aws_pca_issuer" {
  depends_on = [helm_release.cert_manager]

  name       = "aws-privateca-issuer"
  repository = "https://cert-manager.github.io/aws-privateca-issuer"
  chart      = "aws-privateca-issuer"
  namespace  = "cert-manager"
  wait       = true
  set = [
    {
      name  = "installCRDs"
      value = "true"
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = var.pca_issuer_role_arn
    },
  ]
}

# Wait for the AWSPCAClusterIssuer CRD to be fully registered
# in the API server before attempting kubectl apply.
resource "null_resource" "await_pca_crd" {
  depends_on = [helm_release.aws_pca_issuer]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command     = <<-EOT
      set -euo pipefail
      aws eks update-kubeconfig --name ${var.cluster_name} --region ${var.aws_region} --profile ${var.aws_profile} --alias ${var.cluster_name}
      for i in $(seq 1 12); do
        if kubectl get crd awspcaclusterissuers.awspca.cert-manager.io >/dev/null 2>&1; then
          kubectl wait --for condition=established crd/awspcaclusterissuers.awspca.cert-manager.io --timeout=10s
          exit 0
        fi
        echo "Waiting for AWSPCAClusterIssuer CRD to appear... ($i/12)"
        sleep 5
      done
      echo "ERROR: CRD awspcaclusterissuers.awspca.cert-manager.io not found after 60s" >&2
      exit 1
    EOT
  }
}
