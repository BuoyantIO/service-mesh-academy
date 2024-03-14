#!/bin/bash
# cluster_setup.sh
# Demo script for the eliminate-cross-zone-traffic-hazl GitHub repository
# https://github.com/BuoyantIO/service-mesh-academy/tree/main/eliminate-cross-zone-traffic-hazl
# Automates cluster creation, Linkerd installation and installs the Orders application
# Tom Dean | Buoyant
# Last edit: 3/14/2024

k3d cluster delete demo-cluster-orders-hazl
k3d cluster delete demo-cluster-orders-topo
k3d cluster create -c cluster/demo-cluster-orders-hazl.yaml --wait
k3d cluster create -c cluster/demo-cluster-orders-topo.yaml --wait
k3d cluster list

kubectx hazl=k3d-demo-cluster-orders-hazl
kubectx topo=k3d-demo-cluster-orders-topo
kubectx hazl
kubectx

cd certs
rm -f *.{crt,key}
step certificate create root.linkerd.cluster.local ca.crt ca.key \
--profile root-ca --no-password --insecure
step certificate create identity.linkerd.cluster.local issuer.crt issuer.key \
--profile intermediate-ca --not-after 8760h --no-password --insecure \
--ca ca.crt --ca-key ca.key
ls -la
cd ..

source settings.sh

curl https://enterprise.buoyant.io/install | sh
export PATH=~/.linkerd2/bin:$PATH
linkerd version

linkerd check --pre --context=hazl
linkerd check --pre --context=topo

helm repo add linkerd-buoyant https://helm.buoyant.cloud
helm repo update

helm install linkerd-buoyant \
  --create-namespace \
  --namespace linkerd-buoyant \
  --kube-context hazl \
  --set metadata.agentName=$CLUSTER1_NAME \
  --set api.clientID=$API_CLIENT_ID \
  --set api.clientSecret=$API_CLIENT_SECRET \
  --set metrics.debugMetrics=true \
  --set agent.logLevel=debug \
  --set metrics.logLevel=debug \
linkerd-buoyant/linkerd-buoyant

helm install linkerd-buoyant \
  --create-namespace \
  --namespace linkerd-buoyant \
  --kube-context topo \
  --set metadata.agentName=$CLUSTER2_NAME \
  --set api.clientID=$API_CLIENT_ID \
  --set api.clientSecret=$API_CLIENT_SECRET \
  --set metrics.debugMetrics=true \
  --set agent.logLevel=debug \
  --set metrics.logLevel=debug \
linkerd-buoyant/linkerd-buoyant

kubectl rollout status daemonset/buoyant-cloud-metrics -n linkerd-buoyant --context=hazl
linkerd buoyant check --context hazl

kubectl rollout status daemonset/buoyant-cloud-metrics -n linkerd-buoyant --context=topo
linkerd buoyant check --context topo

cat <<EOF > linkerd-identity-secret.yaml
apiVersion: v1
data:
  ca.crt: $(base64 < certs/ca.crt | tr -d '\n')
  tls.crt: $(base64 < certs/issuer.crt| tr -d '\n')
  tls.key: $(base64 < certs/issuer.key | tr -d '\n')
kind: Secret
metadata:
  name: linkerd-identity-issuer
  namespace: linkerd
type: kubernetes.io/tls
EOF

kubectl apply -f linkerd-identity-secret.yaml --context=hazl
kubectl apply -f linkerd-identity-secret.yaml --context=topo

kubectl get secrets  -n linkerd --context=hazl
kubectl get secrets  -n linkerd --context=topo

cat <<EOF > linkerd-control-plane-config-hazl.yaml
apiVersion: linkerd.buoyant.io/v1alpha1
kind: ControlPlane
metadata:
  name: linkerd-control-plane
spec:
  components:
    linkerd:
      version: enterprise-2.15.1-1
      license: $BUOYANT_LICENSE
      controlPlaneConfig:
        proxy:
          image:
            version: enterprise-2.15.1-1-hazl
        identityTrustAnchorsPEM: |
$(sed 's/^/          /' < certs/ca.crt )
        identity:
          issuer:
            scheme: kubernetes.io/tls
        destinationController:
          additionalArgs:
           # - -ext-endpoint-zone-weights
EOF

cat <<EOF > linkerd-control-plane-config-topo.yaml
apiVersion: linkerd.buoyant.io/v1alpha1
kind: ControlPlane
metadata:
  name: linkerd-control-plane
spec:
  components:
    linkerd:
      version: enterprise-2.15.1-1
      license: $BUOYANT_LICENSE
      controlPlaneConfig:
        proxy:
          image:
            version: enterprise-2.15.1-1
        identityTrustAnchorsPEM: |
$(sed 's/^/          /' < certs/ca.crt )
        identity:
          issuer:
            scheme: kubernetes.io/tls
EOF

kubectl apply -f linkerd-control-plane-config-hazl.yaml --context=hazl
kubectl apply -f linkerd-control-plane-config-topo.yaml --context=topo

watch -n 1 kubectl get pods -A -o wide --sort-by .metadata.namespace --context=hazl
watch -n 1 kubectl get pods -A -o wide --sort-by .metadata.namespace --context=topo

linkerd check --context hazl
linkerd check --context topo

cat <<EOF > linkerd-data-plane-config.yaml
---
apiVersion: linkerd.buoyant.io/v1alpha1
kind: DataPlane
metadata:
  name: linkerd-buoyant
  namespace: linkerd-buoyant
spec:
  workloadSelector:
    matchLabels: {}
EOF

kubectl apply -f linkerd-data-plane-config.yaml --context=hazl
kubectl apply -f linkerd-data-plane-config.yaml --context=topo

kubectl rollout status daemonset/buoyant-cloud-metrics -n linkerd-buoyant --context=hazl
kubectl rollout status daemonset/buoyant-cloud-metrics -n linkerd-buoyant --context=topo

linkerd check --proxy -n linkerd-buoyant --context hazl
linkerd check --proxy -n linkerd-buoyant --context topo

kubectl apply -k orders --context=hazl
kubectl apply -k orders-topo --context=topo

watch -n 1 kubectl get pods -n orders -o wide --sort-by .spec.nodeName --context=hazl
watch -n 1 kubectl get pods -n orders -o wide --sort-by .spec.nodeName --context=topo

cat <<EOF > linkerd-data-plane-orders-config.yaml
---
apiVersion: linkerd.buoyant.io/v1alpha1
kind: DataPlane
metadata:
  name: linkerd-orders
  namespace: orders
spec:
  workloadSelector:
    matchLabels: {}
EOF

kubectl apply -f linkerd-data-plane-orders-config.yaml --context=hazl
kubectl apply -f linkerd-data-plane-orders-config.yaml --context=topo
