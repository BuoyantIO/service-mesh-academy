#!/bin/bash

set -eu

while ! linkerd check ; do :; done

helm install linkerd-viz \
  --create-namespace \
  linkerd/linkerd-viz \
  --version 2.10.2