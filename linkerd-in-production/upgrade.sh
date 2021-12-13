#!/bin/bash 

set -eu

helm upgrade linkerd2 \
  linkerd/linkerd2 \
  --set identity.issuer.scheme=kubernetes.io/tls \
  --version 2.11.1

sleep 30

kubectl rollout restart deploy -n linkerd-viz

while ! linkerd check ; do :; done

helm upgrade linkerd-viz \
  linkerd/linkerd-viz \
  --version 2.11.1