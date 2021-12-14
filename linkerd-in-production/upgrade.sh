#!/bin/bash 

set -eu

helm upgrade linkerd2 \
  linkerd/linkerd2 \
  -f ./values-ha.yaml \
  --version 2.11.1 \
  --atomic \
  --reset-values

sleep 30

while ! linkerd check ; do :; done

helm upgrade linkerd-viz \
  linkerd/linkerd-viz \
  --version 2.11.1 \
  --atomic \
  --reset-values