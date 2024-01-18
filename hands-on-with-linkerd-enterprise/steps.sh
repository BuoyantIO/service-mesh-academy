#!/bin/bash
k3d cluster delete sma &>/dev/null
k3d cluster create -c cluster/hazl.yaml --wait
kubectl ns default
clear

# shellcheck source=demo-magic.sh
source demo-magic.sh

# watch kubectl get pods -A -o wide --sort-by .metadata.namespace

# shellcheck source=settings.sh
pe "source settings.sh"
wait
clear

pe "curl -sL https://enterprise.buoyant.io/install-preview | sh"
wait
clear

pe "linkerd check --pre"
wait
clear

pe "helm repo add linkerd-buoyant https://helm.buoyant.cloud"
wait
clear

pe "helm repo update"
wait
clear

pe "export CLUSTER_NAME=jmo-sma"
wait
clear

pe "helm install linkerd-buoyant \\
  --create-namespace \\
  --namespace linkerd-buoyant \\
  --set metadata.agentName=\"\${CLUSTER_NAME}\" \\
  --set metrics.debugMetrics=true \\
  --set api.clientID=\"\${API_CLIENT_ID}\" \\
  --set api.clientSecret=\"\${API_CLIENT_SECRET}\" \\
linkerd-buoyant/linkerd-buoyant"
wait
clear

pe "kubectl rollout status daemonset/buoyant-cloud-metrics -n linkerd-buoyant"
wait
clear

pe "linkerd buoyant check"
wait
clear

pe "cat linkerd-identity-secret.yaml | bat -l yaml"
# pe "cat <<EOF > linkerd-identity-secret.yaml
# apiVersion: v1
# data:
#   ca.crt: \$(base64 < certs/ca.crt | tr -d '\n')
#   tls.crt: \$(base64 < certs/issuer.crt| tr -d '\n')
#   tls.key: \$(base64 < certs/issuer.key | tr -d '\n')
# kind: Secret
# metadata:
#   name: linkerd-identity-issuer
#   namespace: linkerd
# type: kubernetes.io/tls
# EOF"
wait
clear

pe "kubectl apply -f linkerd-identity-secret.yaml"
wait
clear

pe "cat linkerd-control-plane-config.yaml | bat -l yaml"
# pe "cat <<EOF > linkerd-control-plane-config.yaml
# apiVersion: linkerd.buoyant.io/v1alpha1
# kind: ControlPlane
# metadata:
#   name: linkerd-control-plane
# spec:
#   components:
#     linkerd:
#       version: preview-24.1.3
#       license: \$BUOYANT_LICENSE
#       controlPlaneConfig:
#         proxy:
#           image:
#             version: preview-24.1.3-hazl
#         identityTrustAnchorsPEM: |
# \$(sed 's/^/          /' < certs/ca.crt )
#         identity:
#           issuer:
#             scheme: kubernetes.io/tls
#         destinationController:
#           experimentalArgs:
#           # - -experimental-endpoint-zone-weights
#         nodeAffinity:
#           requiredDuringSchedulingIgnoredDuringExecution:
#             nodeSelectorTerms:
#             - matchExpressions:
#               - key: topology.kubernetes.io/zone
#                 operator: DoesNotExist
# EOF"
wait
clear

pe "kubectl apply -f linkerd-control-plane-config.yaml"
wait
clear

pe "linkerd check"
wait
clear

# Create demo apps

pe "curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/emojivoto.yml | linkerd inject - | k apply -f -"
wait
clear

# Create dataplane objects

pe "kubectl apply -f - <<EOF
---
apiVersion: linkerd.buoyant.io/v1alpha1
kind: DataPlane
metadata:
  name: linkerd-buoyant
  namespace: linkerd-buoyant
spec:
  workloadSelector:
    matchLabels: {}
EOF"
wait
clear

# check proxies

pe "kubectl rollout status daemonset/buoyant-cloud-metrics -n linkerd-buoyant"
wait
clear

pe "linkerd check --proxy -n linkerd-buoyant"
wait
clear

# Create policy for Emojivoto

pe "linkerd policy generate | kubectl apply -f -"
wait
clear

# Look at Hazl from linkerd-viz

pe "kubectl apply -k colorz/"
wait
clear

pe "vim linkerd-control-plane-config.yaml"
wait
clear


pe "kubectl apply -f linkerd-control-plane-config.yaml"
wait
clear

pe "linkerd check"
wait
clear

# watch k get pods -n colorz -o wide --sort-by .spec.nodeName
