k3d cluster delete sma
k3d cluster create sma \
      --no-lb \
      --k3s-arg --disable=traefik,metrics-server@server:0

linkerd install --crds | kubectl apply -f -
linkerd install | kubectl apply -f -
linkerd check

helm install grafana -n grafana --create-namespace grafana/grafana \
  -f grafana-values.yaml

linkerd viz install --set grafana.url=grafana.grafana:3000 \
  | kubectl apply -f -


# kubectl apply -f grafana-authpolicy.yaml

kubectl create ns emissary
kubectl annotate ns emissary linkerd.io/inject=enabled

helm install emissary-crds \
  oci://ghcr.io/emissary-ingress/emissary-crds-chart \
  -n emissary \
  --version 0.0.0-test \
  --wait

helm install emissary-ingress \
     oci://ghcr.io/emissary-ingress/emissary-chart \
     -n emissary \
     --version 0.0.0-test \
     --set replicaCount=1 \
     --set nameOverride=emissary \
     --set fullnameOverride=emissary

kubectl create ns faces
kubectl annotate ns faces linkerd.io/inject=enabled

helm install faces -n faces \
     oci://ghcr.io/buoyantio/faces-chart --version 1.2.0 \
     -n faces \
     --set smiley2.enabled=true \
     --set color2.enabled=true

curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/emojivoto.yml \
  | kubectl apply -f -

kubectl annotate ns emojivoto linkerd.io/inject=enabled

kubectl rollout restart -n emojivoto deploy

# Wait for everything to be ready.
kubectl -n emissary wait --for condition=available --timeout=90s deploy -lproduct=aes
kubectl rollout status -n faces deploy
kubectl rollout status -n emojivoto deploy

kubectl apply -f init-yaml

kubectl annotate -n faces service face \
        retry.linkerd.io/http=5xx retry.linkerd.io/limit=3
kubectl annotate -n faces service smiley \
        retry.linkerd.io/http=5xx retry.linkerd.io/limit=3
kubectl annotate -n faces service color \
        retry.linkerd.io/http=5xx retry.linkerd.io/limit=3
kubectl annotate -n faces service color timeout.linkerd.io/request=300ms
