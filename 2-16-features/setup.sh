CLUSTER=${CLUSTER:-sma-dual}

kind delete cluster --name $CLUSTER
kind create cluster --config $CLUSTER/kind.yaml
kubectl wait --for=condition=Ready --timeout=5m nodes --all

docker network inspect kind | python3 choose-ipam.py

helm install \
     -n metallb --create-namespace \
     metallb metallb/metallb

kubectl rollout status -n metallb deploy

kubectl apply -f $CLUSTER/metallb.yaml

linkerd install --crds | kubectl apply -f -
linkerd install --set disableIPv6=false | kubectl apply -f -
linkerd check

kubectl create ns faces
kubectl annotate ns faces linkerd.io/inject=enabled

helm install faces -n faces \
     oci://ghcr.io/buoyantio/faces-chart --version 1.4.1 \
     -n faces \
     --set gui.serviceType=LoadBalancer \
     --set smiley2.enabled=true \
     --set smiley2.smiley=HeartEyes \
     --set color2.enabled=true \
     --set color2.color=green \
     --set backend.errorFraction=0 \
     --set face.errorFraction=0

kubectl rollout status -n faces deploy

kubectl patch -n faces svc faces-gui -p '{"spec": {"ipFamilyPolicy": "RequireDualStack"}}'
