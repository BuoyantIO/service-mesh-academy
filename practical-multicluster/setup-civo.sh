#!/bin/bash

set -x

# Cleanup
linkerd --context civo-faces multicluster uninstall | kubectl --context civo-faces delete -f -
linkerd --context civo-faces uninstall | kubectl --context civo-faces delete -f -

# Certs
rm -f clusters/civo-faces/issuer*

step certificate create \
  identity.linkerd.cluster.local \
  clusters/civo-faces/issuer.crt \
  clusters/civo-faces/issuer.key \
  --profile intermediate-ca \
  --ca ./certs/root.crt \
  --ca-key ./certs/root.key \
  --not-after 8760h --no-password --insecure

# Linkerd
linkerd --context civo-faces install --crds | kubectl --context civo-faces apply -f -
linkerd --context civo-faces install \
    --set disableIPv6=true \
    --identity-trust-anchors-file ./certs/root.crt \
    --identity-issuer-certificate-file clusters/civo-faces/issuer.crt \
    --identity-issuer-key-file clusters/civo-faces/issuer.key \
    | kubectl --context civo-faces apply -f -

# Faces
kubectl --context civo-faces create ns faces
kubectl --context civo-faces annotate ns/faces linkerd.io/inject=enabled

helm install --kube-context civo-faces \
    faces -n faces \
    oci://ghcr.io/buoyantio/faces-chart --version 1.4.0 \
    --set face.errorFraction=0 \
    --set backend.errorFraction=0 \
    --set smiley.smiley=Grinning \
    --set color.color=white

kubectl --context civo-faces rollout status -n faces deploy

# Multicluster
linkerd --context civo-faces multicluster install | kubectl --context civo-faces apply -f -

# Link
# linkerd --context civo-faces multicluster link --cluster-name civo-faces | kubectl --context cdn apply -f -