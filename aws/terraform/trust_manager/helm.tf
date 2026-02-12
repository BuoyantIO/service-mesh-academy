# ============================================================
# trust-manager
# ============================================================

resource "helm_release" "trust_manager" {
  name             = "trust-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "trust-manager"
  namespace        = "cert-manager"
  create_namespace = false

  # Equivalent to: helm install trust-manager --namespace cert-manager --set app.trust.namespace=cert-manager --wait
  wait = true

  set = [
    {
      name  = "app.trust.namespace"
      value = "cert-manager"
    },
  ]
}
