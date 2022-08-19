#!/bin/env bash

# BEFORE STARTING: arrange for "emoji.example.com", "books.example.com", and
# "viz.example.com" to resolve to 127.0.0.1, perhaps by editing /etc/hosts.

# Use a k3d cluster for this demo.
k3d cluster delete observability &>/dev/null

# Expose ports 80 and 443 to the local host, so that our ingress can work.
# Also, don't install traefik, since we'll be putting Linkerd on instead.
k3d cluster create observability \
    -p "80:80@loadbalancer" -p "443:443@loadbalancer" \
    --k3s-arg '--no-deploy=traefik@server:*;agents:*'

# Make sure that we're in the namespace we expect...
kubectl ns default

# ...then install Linkerd. This is mostly from the quickstart; the kustomize run is
# to open up the linkerd-viz dashboard to any hostname.
curl -sL https://run.linkerd.io/install | sh
linkerd install | kubectl apply -f - && linkerd check
kubectl kustomize kustomized/linkerd | kubectl apply -f - && linkerd viz check

# Once that's done, install emojivoto and books from their quickstarts, injecting them
# into the mesh...
curl -sL https://run.linkerd.io/emojivoto.yml | linkerd inject - | kubectl apply -f -
kubectl create ns booksapp
curl -sL https://run.linkerd.io/booksapp.yml | linkerd inject - | kubectl apply -n booksapp -f -

# ...and install the booksapp service profiles too.
kubectl apply -f ../101/service_profiles/source/books-profiles.yaml 

# Next up: install Emissary-ingress 3.1.0 as the ingress. This is mostly following
# the quickstart: the kustomize commands change the replica counts for emissary-apiext
# and emissary itself to 1 instead of 3, to lighten the load on k3d.

EMISSARY_CRDS=https://app.getambassador.io/yaml/emissary/3.1.0/emissary-crds.yaml
EMISSARY_INGRESS=https://app.getambassador.io/yaml/emissary/3.1.0/emissary-emissaryns.yaml

kubectl create namespace emissary && \
curl -o kustomized/emissary-crds/emissary-crds.yaml $EMISSARY_URL
curl -o kustomized/emissary/emissary-emissaryns.yaml $EMISSARY_INGRESS

kubectl kustomize kustomized/emissary-crds | kubectl apply -f -
kubectl wait --timeout=90s --for=condition=available deployment emissary-apiext -n emissary-system
kubectl kustomize kustomized/emissary | kubectl apply -f - 
kubectl -n emissary wait --for condition=available --timeout=90s deploy -lproduct=aes

# Finally, configure Emissary for HTTP - not HTTPS! - host-based routing to
# our cluster...
kubectl apply -f emissary-yaml

# ...and inject it into Linkerd.
kubectl get -n emissary deploy -o yaml | linkerd inject - | kubectl apply -f -
