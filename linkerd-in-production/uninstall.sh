#!/bin/bash

installed=$(helm list -q)
sub='linkerd2'

if [[ "$installed" == *"$sub"* ]]; then
    helm uninstall linkerd2
    echo "linkerd uninstalled"
fi

installed=$(k3d cluster list)
sub='workshop'

if [[ "$installed" == *"$sub"* ]]; then
    k3d cluster delete workshop
    echo "cluster uninstalled"
fi