# SPDX-FileCopyrightText: 2024 Buoyant Inc.
# SPDX-License-Identifier: Apache-2.0

set -ex

# Start by smiting _everything_.
./localcluster delete .

# Make sure we have our docker network.
docker inspect kind || bash setup-network.sh

# Then we want to create just the cdn and faces clusters.
./localcluster create clusters cdn faces color color-b faces-dr smiley-dr

# Make sure we have the certs we need...
./localcluster certs --force clusters cdn faces color color-b faces-dr smiley-dr

# Set up the Linkerd CLI
curl -sL https://enterprise.buoyant.io/install | LINKERD2_VERSION=enterprise-2.15.5 sh
export PATH=$PATH:$HOME/.linkerd2/bin

# ...and then we can install Linkerd.
./localcluster linkerd clusters cdn faces color color-b faces-dr smiley-dr

# Go ahead and group everything up.
./localcluster group clusters faces color color-b faces-dr smiley-dr

# # Finally, link cdn -> faces and faces-dr.
./localcluster link --src cdn --dst faces clusters
./localcluster link --src cdn --dst faces-dr clusters

# Get Faces running in faces and faces-dr.
kubectl --context faces create ns faces
kubectl --context faces annotate ns/faces linkerd.io/inject=enabled

    #  --set gui.serviceType=LoadBalancer \

helm install --kube-context faces \
     faces -n faces \
     oci://ghcr.io/buoyantio/faces-chart --version 1.4.0 \
     --set face.errorFraction=0 \
     --set backend.errorFraction=0

kubectl --context faces-dr create ns faces
kubectl --context faces-dr annotate ns/faces linkerd.io/inject=enabled

    #  --set gui.serviceType=LoadBalancer \

helm install --kube-context faces-dr \
     faces -n faces \
     oci://ghcr.io/buoyantio/faces-chart --version 1.4.0 \
     --set face.errorFraction=0 \
     --set color.color=white \
     --set backend.errorFraction=0

# faces-dr doesn't need a smiley workload.
kubectl --context faces-dr delete deploy -n faces smiley

# Preinstall just the color service (with a green color) in the color cluster,
# and preinstall just the color service (with the blue color) in the color-b
# cluster.
kubectl --context color create ns faces
kubectl --context color annotate ns/faces linkerd.io/inject=enabled

helm install --kube-context color \
     faces -n faces \
     oci://ghcr.io/buoyantio/faces-chart --version 1.4.0 \
     --set color.color=green \
     --set color.errorFraction=0

kubectl --context color delete deploy -n faces faces-gui face smiley

kubectl --context color-b create ns faces
kubectl --context color-b annotate ns/faces linkerd.io/inject=enabled

helm install --kube-context color-b \
     faces -n faces \
     oci://ghcr.io/buoyantio/faces-chart --version 1.4.0 \
     --set color.errorFraction=0

kubectl --context color-b delete deploy -n faces faces-gui face smiley

# Preinstall just the smiley service (with a screaming face) in the smiley-dr
# cluster.
kubectl --context smiley-dr create ns faces
kubectl --context smiley-dr annotate ns/faces linkerd.io/inject=enabled

helm install --kube-context smiley-dr \
     faces -n faces \
     oci://ghcr.io/buoyantio/faces-chart --version 1.4.0 \
     --set smiley.errorFraction=0 \
     --set smiley.smiley=Screaming

kubectl --context smiley-dr delete deploy -n faces faces-gui face color

# Next up, get Emissary installed to pretend to be the CDN.
kubectl --context cdn create ns emissary
kubectl --context cdn annotate ns/emissary linkerd.io/inject=enabled

helm install --kube-context cdn \
     emissary-crds -n emissary \
     oci://ghcr.io/emissary-ingress/emissary-crds-chart \
     --version 0.0.0-test \
     --wait

helm install --kube-context cdn \
     emissary-ingress \
     oci://ghcr.io/emissary-ingress/emissary-chart \
     -n emissary \
     --version 0.0.0-test \
     --set replicaCount=1 \
     --set nameOverride=emissary \
     --set fullnameOverride=emissary

# Wait for everything to be running
kubectl --context cdn rollout status -n emissary deploy

kubectl --context faces rollout status -n faces deploy
kubectl --context color rollout status -n faces deploy
kubectl --context color-b rollout status -n faces deploy
kubectl --context faces-dr rollout status -n faces deploy
kubectl --context smiley-dr rollout status -n faces deploy

# Go ahead and mirror the faces-gui service in the faces cluster...
kubectl --context cdn create ns faces
kubectl --context faces label -n faces \
    svc/faces-gui mirror.linkerd.io/exported=true

# ...and the smiley service in the smiley-dr cluster.
kubectl --context smiley-dr label -n faces \
    svc/smiley mirror.linkerd.io/exported=remote-discovery

# Finally, set up an HTTPRoute in faces-dr to route to the smiley-dr smiley
# workload.
kubectl --context faces-dr apply -f clusters/smiley-dr/route-to-smiley-dr.yaml

# Finally, set up the TCPMapping to tell Emissary to route stuff.
kubectl --context cdn apply -f clusters/cdn/tcpmapping.yaml

