# The setup for this federated Service and egress demo is... complex. For
# federated Services, we have four clusters going:
#
# - k3d-face has the GUI and the `face` workload. The GUI is configured as a
#   loadbalancer Service, and the `face` workload is configured to use a
#   SMILEY_SERVICE of smiley-federated and a COLOR_SERVICE of color:8000.
#
# - kind-smiley-1, -2, and -3 are Kind clusters that are _only_ running the
#   `smiley` workload.
#
# - There's an external `color` container running in Docker, not in Kubernetes
#   at all.

V4_BASE=172.17

# Include the kind network's address space in the cluster networks,
# but not the egress network's address space.

CLUSTER_NETWORKS="10.0.0.0/8\,${V4_BASE}.1.0/24"

FACES_CHART=${FACES_CHART:-oci://ghcr.io/buoyantio/faces-chart --version 2.0.0-rc.2}

echo "Creating Docker networks..."

echo "...kind"
docker network create kind \
    --subnet "${V4_BASE}.1.0/24" \
    --gateway "${V4_BASE}.1.1" \
    -o "com.docker.network.bridge.enable_ip_masquerade=true" \
    -o "com.docker.network.driver.mtu=1500"

echo "...egress"
docker network create egress \
    --subnet "${V4_BASE}.2.0/24" \
    --gateway "${V4_BASE}.2.1" \
    -o "com.docker.network.bridge.enable_ip_masquerade=true" \
    -o "com.docker.network.driver.mtu=1500"

set -e

echo "Creating clusters..."
ctlptl apply -f clusters.yaml

FACE_IP=$(docker inspect k3d-face-server-0 | \
        jq -r '.[0].NetworkSettings.Networks[].IPAddress')
echo FACE_IP is ${FACE_IP}

SMILEY_1_IP=$(docker inspect smiley-1-control-plane | \
        jq -r '.[0].NetworkSettings.Networks[].IPAddress')
echo SMILEY_1_IP is ${SMILEY_1_IP}

SMILEY_2_IP=$(docker inspect smiley-2-control-plane | \
        jq -r '.[0].NetworkSettings.Networks[].IPAddress')
echo SMILEY_2_IP is ${SMILEY_2_IP}

SMILEY_3_IP=$(docker inspect smiley-3-control-plane | \
        jq -r '.[0].NetworkSettings.Networks[].IPAddress')
echo SMILEY_3_IP is ${SMILEY_3_IP}

echo "Fixing API server addresses..."
kubectl config set clusters.k3d-face.server "https://${FACE_IP}:6443"
kubectl config set clusters.kind-smiley-1.server "https://${SMILEY_1_IP}:6443"
kubectl config set clusters.kind-smiley-2.server "https://${SMILEY_2_IP}:6443"
kubectl config set clusters.kind-smiley-3.server "https://${SMILEY_3_IP}:6443"

echo "Adding routes..."
docker exec k3d-face-server-0 \
  ip route add 10.55.1.0/24 via ${SMILEY_1_IP}
docker exec smiley-1-control-plane \
  ip route add 10.55.0.0/24 via ${FACE_IP}

docker exec k3d-face-server-0 \
  ip route add 10.55.2.0/24 via ${SMILEY_2_IP}
docker exec smiley-2-control-plane \
  ip route add 10.55.0.0/24 via ${FACE_IP}

docker exec k3d-face-server-0 \
  ip route add 10.55.3.0/24 via ${SMILEY_3_IP}
docker exec smiley-3-control-plane \
  ip route add 10.55.0.0/24 via ${FACE_IP}

echo "Connecting clusters to egress network..."
docker network connect egress k3d-face-server-0
# docker network connect egress smiley-1-control-plane
# docker network connect egress smiley-2-control-plane
# docker network connect egress smiley-3-control-plane

echo "Creating Linkerd trust anchors and identity issuers..."

rm -rf certs
mkdir certs

step certificate create root.linkerd.cluster.local \
     certs/anchor.crt certs/anchor.key \
     --profile root-ca \
     --no-password --insecure

step certificate create identity.linkerd.cluster.local \
     certs/face-issuer.crt certs/face-issuer.key \
     --profile intermediate-ca --not-after 8760h \
     --no-password --insecure \
     --ca certs/anchor.crt --ca-key certs/anchor.key

step certificate create identity.linkerd.cluster.local \
     certs/smiley-1-issuer.crt certs/smiley-1-issuer.key \
     --profile intermediate-ca --not-after 8760h \
     --no-password --insecure \
     --ca certs/anchor.crt --ca-key certs/anchor.key

step certificate create identity.linkerd.cluster.local \
     certs/smiley-2-issuer.crt certs/smiley-2-issuer.key \
     --profile intermediate-ca --not-after 8760h \
     --no-password --insecure \
     --ca certs/anchor.crt --ca-key certs/anchor.key

step certificate create identity.linkerd.cluster.local \
     certs/smiley-3-issuer.crt certs/smiley-3-issuer.key \
     --profile intermediate-ca --not-after 8760h \
     --no-password --insecure \
     --ca certs/anchor.crt --ca-key certs/anchor.key

echo "Setting up Linkerd CAs..."

echo "...k3d-face"
kubectl --context k3d-face create namespace linkerd

kubectl --context k3d-face create configmap \
        linkerd-identity-trust-roots -n linkerd \
        --from-file='ca-bundle.crt'=certs/anchor.crt

kubectl --context k3d-face create secret generic \
    linkerd-identity-issuer -n linkerd \
    --type=kubernetes.io/tls \
    --from-file=ca.crt=certs/anchor.crt \
    --from-file=tls.crt=certs/face-issuer.crt \
    --from-file=tls.key=certs/face-issuer.key

echo "...kind-smiley-1"
kubectl --context kind-smiley-1 create namespace linkerd

kubectl --context kind-smiley-1 create configmap \
        linkerd-identity-trust-roots -n linkerd \
        --from-file='ca-bundle.crt'=certs/anchor.crt

kubectl --context kind-smiley-1 create secret generic \
    linkerd-identity-issuer -n linkerd \
    --type=kubernetes.io/tls \
    --from-file=ca.crt=certs/anchor.crt \
    --from-file=tls.crt=certs/smiley-1-issuer.crt \
    --from-file=tls.key=certs/smiley-1-issuer.key

echo "...kind-smiley-2"
kubectl --context kind-smiley-2 create namespace linkerd

kubectl --context kind-smiley-2 create configmap \
        linkerd-identity-trust-roots -n linkerd \
        --from-file='ca-bundle.crt'=certs/anchor.crt

kubectl --context kind-smiley-2 create secret generic \
    linkerd-identity-issuer -n linkerd \
    --type=kubernetes.io/tls \
    --from-file=ca.crt=certs/anchor.crt \
    --from-file=tls.crt=certs/smiley-2-issuer.crt \
    --from-file=tls.key=certs/smiley-2-issuer.key

echo "...kind-smiley-3"
kubectl --context kind-smiley-3 create namespace linkerd

kubectl --context kind-smiley-3 create configmap \
        linkerd-identity-trust-roots -n linkerd \
        --from-file='ca-bundle.crt'=certs/anchor.crt

kubectl --context kind-smiley-3 create secret generic \
    linkerd-identity-issuer -n linkerd \
    --type=kubernetes.io/tls \
    --from-file=ca.crt=certs/anchor.crt \
    --from-file=tls.crt=certs/smiley-3-issuer.crt \
    --from-file=tls.key=certs/smiley-3-issuer.key

echo "Installing Linkerd CRDs..."

kubectl --context k3d-face apply -f experimental-install.yaml
kubectl --context kind-smiley-1 apply -f experimental-install.yaml
kubectl --context kind-smiley-2 apply -f experimental-install.yaml
kubectl --context kind-smiley-3 apply -f experimental-install.yaml

linkerd --context k3d-face install --crds \
    --set enableHttpRoutes=false \
    --set enableTcpRoutes=false \
    --set enableTlsRoutes=false \
    | kubectl --context k3d-face apply -f -

linkerd --context kind-smiley-1 install --crds \
    --set enableHttpRoutes=false \
    --set enableTcpRoutes=false \
    --set enableTlsRoutes=false \
    | kubectl --context kind-smiley-1 apply -f -

linkerd --context kind-smiley-2 install --crds \
    --set enableHttpRoutes=false \
    --set enableTcpRoutes=false \
    --set enableTlsRoutes=false \
    | kubectl --context kind-smiley-2 apply -f -

linkerd --context kind-smiley-3 install --crds \
    --set enableHttpRoutes=false \
    --set enableTcpRoutes=false \
    --set enableTlsRoutes=false \
    | kubectl --context kind-smiley-3 apply -f -

echo "Installing Linkerd control planes..."

linkerd --context k3d-face install \
    --set clusterNetworks="${CLUSTER_NETWORKS}" \
    --set enableHttpRoutes=false \
    --set enableTcpRoutes=false \
    --set enableTlsRoutes=false \
    --set identity.issuer.scheme=kubernetes.io/tls \
    --set identity.externalCA=true \
    | kubectl --context k3d-face apply -f -

linkerd --context kind-smiley-1 install \
    --set clusterNetworks="${CLUSTER_NETWORKS}" \
    --set enableHttpRoutes=false \
    --set enableTcpRoutes=false \
    --set enableTlsRoutes=false \
    --set identity.issuer.scheme=kubernetes.io/tls \
    --set identity.externalCA=true \
    | kubectl --context kind-smiley-1 apply -f -

linkerd --context kind-smiley-2 install \
    --set clusterNetworks="${CLUSTER_NETWORKS}" \
    --set enableHttpRoutes=false \
    --set enableTcpRoutes=false \
    --set enableTlsRoutes=false \
    --set identity.issuer.scheme=kubernetes.io/tls \
    --set identity.externalCA=true \
    | kubectl --context kind-smiley-2 apply -f -

linkerd --context kind-smiley-3 install \
    --set clusterNetworks="${CLUSTER_NETWORKS}" \
    --set enableHttpRoutes=false \
    --set enableTcpRoutes=false \
    --set enableTlsRoutes=false \
    --set identity.issuer.scheme=kubernetes.io/tls \
    --set identity.externalCA=true \
    | kubectl --context kind-smiley-3 apply -f -

linkerd --context k3d-face check
linkerd --context kind-smiley-1 check
linkerd --context kind-smiley-2 check
linkerd --context kind-smiley-3 check

echo "Installing Linkerd Viz..."

linkerd --context k3d-face viz install \
    | kubectl --context k3d-face apply -f -

echo "Installing Faces..."

echo "...k3d-face"
kubectl --context k3d-face create ns faces
kubectl --context k3d-face annotate ns faces linkerd.io/inject=enabled

helm --kube-context k3d-face install faces \
     -n faces \
     ${FACES_CHART} \
     --set face.errorFraction=0 \
     --set gui.serviceType=LoadBalancer \
     --set backend.errorFraction=0 \
     --set smiley.enabled=false \
     --set smiley2.enabled=false \
     --set smiley3.enabled=false \
     --set color.enabled=false \
     --set color2.enabled=false \
     --set color3.enabled=false

kubectl --context k3d-face set env -n faces deploy/face \
        COLOR_SERVICE=color:8000 \
        SMILEY_SERVICE=smiley-federated

kubectl --context k3d-face rollout status -n faces deploy

echo "...kind-smiley-1"
kubectl --context kind-smiley-1 create ns faces
kubectl --context kind-smiley-1 annotate ns faces linkerd.io/inject=enabled

helm --kube-context kind-smiley-1 install faces \
     -n faces \
     ${FACES_CHART} \
     --set face.enabled=false \
     --set backend.errorFraction=0 \
     --set smiley.enabled=true \
     --set smiley2.enabled=false \
     --set smiley3.enabled=false \
     --set color.enabled=false \
     --set color2.enabled=false \
     --set color3.enabled=false

kubectl --context kind-smiley-1 delete deploy,svc -n faces face faces-gui

echo "...kind-smiley-2"
kubectl --context kind-smiley-2 create ns faces
kubectl --context kind-smiley-2 annotate ns faces linkerd.io/inject=enabled

helm --kube-context kind-smiley-2 install faces \
     -n faces \
     ${FACES_CHART} \
     --set face.enabled=false \
     --set backend.errorFraction=0 \
     --set smiley.enabled=true \
     --set smiley2.enabled=false \
     --set smiley3.enabled=false \
     --set color.enabled=false \
     --set color2.enabled=false \
     --set color3.enabled=false

kubectl --context kind-smiley-2 delete deploy,svc -n faces face faces-gui

echo "...kind-smiley-3"
kubectl --context kind-smiley-3 create ns faces
kubectl --context kind-smiley-3 annotate ns faces linkerd.io/inject=enabled

helm --kube-context kind-smiley-3 install faces \
     -n faces \
     ${FACES_CHART} \
     --set face.enabled=false \
     --set backend.errorFraction=0 \
     --set smiley.enabled=true \
     --set smiley2.enabled=false \
     --set smiley3.enabled=false \
     --set color.enabled=false \
     --set color2.enabled=false \
     --set color3.enabled=false

kubectl --context kind-smiley-3 delete deploy,svc -n faces face faces-gui

