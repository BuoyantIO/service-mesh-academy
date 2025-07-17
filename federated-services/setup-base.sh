# SPDX-FileCopyrightText: 2024 Buoyant Inc.
# SPDX-License-Identifier: Apache-2.0

set -ex

# Set up the Linkerd CLI
curl -sL https://enterprise.buoyant.io/install | LINKERD2_VERSION=enterprise-2.18.2 sh
export PATH=$PATH:$HOME/.linkerd2/bin

# Start by smiting _everything_.
./localcluster delete clusters || true

# Make sure we have our docker network.
docker inspect kind || bash setup-network.sh

# Then create our clusters.
./localcluster create clusters

# Make sure we have the certs we need...
./localcluster certs --force clusters

# ...and then we can install Linkerd -- but only do the east cluster for now!
# ./localcluster linkerd clusters/east
./localcluster linkerd clusters
