#!/usr/bin/env bash
###################################################################################################################
# Created on: 1.9.26
# Made with Love by: Phil Henderson
# Version 1.0
# Purpose:
#   1) Create a k3d cluster and install Linkerd Enterprise using cert-manager + trust-manager
#      (external CA), plus Gateway API.
#   2) Install the full Linkerd o11y stack via Helm into the monitoring namespace:
#      Loki, Tempo, kube-prometheus-stack (Prometheus+Grafana), Alloy.
#
# Usage:
#   export BUOYANT_LICENSE='...'
#   ./create.sh
#
# Optional env vars:
#   # Cluster / kube context
#   CLUSTER_NAME=sma
#   SERVERS=3
#   WAIT=true
#   CONTEXT=                          # if set, uses this kube context for kubectl/helm (otherwise current)
#
#   # Namespaces
#   LINKERD_NS=linkerd
#   CERT_MANAGER_NS=cert-manager
#   MONITORING_NS=monitoring
#   ENABLE_MONITORING_NS_INJECT=true|false   (default: true)
#
#   # Versions / paths
#   GATEWAY_API_VERSION=v1.4.0
#   HA_VALUES_PATH=linkerd-enterprise-control-plane/values-ha.yaml
#
#   # Helm behavior
#   SKIP_REPO_ADD=false|true          (default: false)
#
# Notes:
# - Requires internet access for helm repos + gateway api manifest.
# - Writes these files in the current directory:
#     linkerd-loki-values.yaml
#     linkerd-alloy-values.yaml
#     linkerd-o11y-stack.yaml
###################################################################################################

set -euo pipefail

# ----------------------------
# Config (env overridable)
# ----------------------------
CLUSTER_NAME="${CLUSTER_NAME:-sma}"
SERVERS="${SERVERS:-3}"
WAIT="${WAIT:-true}"
CONTEXT="${CONTEXT:-}"

LINKERD_NS="${LINKERD_NS:-linkerd}"
CERT_MANAGER_NS="${CERT_MANAGER_NS:-cert-manager}"
MONITORING_NS="${MONITORING_NS:-monitoring}"
ENABLE_MONITORING_NS_INJECT="${ENABLE_MONITORING_NS_INJECT:-true}"

GATEWAY_API_VERSION="${GATEWAY_API_VERSION:-v1.4.0}"
HA_VALUES_PATH="${HA_VALUES_PATH:-linkerd-enterprise-control-plane/values-ha.yaml}"

SKIP_REPO_ADD="${SKIP_REPO_ADD:-false}"

# ----------------------------
# Helpers
# ----------------------------
log() { echo "[INFO] $*"; }
err() { echo "[ERROR] $*" >&2; }

require() {
  command -v "$1" >/dev/null 2>&1 || {
    err "$1 could not be found. $2"
    exit 1
  }
}

k() {
  if [[ -n "${CONTEXT}" ]]; then
    kubectl --context "${CONTEXT}" "$@"
  else
    kubectl "$@"
  fi
}

h() {
  if [[ -n "${CONTEXT}" ]]; then
    helm --kube-context "${CONTEXT}" "$@"
  else
    helm "$@"
  fi
}

wait_for_deploy() {
  local ns="$1" name="$2"
  log "Waiting for deployment/${name} in ns/${ns}..."
  k -n "${ns}" rollout status "deploy/${name}" --timeout=10m
}

ensure_ns() {
  local ns="$1"
  if k get ns "${ns}" >/dev/null 2>&1; then
    log "Namespace ${ns} already exists."
  else
    log "Creating namespace ${ns}..."
    k create ns "${ns}"
  fi
}

# ----------------------------
# Steps
# ----------------------------
check_deps() {
  require k3d "You can get it from https://k3d.io"
  require step "You can get it from https://smallstep.com/docs/step-cli/installation"
  require kubectl "You can get it from https://kubernetes.io/docs/tasks/tools/#kubectl"
  require linkerd "You can install it with: curl -fsL https://enterprise.buoyant.io/install | sh"
  require helm "You can get it from https://helm.sh/docs/intro/install/"

  if [[ -z "${BUOYANT_LICENSE:-}" ]]; then
    err "BUOYANT_LICENSE is not set. Example: export BUOYANT_LICENSE='...'"
    exit 1
  fi

  log "Hooray! All dependencies have been met!"
}

add_helm_repos() {
  if [[ "${SKIP_REPO_ADD}" == "true" ]]; then
    log "Skipping helm repo add/update (SKIP_REPO_ADD=true)."
    return
  fi

  log "Adding/updating Helm repos..."
  h repo add linkerd-buoyant https://helm.buoyant.cloud >/dev/null 2>&1 || true
  h repo add jetstack https://charts.jetstack.io --force-update >/dev/null 2>&1 || true
  h repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1 || true
  h repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
  h repo update >/dev/null
}

create_k3d_cluster() {
  # If CONTEXT is set, we assume user wants to target an existing cluster/context.
  if [[ -n "${CONTEXT}" ]]; then
    log "CONTEXT is set (${CONTEXT}); skipping k3d cluster creation."
    return
  fi

  log "Creating k3d cluster: ${CLUSTER_NAME} (servers=${SERVERS})"
  if [[ "${WAIT}" == "true" ]]; then
    k3d cluster create "${CLUSTER_NAME}" --servers "${SERVERS}" --wait
  else
    k3d cluster create "${CLUSTER_NAME}" --servers "${SERVERS}"
  fi
}

install_gateway_api() {
  log "Installing Gateway API ${GATEWAY_API_VERSION}..."
  k apply --server-side -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"
}

fetch_enterprise_chart() {
  log "Fetching linkerd-enterprise-control-plane chart locally..."
  rm -rf linkerd-enterprise-control-plane >/dev/null 2>&1 || true
  h fetch --untar linkerd-buoyant/linkerd-enterprise-control-plane

  if [[ ! -f "${HA_VALUES_PATH}" ]]; then
    err "HA values file not found at: ${HA_VALUES_PATH}"
    err "Did the chart layout change? Check the directory: linkerd-enterprise-control-plane/"
    exit 1
  fi
}

install_cert_manager_and_trust_manager() {
  ensure_ns "${LINKERD_NS}"
  log "Labeling ${LINKERD_NS} as Linkerd control plane namespace..."
  k label namespace "${LINKERD_NS}" linkerd.io/is-control-plane=true --overwrite

  log "Installing cert-manager..."
  h upgrade -i cert-manager jetstack/cert-manager \
    --namespace "${CERT_MANAGER_NS}" \
    --create-namespace \
    --set crds.enabled=true

  log "Waiting for cert-manager deployments..."
  k rollout status -n "${CERT_MANAGER_NS}" deploy --timeout=10m

  log "Installing trust-manager..."
  h upgrade -i trust-manager jetstack/trust-manager \
    --namespace "${CERT_MANAGER_NS}" \
    --set app.trust.namespace="${CERT_MANAGER_NS}" \
    --wait
}

configure_linkerd_external_ca() {
  log "Creating self-signed Issuer for trust root..."
  k apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: linkerd-trust-root-issuer
  namespace: ${CERT_MANAGER_NS}
spec:
  selfSigned: {}
EOF

  log "Creating trust anchor Certificate (Secret: linkerd-trust-anchor)..."
  k apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: linkerd-trust-anchor
  namespace: ${CERT_MANAGER_NS}
spec:
  issuerRef:
    kind: Issuer
    name: linkerd-trust-root-issuer
  secretName: linkerd-trust-anchor
  isCA: true
  commonName: root.linkerd.cluster.local
  duration: 8760h0m0s
  renewBefore: 7320h0m0s
  privateKey:
    rotationPolicy: Always
    algorithm: ECDSA
EOF

  log "Creating ClusterIssuer backed by the trust anchor..."
  k apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: linkerd-identity-issuer
spec:
  ca:
    secretName: linkerd-trust-anchor
EOF

  log "Creating identity issuer Certificate in ${LINKERD_NS} (Secret: linkerd-identity-issuer)..."
  k apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: linkerd-identity-issuer
  namespace: ${LINKERD_NS}
spec:
  issuerRef:
    name: linkerd-identity-issuer
    kind: ClusterIssuer
  secretName: linkerd-identity-issuer
  isCA: true
  commonName: identity.linkerd.cluster.local
  duration: 48h0m0s
  renewBefore: 25h0m0s
  privateKey:
    rotationPolicy: Always
    algorithm: ECDSA
EOF

  log "Creating linkerd-previous-anchor secret from linkerd-trust-anchor (stripping ownership metadata)..."
  k get secret -n "${CERT_MANAGER_NS}" linkerd-trust-anchor -o yaml \
    | sed 's/name: linkerd-trust-anchor/name: linkerd-previous-anchor/' \
    | sed '/^\s*resourceVersion:/d' \
    | sed '/^\s*uid:/d' \
    | sed '/^\s*creationTimestamp:/d' \
    | sed '/^\s*managedFields:/,/^[^ ]/d' \
    | sed '/^\s*ownerReferences:/,/^\s*[^ ]/d' \
    | k apply -n "${CERT_MANAGER_NS}" -f -

  log "Creating trust-manager Bundle for linkerd-identity-trust-roots..."
  k apply -f - <<EOF
apiVersion: trust.cert-manager.io/v1alpha1
kind: Bundle
metadata:
  name: linkerd-identity-trust-roots
spec:
  sources:
    - secret:
        name: "linkerd-trust-anchor"
        key: "tls.crt"
    - secret:
        name: "linkerd-previous-anchor"
        key: "tls.crt"
  target:
    configMap:
      key: "ca-bundle.crt"
    namespaceSelector:
      matchLabels:
        linkerd.io/is-control-plane: "true"
EOF
}

install_linkerd_enterprise() {
  log "Installing Linkerd Enterprise CRDs..."
  h upgrade -i linkerd-crds \
    --namespace "${LINKERD_NS}" \
    --create-namespace \
    linkerd-buoyant/linkerd-enterprise-crds

  log "Installing Linkerd Enterprise control plane (externalCA=true + HA values)..."
  h upgrade -i linkerd-control-plane \
    --namespace "${LINKERD_NS}" \
    --set "license=${BUOYANT_LICENSE}" \
    --set identity.externalCA=true \
    --set proxy.tracing.enabled=true \
    --set proxy.tracing.collector.endpoint=tempo.monitoring:4317 \
    --set proxy.tracing.collector.meshIdentity.serviceAccountName=tempo \
    --set proxy.tracing.collector.meshIdentity.namespace=monitoring \
    --set identity.issuer.scheme=kubernetes.io/tls \
    --values "${HA_VALUES_PATH}" \
    linkerd-buoyant/linkerd-enterprise-control-plane

  log "Waiting for Linkerd control plane deployments..."
  k rollout status -n "${LINKERD_NS}" deploy --timeout=10m
}

write_o11y_values_files() {
  log "Writing linkerd-loki-values.yaml..."
  cat <<'EOF' > linkerd-loki-values.yaml
# linkerd-loki-values-min.yaml
deploymentMode: SingleBinary

loki:
  auth_enabled: false

  commonConfig:
    replication_factor: 1

  # Use local filesystem storage instead of object storage (MinIO/S3/etc)
  storage:
    type: filesystem

  storageConfig:
    filesystem:
      directory: /var/loki

  # TSDB schema, but backed by filesystem (ephemeral via emptyDir below)
  schemaConfig:
    configs:
      - from: "2024-04-01"
        store: tsdb
        object_store: filesystem
        schema: v13
        index:
          prefix: loki_index_
          period: 24h

  # Keep it simple for local use
  limits_config:
    allow_structured_metadata: true
    volume_enabled: true

singleBinary:
  replicas: 1

  # Ephemeral storage (no PVC). This is the "local dev" mode.
  persistence:
    enabled: false

  extraVolumes:
    - name: loki-data
      emptyDir: {}

  extraVolumeMounts:
    - name: loki-data
      mountPath: /var/loki

# Turn off anything that spawns extra pods
minio:
  enabled: false
gateway:
  enabled: true
chunksCache:
  enabled: false
resultsCache:
  enabled: false
lokiCanary:
  enabled: false
test:
  enabled: false
monitoring:
  selfMonitoring:
    enabled: false

# Zero out other modes/components explicitly
backend:
  replicas: 0
read:
  replicas: 0
write:
  replicas: 0

ingester:
  replicas: 0
querier:
  replicas: 0
queryFrontend:
  replicas: 0
queryScheduler:
  replicas: 0
distributor:
  replicas: 0
compactor:
  replicas: 0
indexGateway:
  replicas: 0
bloomCompactor:
  replicas: 0
bloomGateway:
  replicas: 0

EOF

  log "Writing linkerd-alloy-values.yaml..."
  cat <<'EOF' > linkerd-alloy-values.yaml
alloy:
  extraPorts:
  - name: otelgrpc
    port: 4317
    protocol: TCP
    targetPort: 4317
  - name: otelhttp
    port: 4318
    protocol: TCP
    targetPort: 4318
  - name: zipkin
    port: 9411
    protocol: TCP
    targetPort: 9411
  configMap:
    content: |-
      logging {
        level  = "info"
        format = "logfmt"
      }

      discovery.kubernetes "linkerd_controller" {
        role = "pod"
        namespaces {
                names = ["linkerd", "prometheus"]
        }
      }
      discovery.kubernetes "linkerd_service_mirror" {
        role = "pod"
      }
      discovery.kubernetes "linkerd_proxy" {
        role = "pod"
      }

      discovery.relabel "linkerd_controller" {
        targets = discovery.kubernetes.linkerd_controller.targets
        rule {
                source_labels = ["__meta_kubernetes_pod_container_port_name"]
                regex         = "admin-http"
                action        = "keep"
        }
        rule {
                source_labels = ["__meta_kubernetes_pod_container_name"]
                target_label  = "component"
        }
      }

      discovery.relabel "linkerd_service_mirror" {
        targets = discovery.kubernetes.linkerd_service_mirror.targets
        rule {
                source_labels = ["__meta_kubernetes_pod_label_component", "__meta_kubernetes_pod_container_port_name"]
                regex         = "linkerd-service-mirror;admin-http$"
                action        = "keep"
        }
        rule {
                source_labels = ["__meta_kubernetes_pod_container_name"]
                target_label  = "component"
        }
      }

      discovery.relabel "linkerd_proxy" {
        targets = discovery.kubernetes.linkerd_proxy.targets
        rule {
                source_labels = ["__meta_kubernetes_pod_container_name", "__meta_kubernetes_pod_container_port_name", "__meta_kubernetes_pod_label_linkerd_io_control_plane_ns"]
                regex         = "^linkerd-proxy;linkerd-admin;linkerd$"
                action        = "keep"
        }
        rule {
                source_labels = ["__meta_kubernetes_namespace"]
                target_label  = "namespace"
        }
        rule {
                source_labels = ["__meta_kubernetes_pod_name"]
                target_label  = "pod"
        }
        rule {
                source_labels = ["__meta_kubernetes_pod_label_linkerd_io_proxy_job"]
                target_label  = "k8s_job"
        }
        rule {
                regex  = "__meta_kubernetes_pod_label_linkerd_io_proxy_job"
                action = "labeldrop"
        }
        rule {
                regex  = "__meta_kubernetes_pod_label_linkerd_io_proxy_(.+)"
                action = "labelmap"
        }
        rule {
                regex  = "__meta_kubernetes_pod_label_linkerd_io_proxy_(.+)"
                action = "labeldrop"
        }
        rule {
                regex  = "__meta_kubernetes_pod_label_linkerd_io_(.+)"
                action = "labelmap"
        }
        rule {
                regex       = "__meta_kubernetes_pod_label_(.+)"
                replacement = "__tmp_pod_label_"
                action      = "labelmap"
        }
        rule {
                regex       = "__tmp_pod_label_linkerd_io_(.+)"
                replacement = "__tmp_pod_label_"
                action      = "labelmap"
        }
        rule {
                regex  = "__tmp_pod_label_linkerd_io_(.+)"
                action = "labeldrop"
        }
        rule {
                regex  = "__tmp_pod_label_(.+)"
                action = "labelmap"
        }
      }

      prometheus.scrape "linkerd_controller" {
        targets          = discovery.relabel.linkerd_controller.output
        forward_to       = [prometheus.remote_write.default.receiver]
        scrape_interval  = "10s"
        job_name         = "linkerd-controller"
      }

      prometheus.scrape "linkerd_service_mirror" {
        targets          = discovery.relabel.linkerd_service_mirror.output
        forward_to       = [prometheus.remote_write.default.receiver]
        scrape_interval  = "10s"
        job_name         = "linkerd-service-mirror"
      }

      prometheus.scrape "linkerd_proxy" {
        targets          = discovery.relabel.linkerd_proxy.output
        forward_to       = [prometheus.remote_write.default.receiver]
        scrape_interval  = "10s"
        job_name         = "linkerd-proxy"
      }

      discovery.kubernetes "pods" { role = "pod" }

      discovery.relabel "linkerd_namespaces" {
        targets = discovery.kubernetes.pods.targets
        rule {
          source_labels = ["__meta_kubernetes_namespace"]
          regex         = ".*linkerd.*"
          action        = "keep"
        }
        rule {
          source_labels = ["__meta_kubernetes_pod_container_name"]
          target_label  = "container"
          action        = "replace"
        }
        rule {
          source_labels = ["__meta_kubernetes_pod_name"]
          target_label  = "pod"
          action        = "replace"
        }
        rule {
          source_labels = ["__meta_kubernetes_namespace"]
          target_label  = "namespace"
          action        = "replace"
        }
        rule {
          source_labels = [
            "__meta_kubernetes_pod_label_linkerd_io_workload_ns",
            "__meta_kubernetes_pod_label_linkerd_io_proxy_deployment",
          ]
          separator    = "/"
          target_label = "linkerd_control_plane"
          action       = "replace"
        }
      }

      discovery.relabel "linkerd_sidecars" {
        targets = discovery.kubernetes.pods.targets

        rule {
          source_labels = ["__meta_kubernetes_pod_annotation_linkerd_io_inject"]
          regex         = "enabled"
          action        = "keep"
        }
        rule {
          source_labels = ["__meta_kubernetes_pod_container_name"]
          regex         = "linkerd-(proxy|init)"
          action        = "keep"
        }
        rule {
          source_labels = ["__meta_kubernetes_pod_container_name"]
          target_label  = "container"
          action        = "replace"
        }
        rule {
          source_labels = ["__meta_kubernetes_pod_name"]
          target_label  = "pod"
          action        = "replace"
        }
        rule {
          source_labels = ["__meta_kubernetes_namespace"]
          target_label  = "namespace"
          action        = "replace"
        }
        rule {
          source_labels = [
            "__meta_kubernetes_pod_label_linkerd_io_workload_ns",
            "__meta_kubernetes_pod_label_linkerd_io_proxy_deployment",
          ]
          separator    = "/"
          target_label = "meshed_workloads"
          action       = "replace"
        }
      }

      loki.source.kubernetes "linkerd_namespace_logs" {
        targets    = discovery.relabel.linkerd_namespaces.output
        forward_to = [loki.process.linkerd.receiver]
      }

      loki.source.kubernetes "linkerd_sidecar_logs" {
        targets    = discovery.relabel.linkerd_sidecars.output
        forward_to = [loki.process.linkerd.receiver]
      }

      loki.process "linkerd" {
        forward_to = [loki.write.loki.receiver]

        stage.drop {
          older_than          = "1h"
          drop_counter_reason = "too old"
        }

        stage.match {
          selector = "{container=~\".*\"}"

          stage.json {
            expressions = {
              level = "level",
            }
          }

          stage.labels {
            values = {
              level = "level",
            }
          }
        }
      }

      discovery.relabel "application_containers" {
        targets = discovery.kubernetes.pods.targets

        rule {
          source_labels = ["__meta_kubernetes_namespace"]
          regex         = "emojivoto|otel-demo|monitoring"
          action        = "keep"
        }

        rule {
          source_labels = ["__meta_kubernetes_namespace"]
          regex         = ".*linkerd.*"
          action        = "drop"
        }

        rule {
          source_labels = ["__meta_kubernetes_pod_container_name"]
          regex         = "linkerd-(proxy|init)"
          action        = "drop"
        }

        rule {
          source_labels = ["__meta_kubernetes_pod_container_name"]
          target_label  = "container"
          action        = "replace"
        }

        rule {
          source_labels = ["__meta_kubernetes_pod_name"]
          target_label  = "pod"
          action        = "replace"
        }

        rule {
          source_labels = ["__meta_kubernetes_namespace"]
          target_label  = "namespace"
          action        = "replace"
        }

        rule {
          source_labels = [
            "__meta_kubernetes_namespace",
            "__meta_kubernetes_pod_controller_name",
          ]
          separator    = "/"
          target_label = "workloads"
          action       = "replace"
        }
      }

      loki.source.kubernetes "application_logs" {
        targets    = discovery.relabel.application_containers.output
        forward_to = [loki.process.linkerd.receiver]
      }

      otelcol.receiver.otlp "default" {
        grpc { }
        http { }
        output {
          metrics = [otelcol.processor.resourcedetection.default.input]
          logs    = [otelcol.processor.resourcedetection.default.input]
          traces  = [otelcol.processor.resourcedetection.default.input]
        }
      }

      otelcol.processor.resourcedetection "default" {
        detectors = ["env", "system"]
        system { hostname_sources = ["os"] }
        output {
          metrics = [otelcol.processor.transform.drop_unneeded_resource_attributes.input]
          logs    = [otelcol.processor.transform.drop_unneeded_resource_attributes.input]
          traces  = [otelcol.processor.transform.drop_unneeded_resource_attributes.input]
        }
      }

      otelcol.processor.transform "drop_unneeded_resource_attributes" {
        error_mode = "ignore"
        trace_statements {
          context    = "resource"
          statements = [
            "delete_key(attributes, \"k8s.pod.start_time\")",
            "delete_key(attributes, \"os.description\")",
            "delete_key(attributes, \"os.type\")",
            "delete_key(attributes, \"process.command_args\")",
            "delete_key(attributes, \"process.executable.path\")",
            "delete_key(attributes, \"process.pid\")",
            "delete_key(attributes, \"process.runtime.description\")",
            "delete_key(attributes, \"process.runtime.name\")",
            "delete_key(attributes, \"process.runtime.version\")",
          ]
        }
        output {
          metrics = [otelcol.processor.transform.reduce_otel_demo_cardinality.input]
          logs    = [otelcol.processor.transform.reduce_otel_demo_cardinality.input]
          traces  = [otelcol.processor.transform.reduce_otel_demo_cardinality.input]
        }
      }

      otelcol.processor.transform "reduce_otel_demo_cardinality" {
        error_mode = "ignore"
        trace_statements {
          context    = "span"
          statements = [
            "replace_match(name, \"GET /api/cart*\", \"GET /api/cart\")",
            "replace_match(name, \"GET /api/recommendations*\", \"GET /api/recommendations\")",
            "replace_match(name, \"GET /api/products*\", \"GET /api/products\")",
          ]
        }
        output {
          logs    = [otelcol.processor.batch.default.input]
          traces  = [otelcol.processor.batch.default.input]
        }
      }

      otelcol.processor.batch "default" {
        output {
          metrics = []
          logs    = []
          traces  = [otelcol.exporter.otlphttp.tempo.input]
        }
      }

      otelcol.exporter.otlphttp "tempo" {
        client { endpoint = "http://tempo.monitoring:4318" }
      }

      prometheus.remote_write "default" {
        endpoint { url = "http://kube-prometheus-stack-prometheus.monitoring:9090/api/v1/write" }
      }

      loki.write "loki" {
        endpoint { url = "http://loki-gateway/loki/api/v1/push" }
      }
EOF

  log "Writing linkerd-o11y-stack.yaml..."
  cat <<'EOF' > linkerd-o11y-stack.yaml
grafana:
  enabled: true
  grafana.ini:
    auth:
      disable_login_form: true
    auth.anonymous:
      enabled: true
      org_role: Admin
    auth.basic:
      enabled: false
    analytics:
      check_for_updates: false
    panels:
      disable_sanitize_html: true
    log:
      mode: console
    log.console:
      format: text
      level: info
  datasources:
   datasources.yaml:
     apiVersion: 1
     datasources:
      - name: Loki
        type: loki
        url: http://loki-gateway.monitoring
        jsonData:
          httpHeaderName1: 'X-Scope-OrgID'
        secureJsonData:
          httpHeaderValue1: '1'
      - name: Tempo
        uid: tempo
        type: tempo
        access: proxy
        url: http://tempo.monitoring:3200
        jsonData:
          tracesToLogs:
            datasourceUid: loki
          tracesToMetrics:
            datasourceUid: prometheus
  dashboardProviders:
    dashboardproviders.yaml:
      apiVersion: 1
      providers:
      - disableDeletion: false
        editable: true
        folder: Linkerd
        name: linkerd
        options:
          path: /var/lib/grafana/dashboards/default
        orgId: 1
        type: file
  dashboards:
    linkerd:
      authority: { datasource: prometheus, gnetId: 15482, revision: 3 }
      cronjob: { datasource: prometheus, gnetId: 15483, revision: 3 }
      daemonset: { datasource: prometheus, gnetId: 15484, revision: 3 }
      deployment: { datasource: prometheus, gnetId: 15475, revision: 7 }
      health: { datasource: prometheus, gnetId: 15486, revision: 3 }
      job: { datasource: prometheus, gnetId: 15487, revision: 3 }
      kubernetes: { datasource: prometheus, gnetId: 15479, revision: 2 }
      multicluster: { datasource: prometheus, gnetId: 15488, revision: 3 }
      namespace: { datasource: prometheus, gnetId: 15478, revision: 3 }
      pod: { datasource: prometheus, gnetId: 15477, revision: 3 }
      prometheus: { datasource: prometheus, gnetId: 15489, revision: 2 }
      prometheus-benchmark: { datasource: prometheus, gnetId: 15490, revision: 2 }
      replicaset: { datasource: prometheus, gnetId: 15491, revision: 3 }
      replicationcontroller: { datasource: prometheus, gnetId: 15492, revision: 4 }
      route: { datasource: prometheus, gnetId: 15481, revision: 3 }
      service: { datasource: prometheus, gnetId: 15480, revision: 3 }
      statefulset: { datasource: prometheus, gnetId: 15493, revision: 3 }
      top-line: { datasource: prometheus, gnetId: 15474, revision: 4 }
      hazl: { datasource: prometheus, gnetId: 23979, revision: 2 }
  persistence:
    accessModes: [ReadWriteOnce]
    enabled: false
    size: 20Gi
    type: pvc
prometheusOperator:
  admissionWebhooks:
    patch:
      podAnnotations:
         config.alpha.linkerd.io/proxy-enable-native-sidecar: "true"
prometheus:
  prometheusSpec:
    scrapeInterval: 10s
    enableRemoteWriteReceiver: true
    enableFeatures:
    - remote-write-receiver
EOF
}

install_faces_with_routes() {
  #################################################################################################
  # Installs Faces (Helm) into the "faces" namespace (meshed by default) and applies GRPCRoute +
  # HTTPRoute resources for color/smiley routing.
  #
  # Optional env vars to override:
  #   FACES_NS=faces
  #   FACES_CHART_VERSION=2.1.0-rc.1
  #   FACES_COLOR1=blue
  #   FACES_COLOR2=green
  #   FACES_SMILEY1=U+1F601
  #   FACES_SMILEY2=U+1F920
  #################################################################################################

  set -euo pipefail

  local ns="${FACES_NS:-faces}"
  local chart_version="${FACES_CHART_VERSION:-2.1.0-rc.1}"

  local color1="${FACES_COLOR1:-blue}"
  local color2="${FACES_COLOR2:-green}"
  local smiley1="${FACES_SMILEY1:-U+1F601}"
  local smiley2="${FACES_SMILEY2:-U+1F920}"

  echo "[INFO] Installing Faces into namespace: ${ns}"

  # Namespace + injection
  kubectl get namespace "${ns}" >/dev/null 2>&1 || kubectl create namespace "${ns}"
  kubectl annotate namespace "${ns}" linkerd.io/inject=enabled --overwrite

  # Install/upgrade Faces chart
  helm upgrade --install faces -n "${ns}" \
    oci://ghcr.io/buoyantio/faces-chart --version "${chart_version}" \
    --set "color.color=${color1}" \
    --set "smiley.smiley=${smiley1}" \
    --set "backend.errorFraction=0" \
    --set "backend.delayBuckets=" \
    --set "face.errorFraction=0" \
    --set "smiley2.enabled=true" \
    --set "smiley2.smiley=${smiley2}" \
    --set "color2.enabled=true" \
    --set "color2.color=${color2}"

  # Apply GRPCRoute for ColorService routing (center -> color, edge -> color2)
  cat <<EOF | kubectl -n "${ns}" apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: GRPCRoute
metadata:
  name: color-route
  namespace: ${ns}
spec:
  parentRefs:
    - group: ""
      kind: Service
      name: color
      namespace: ${ns}
      port: 80
  rules:
    - matches:
        - method:
            service: ColorService
            method: Center
      backendRefs:
        - group: ""
          kind: Service
          name: color
          namespace: ${ns}
          port: 80
    - matches:
        - method:
            service: ColorService
            method: Edge
      backendRefs:
        - group: ""
          kind: Service
          name: color2
          namespace: ${ns}
          port: 80
EOF

  # Apply HTTPRoute for smiley routing (/edge -> smiley2, /center -> smiley)
  cat <<EOF | kubectl -n "${ns}" apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: smiley-route
  namespace: ${ns}
spec:
  parentRefs:
    - kind: Service
      group: ""
      name: smiley
      namespace: ${ns}
      port: 80
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /edge
      backendRefs:
        - kind: Service
          group: ""
          name: smiley2
          namespace: ${ns}
          port: 80
    - matches:
        - path:
            type: PathPrefix
            value: /center
      backendRefs:
        - kind: Service
          group: ""
          name: smiley
          namespace: ${ns}
          port: 80
EOF

  echo "[INFO] Faces + routes applied."
}

install_o11y_stack() {
  ensure_ns "${MONITORING_NS}"

  if [[ "${ENABLE_MONITORING_NS_INJECT}" == "true" ]]; then
    log "Annotating namespace ${MONITORING_NS} with linkerd.io/inject=enabled (overwrite)..."
    k annotate namespace "${MONITORING_NS}" linkerd.io/inject=enabled --overwrite
  else
    log "Skipping monitoring namespace injection annotation (ENABLE_MONITORING_NS_INJECT=false)."
  fi

  write_o11y_values_files

  log "Installing Loki..."
  h upgrade -i -n "${MONITORING_NS}" loki grafana/loki -f linkerd-loki-values.yaml

  log "Installing Tempo (metricsGenerator enabled)..."
  h upgrade -i -n "${MONITORING_NS}" tempo grafana/tempo --set tempo.metricsGenerator.enabled=true

  log "Installing kube-prometheus-stack (Prometheus + Grafana)..."
  h upgrade -i -n "${MONITORING_NS}" kube-prometheus-stack prometheus-community/kube-prometheus-stack -f linkerd-o11y-stack.yaml

  log "Installing Alloy..."
  h upgrade -i -n "${MONITORING_NS}" alloy grafana/alloy -f linkerd-alloy-values.yaml

  log "Best-effort rollout checks..."
  if k -n "${MONITORING_NS}" get deploy kube-prometheus-stack-grafana >/dev/null 2>&1; then
    wait_for_deploy "${MONITORING_NS}" kube-prometheus-stack-grafana
  fi
  if k -n "${MONITORING_NS}" get deploy alloy >/dev/null 2>&1; then
    wait_for_deploy "${MONITORING_NS}" alloy
  fi
}

post_checks() {
  log "Done."
  log "Suggested checks:"
  log "  linkerd check"
  log "  k get pods -n ${LINKERD_NS}"
  log "  k get pods -n ${MONITORING_NS}"
  log ""
  log "Grafana (anonymous enabled in values):"
  log "  kubectl -n ${MONITORING_NS} port-forward svc/kube-prometheus-stack-grafana 3000:80"
  log ""
  log "Prometheus:"
  log "  kubectl -n ${MONITORING_NS} port-forward svc/kube-prometheus-stack-prometheus 9090:9090"
}

main() {
  check_deps
  create_k3d_cluster
  add_helm_repos

  install_gateway_api
  fetch_enterprise_chart
  install_cert_manager_and_trust_manager
  configure_linkerd_external_ca
  install_linkerd_enterprise

  install_o11y_stack
  post_checks
  install_faces_with_routes
}

main "$@"
