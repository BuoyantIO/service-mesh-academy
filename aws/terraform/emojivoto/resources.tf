# ============================================================
# emojivoto – Linkerd demo application
# Equivalent to: kubectl apply -k github.com/BuoyantIO/emojivoto/kustomize/deployment
# ============================================================

locals {
  namespace      = "emojivoto"
  image_registry = "docker.l5d.io/buoyantio"
  image_tag      = "v11"
  labels = {
    "app.kubernetes.io/part-of" = "emojivoto"
    "app.kubernetes.io/version" = local.image_tag
  }
}

# ============================================================
# Namespace
# ============================================================

resource "kubernetes_namespace_v1" "emojivoto" {
  metadata {
    name = local.namespace
    annotations = {
      "linkerd.io/inject" = "enabled"
    }
  }
}

# ============================================================
# emoji – gRPC service that provides the list of emojis
# ============================================================

resource "kubernetes_service_account_v1" "emoji" {
  metadata {
    name      = "emoji"
    namespace = kubernetes_namespace_v1.emojivoto.metadata[0].name
    labels    = merge(local.labels, { "app.kubernetes.io/name" = "emoji" })
  }
}

resource "kubernetes_deployment_v1" "emoji" {
  metadata {
    name      = "emoji"
    namespace = kubernetes_namespace_v1.emojivoto.metadata[0].name
    labels    = merge(local.labels, { "app.kubernetes.io/name" = "emoji" })
  }
  spec {
    replicas = 1
    selector {
      match_labels = { "app.kubernetes.io/name" = "emoji" }
    }
    template {
      metadata {
        labels = merge(local.labels, { "app.kubernetes.io/name" = "emoji" })
      }
      spec {
        service_account_name = kubernetes_service_account_v1.emoji.metadata[0].name
        container {
          name  = "emoji-svc"
          image = "${local.image_registry}/emojivoto-emoji-svc:${local.image_tag}"
          port {
            container_port = 8080
            name           = "grpc"
          }
          port {
            container_port = 8801
            name           = "prom"
          }
          env {
            name  = "GRPC_PORT"
            value = "8080"
          }
          env {
            name  = "PROM_PORT"
            value = "8801"
          }
          resources {
            requests = { cpu = "100m" }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "emoji" {
  metadata {
    name      = "emoji-svc"
    namespace = kubernetes_namespace_v1.emojivoto.metadata[0].name
    labels    = merge(local.labels, { "app.kubernetes.io/name" = "emoji" })
  }
  spec {
    selector = { "app.kubernetes.io/name" = "emoji" }
    port {
      name        = "grpc"
      port        = 8080
      target_port = 8080
    }
    port {
      name        = "prom"
      port        = 8801
      target_port = 8801
    }
  }
}

# ============================================================
# voting – gRPC service that allows voting on emojis
# ============================================================

resource "kubernetes_service_account_v1" "voting" {
  metadata {
    name      = "voting"
    namespace = kubernetes_namespace_v1.emojivoto.metadata[0].name
    labels    = merge(local.labels, { "app.kubernetes.io/name" = "voting" })
  }
}

resource "kubernetes_deployment_v1" "voting" {
  metadata {
    name      = "voting"
    namespace = kubernetes_namespace_v1.emojivoto.metadata[0].name
    labels    = merge(local.labels, { "app.kubernetes.io/name" = "voting" })
  }
  spec {
    replicas = 1
    selector {
      match_labels = { "app.kubernetes.io/name" = "voting" }
    }
    template {
      metadata {
        labels = merge(local.labels, { "app.kubernetes.io/name" = "voting" })
      }
      spec {
        service_account_name = kubernetes_service_account_v1.voting.metadata[0].name
        container {
          name  = "voting-svc"
          image = "${local.image_registry}/emojivoto-voting-svc:${local.image_tag}"
          port {
            container_port = 8080
            name           = "grpc"
          }
          port {
            container_port = 8801
            name           = "prom"
          }
          env {
            name  = "GRPC_PORT"
            value = "8080"
          }
          env {
            name  = "PROM_PORT"
            value = "8801"
          }
          resources {
            requests = { cpu = "100m" }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "voting" {
  metadata {
    name      = "voting-svc"
    namespace = kubernetes_namespace_v1.emojivoto.metadata[0].name
    labels    = merge(local.labels, { "app.kubernetes.io/name" = "voting" })
  }
  spec {
    selector = { "app.kubernetes.io/name" = "voting" }
    port {
      name        = "grpc"
      port        = 8080
      target_port = 8080
    }
    port {
      name        = "prom"
      port        = 8801
      target_port = 8801
    }
  }
}

# ============================================================
# web – HTTP frontend + API gateway
# ============================================================

resource "kubernetes_service_account_v1" "web" {
  metadata {
    name      = "web"
    namespace = kubernetes_namespace_v1.emojivoto.metadata[0].name
    labels    = merge(local.labels, { "app.kubernetes.io/name" = "web" })
  }
}

resource "kubernetes_deployment_v1" "web" {
  metadata {
    name      = "web"
    namespace = kubernetes_namespace_v1.emojivoto.metadata[0].name
    labels    = merge(local.labels, { "app.kubernetes.io/name" = "web" })
  }
  spec {
    replicas = 1
    selector {
      match_labels = { "app.kubernetes.io/name" = "web" }
    }
    template {
      metadata {
        labels = merge(local.labels, { "app.kubernetes.io/name" = "web" })
      }
      spec {
        service_account_name = kubernetes_service_account_v1.web.metadata[0].name
        container {
          name  = "web-svc"
          image = "${local.image_registry}/emojivoto-web:${local.image_tag}"
          port {
            container_port = 8080
            name           = "http"
          }
          env {
            name  = "WEB_PORT"
            value = "8080"
          }
          env {
            name  = "EMOJISVC_HOST"
            value = "emoji-svc.${local.namespace}:8080"
          }
          env {
            name  = "VOTINGSVC_HOST"
            value = "voting-svc.${local.namespace}:8080"
          }
          env {
            name  = "INDEX_BUNDLE"
            value = "dist/index_bundle.js"
          }
          resources {
            requests = { cpu = "100m" }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "web" {
  metadata {
    name      = "web-svc"
    namespace = kubernetes_namespace_v1.emojivoto.metadata[0].name
    labels    = merge(local.labels, { "app.kubernetes.io/name" = "web" })
  }
  spec {
    selector = { "app.kubernetes.io/name" = "web" }
    port {
      name        = "http"
      port        = 80
      target_port = 8080
    }
  }
}

# ============================================================
# vote-bot – simulates traffic by voting on random emojis
# ============================================================

resource "kubernetes_deployment_v1" "vote_bot" {
  metadata {
    name      = "vote-bot"
    namespace = kubernetes_namespace_v1.emojivoto.metadata[0].name
    labels    = merge(local.labels, { "app.kubernetes.io/name" = "vote-bot" })
  }
  spec {
    replicas = 1
    selector {
      match_labels = { "app.kubernetes.io/name" = "vote-bot" }
    }
    template {
      metadata {
        labels = merge(local.labels, { "app.kubernetes.io/name" = "vote-bot" })
      }
      spec {
        container {
          name    = "vote-bot"
          image   = "${local.image_registry}/emojivoto-web:${local.image_tag}"
          command = ["emojivoto-vote-bot"]
          env {
            name  = "WEB_HOST"
            value = "web-svc.${local.namespace}:80"
          }
          resources {
            requests = { cpu = "10m" }
          }
        }
      }
    }
  }
}
