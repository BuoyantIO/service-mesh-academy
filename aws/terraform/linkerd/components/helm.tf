# ============================================================
# Linkerd Enterprise CRDs
# ============================================================

resource "helm_release" "linkerd_crds" {
  name            = "linkerd-enterprise-crds"
  repository      = "https://helm.buoyant.cloud"
  chart           = "linkerd-enterprise-crds"
  namespace       = "linkerd"
  version         = "2.19.4"
  upgrade_install = true
}

# ============================================================
# Linkerd Enterprise Control Plane
# ============================================================

resource "helm_release" "linkerd_control_plane" {
  depends_on = [helm_release.linkerd_crds]

  name            = "linkerd-enterprise-control-plane"
  repository      = "https://helm.buoyant.cloud"
  chart           = "linkerd-enterprise-control-plane"
  namespace       = "linkerd"
  version         = "2.19.4"
  upgrade_install = true
  set = [
    {
      name  = "license"
      value = var.linkerd_enterprise_license
    },
    {
      name  = "identity.externalCA"
      value = "true"
    },
    {
      name  = "identity.issuer.scheme"
      value = "kubernetes.io/tls"
    },
    # Pull images from ECR instead of ghcr.io/buoyantio
    {
      name  = "controllerImage"
      value = var.ecr_repository_urls["linkerd-controller"]
    },
    {
      name  = "proxy.image.name"
      value = var.ecr_repository_urls["linkerd-proxy"]
    },
    {
      name  = "proxy.image.version"
      value = "enterprise-2.19.4"
    },
    {
      name  = "proxyInit.image.name"
      value = var.ecr_repository_urls["linkerd-proxy-init"]
    },
    {
      name  = "proxyInit.image.version"
      value = "enterprise-2.19.4"
    },
  ]
  # Trust anchor is managed by trust-manager Bundle
  # (linkerd-identity-trust-roots ConfigMap in linkerd namespace).
  # Pass root CA PEM for initial bootstrap; trust-manager takes
  # over the ConfigMap afterwards.
  set_sensitive = [
    {
      name  = "identityTrustAnchorsPEM"
      value = var.trust_anchor_pem
    },
  ]
}
