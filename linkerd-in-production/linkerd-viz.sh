#!/bin/bash

set -eu

while ! linkerd check ; do :; done

helm install linkerd-viz \
  --create-namespace \
  -f https://raw.githubusercontent.com/linkerd/linkerd2/stable-2.10.2/viz/charts/linkerd-viz/values-ha.yaml \
  linkerd/linkerd-viz \
  --version 2.10.2