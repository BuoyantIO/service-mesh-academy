#!/bin/bash

# Creates a k3d cluster (default: dev) and installs Linkerd.
# First, Linkerd CLI is installed (if CLI binary path not overwritten)
# and after that, Linkerd is installed in the cluster using the CLI.
#
set -e
COLOR='\033[1;32m'
SEP="+===============================+"

# Name of the cluster to create, default: dev
#
CLUSTER_NAME="${CLUSTER_NAME:-dev}"

# Path for CLI binary, defaults to linkerd
# CLI binary (if installed).
#
LINKERD="${LINKERD:-linkerd}"

# First, create a cluster in k3d/kind.
#
echo -e "${COLOR} Creating k3d cluster $CLUSTER_NAME...\n\033[0m${SEP}"
k3d cluster create $CLUSTER_NAME

# Install latest Linkerd CLI
#
if [ "$LINKERD" = "linkerd" ]; then
  echo -e "${COLOR} Installing CLI...\n\033[0m${SEP}"
  curl -sL run.linkerd.io/install | sh
else
  echo -e "${COLOR} Skipping CLI install...\nUsing \033[0m$LINKERD\n${SEP}"
fi

# Install Linkerd in your cluster.
#
echo -e "${COLOR} Installing Linkerd\n\033[0m${SEP}"
$LINKERD install --context=k3d-$CLUSTER_NAME \
| kubectl --context=k3d-$CLUSTER_NAME apply -f - 

