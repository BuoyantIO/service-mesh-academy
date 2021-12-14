#!/bin/bash

set -eu

while ! linkerd check ; do :; done

helm install linkerd-viz \
  --create-namespace \
  -f https://raw.githubusercontent.com/linkerd/linkerd2/stable-2.11.1/viz/charts/linkerd-viz/values-ha.yaml \
  linkerd/linkerd-viz 

# In order to use tap and top on the control plane components, they must 
# be restarted after linkerd-viz has been deployed

echo "Restarting control plane components to make them tappable (this is optional)"

kubectl rollout restart deploy -n linkerd 

while ! linkerd check ; do :; done

echo "Control plane restarted"