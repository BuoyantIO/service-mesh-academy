# ============================================================
# Bundle — publishes trust anchors for Linkerd
# ============================================================

resource "local_file" "linkerd_ca_bundle_yaml" {
  filename = "${path.module}/.terraform/rendered/linkerd-ca-bundle.yaml"
  content  = templatefile("${path.root}/../manifests/linkerd-ca-bundle.yaml.tmpl", {})
}

resource "null_resource" "linkerd_ca_bundle" {
  depends_on = [
    helm_release.trust_manager,
    local_file.linkerd_ca_bundle_yaml,
  ]

  triggers = {
    yaml_sha = sha256(local_file.linkerd_ca_bundle_yaml.content)
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command     = "set -euo pipefail; kubectl apply -f ${local_file.linkerd_ca_bundle_yaml.filename}"
  }
}
