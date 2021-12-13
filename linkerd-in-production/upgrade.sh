#!/bin/bash 

set -eu

helm upgrade linkerd2 \
  linkerd/linkerd2 \
  --version 2.11.1

sleep 30

while ! linkerd check ; do :; done

helm upgrade linkerd-viz \
  linkerd/linkerd-viz \
  --version 2.11.1