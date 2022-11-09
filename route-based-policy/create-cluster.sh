#!/bin/env bash

set -ex

# BEFORE STARTING: arrange for "emoji.example.com", "books.example.com", and
# "viz.example.com" to resolve to 127.0.0.1, perhaps by editing /etc/hosts.

CLUSTER=${CLUSTER:-policy}

# Use a k3d cluster for this demo.
k3d cluster delete $CLUSTER &>/dev/null

# Expose ports 80 and 443 to the local host, so that our ingress can work.
# Also, don't install traefik, since we'll be putting Linkerd on instead.
k3d cluster create $CLUSTER \
    -p "80:80@loadbalancer" -p "443:443@loadbalancer" \
    --k3s-arg '--no-deploy=traefik@server:*;agents:*'

bash setup-cluster.sh
