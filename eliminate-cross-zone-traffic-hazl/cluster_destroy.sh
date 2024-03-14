#!/bin/bash
# cluster_destroy.sh
# Demo script for the eliminate-cross-zone-traffic-hazl GitHub repository
# https://github.com/BuoyantIO/service-mesh-academy/tree/main/eliminate-cross-zone-traffic-hazl
# Automates cluster deletion and cleans up the hazl and topo kubectl contexts
# Tom Dean | Buoyant
# Last edit: 3/14/2024

# Remove the k3d clusters: hazl and topo

k3d cluster delete demo-cluster-orders-hazl
k3d cluster delete demo-cluster-orders-topo
k3d cluster list

# Remove the kubectl contexts: hazl and topo

kubectx -d hazl
kubectx -d topo
kubectx

exit 0