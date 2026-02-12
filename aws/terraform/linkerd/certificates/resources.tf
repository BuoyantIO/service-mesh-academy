# ============================================================
# Namespace — created here so that cert-manager Certificate
# resources targeting it can be applied before the Linkerd
# Helm chart is installed.
# ============================================================

resource "kubernetes_namespace_v1" "linkerd" {
  metadata {
    name = "linkerd"
    labels = {
      "linkerd.io/is-control-plane"          = "true"
      "config.linkerd.io/admission-webhooks" = "disabled"
      "linkerd.io/control-plane-ns"          = "linkerd"
    }
  }
}

# ============================================================
# Certificate — syncs root CA cert as trust anchor
# ============================================================

resource "local_file" "linkerd_trust_anchor_cert_yaml" {
  filename = "${path.module}/.terraform/rendered/linkerd-trust-anchor-cert.yaml"
  content  = templatefile("${path.root}/../manifests/linkerd-trust-anchor-cert.yaml.tmpl", {})
}

resource "null_resource" "linkerd_trust_anchor_cert" {
  depends_on = [local_file.linkerd_trust_anchor_cert_yaml]
  triggers = {
    yaml_sha = sha256(local_file.linkerd_trust_anchor_cert_yaml.content)
  }
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command     = "set -euo pipefail; kubectl apply -f ${local_file.linkerd_trust_anchor_cert_yaml.filename}"
  }
}

# ============================================================
# Certificate — creates the linkerd-identity-issuer secret
# ============================================================

resource "local_file" "linkerd_identity_issuer_cert_yaml" {
  filename = "${path.module}/.terraform/rendered/linkerd-identity-issuer-cert.yaml"
  content  = templatefile("${path.root}/../manifests/linkerd-identity-issuer-cert.yaml.tmpl", {})
}

resource "null_resource" "linkerd_identity_issuer_cert" {
  depends_on = [
    kubernetes_namespace_v1.linkerd,
    local_file.linkerd_identity_issuer_cert_yaml,
  ]
  triggers = {
    yaml_sha = sha256(local_file.linkerd_identity_issuer_cert_yaml.content)
  }
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command     = "set -euo pipefail; kubectl apply -f ${local_file.linkerd_identity_issuer_cert_yaml.filename}"
  }
}
