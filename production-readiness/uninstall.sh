#!/bin/bash

installed=$(k3d cluster list)
sub='sma'

if [[ "$installed" == *"$sub"* ]]; then
    k3d cluster delete sma
    echo "cluster uninstalled"
fi

rm -rf linkerd-enterprise-control-plane
rm -f linkerd-loki-values.yaml
rm -f linkerd-alloy-values.yaml
rm -f linkerd-o11y-stack.yaml