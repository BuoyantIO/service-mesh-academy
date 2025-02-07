CLUSTER=${CLUSTER:-oneapi}

# Use the experimental-install.yaml file if it exists, otherwise use the URL.
GATEWAY_API=https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.1.1/experimental-install.yaml

if [ -f gateway-api/experimental-install ]; then \
    GATEWAY_API=gateway-api/experimental-install ;\
fi

# Function to copy things from the local Docker cache into the cluster
# XXX You'll need to edit image-list if you change FACES_VERSION or
# ENVOY_GATEWAY_VERSION.
load_images () {
    if [ -f image-list ]; then
        for image in $(grep : image-list); do
            c=$(docker images --format '{{ .Repository }}:{{ .Tag }}' | grep -c "$image")

            if [ $c -gt 0 ]; then
                echo "Found $image in local cache" >&2
                echo "$image"
            fi
        done > /tmp/load-$$

        if [ -s /tmp/load-$$ ]; then
            k3d image import -c ${CLUSTER} $(cat /tmp/load-$$)
        fi

        rm -f /tmp/load-$$
    fi
}

#@immed
echo GATEWAY_API is ${GATEWAY_API}

# Select versions of Faces and Envoy Gateway to install.
FACES_VERSION=2.0.0-rc.2
ENVOY_GATEWAY_VERSION=1.3.0

# 1.1.2
ENVOY_GATEWAY_CHART=${ENVOY_GATEWAY_CHART:-oci://docker.io/envoyproxy/gateway-helm --version v${ENVOY_GATEWAY_VERSION}}
FACES_CHART=${FACES_CHART:-oci://ghcr.io/buoyantio/faces-chart --version ${FACES_VERSION}}

#@immed
echo ENVOY_GATEWAY_CHART is ${ENVOY_GATEWAY_CHART}
#@immed
echo FACES_CHART is ${FACES_CHART}

#@SHOW
docker network create egress

k3d cluster delete ${CLUSTER}

# Expose ports 80 and 443 to the local host, so that our ingress can work.
# Don't install traefik - we'll use Envoy Gateway with Linkerd instead.
k3d cluster create ${CLUSTER} \
	-p "80:80@loadbalancer" -p "443:443@loadbalancer" \
	--k3s-arg '--disable=traefik@server:*;agents:*'

# Load local images if present
load_images

K3D_CIDR=$(docker inspect k3d-${CLUSTER} | jq -r '.[0].IPAM.Config[0].Subnet')
#@immed
echo K3D_CIDR is ${K3D_CIDR}

docker network connect egress k3d-${CLUSTER}-server-0

# Start out-of-cluster workloads

docker run --network egress --detach --rm --name smiley \
       -e FACES_SERVICE=smiley -e USER_HEADER_NAME=X-Faces-User \
       ghcr.io/buoyantio/faces-workload:${FACES_VERSION}

docker run --network egress --detach --rm --name color \
       -e FACES_SERVICE=color -e USER_HEADER_NAME=X-Faces-User \
       ghcr.io/buoyantio/faces-color:${FACES_VERSION}

SMILEY_IP=$(docker inspect smiley | jq -r '.[0].NetworkSettings.Networks[].IPAddress')
#@immed
echo SMILEY_IP is ${SMILEY_IP}
COLOR_IP=$(docker inspect color | jq -r '.[0].NetworkSettings.Networks[].IPAddress')
#@immed
echo COLOR_IP is ${COLOR_IP}

# Install Gateway API CRDs
kubectl apply -f ${GATEWAY_API}

# With that done, fire up Linkerd.

linkerd install --crds \
    --set enableHttpRoutes=false \
    --set enableTcpRoutes=false \
    --set enableTlsRoutes=false \
  | kubectl apply -f -

linkerd install \
     --set clusterNetworks="10.0.0.0/8\,${K3D_CIDR}" \
     --set enableHttpRoutes=false \
     --set enableTcpRoutes=false \
     --set enableTlsRoutes=false \
     | kubectl apply -f -

linkerd viz install | kubectl apply -f -
linkerd check

# Install Envoy Gateway. Make sure to use native sidecars here!

kubectl create ns envoy-gateway-system
kubectl annotate ns envoy-gateway-system \
    linkerd.io/inject=enabled \
    config.alpha.linkerd.io/proxy-enable-native-sidecar=true

helm install envoy-gateway \
     -n envoy-gateway-system \
     ${ENVOY_GATEWAY_CHART}

kubectl rollout status -n envoy-gateway-system deploy

kubectl apply -f k8s/ingress-gateway.yaml
kubectl apply -f k8s/egress-gateway.yaml

kubectl rollout status -n envoy-gateway-system deploy

# Install Faces

kubectl create ns faces
kubectl annotate ns faces linkerd.io/inject=enabled

helm install faces \
     -n faces \
     ${FACES_CHART} \
     --set face.errorFraction=0 \
     --set backend.errorFraction=0 \
     --set smiley.enabled=false \
     --set smiley2.enabled=true \
     --set smiley3.enabled=true \
     --set color.enabled=false \
     --set color2.enabled=true \
     --set color3.enabled=true

kubectl set env -n faces deploy/face \
        COLOR_SERVICE=color:8000

kubectl apply -f k8s/face2.yaml

kubectl rollout status -n faces deploy
