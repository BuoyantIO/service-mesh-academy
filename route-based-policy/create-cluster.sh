#!/bin/env bash

set -ex

# BEFORE STARTING: arrange for "emoji.example.com", "books.example.com", and
# "viz.example.com" to resolve to 127.0.0.1, perhaps by editing /etc/hosts.

# Use a k3d cluster for this demo.
k3d cluster delete policy &>/dev/null

# Expose ports 80 and 443 to the local host, so that our ingress can work.
# Also, don't install traefik, since we'll be putting Linkerd on instead.
k3d cluster create policy \
    -p "80:80@loadbalancer" -p "443:443@loadbalancer" \
    --k3s-arg '--no-deploy=traefik@server:*;agents:*'

# Make sure that we're in the namespace we expect...
kubectl ns default

# ...then install Linkerd, per the quickstart.
#### LINKERD_INSTALL_START
curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install | sh

linkerd install --crds | kubectl apply -f -
linkerd install | kubectl apply -f -
linkerd check
#### LINKERD_INSTALL_END

# Next up, install Grafana, since we don't get that by default in 2.12.
#### GRAFANA_INSTALL_START
helm repo add grafana https://grafana.github.io/helm-charts
helm install grafana -n grafana --create-namespace grafana/grafana \
  -f https://raw.githubusercontent.com/linkerd/linkerd2/main/grafana/values.yaml \
  --wait
linkerd viz install --set grafana.url=grafana.grafana:3000 | kubectl apply -f -
linkerd check
#### GRAFANA_INSTALL_END

# curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/emojivoto.yml | linkerd inject - | kubectl apply -f -

# Once that's done, install books from its quickstart, injecting it into the
# mesh, and then installing its service profiles too.

#### BOOKS_INSTALL_START
kubectl create ns booksapp
curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/booksapp.yml | \
  linkerd inject - | kubectl apply -n booksapp -f -

curl --proto '=https' --tlsv1.2 -sSfL \
  https://raw.githubusercontent.com/JasonMorgan/linkerd-demos/main/101/service_profiles/source/booksapp.yaml | \
  kubectl apply -f -
#### BOOKS_INSTALL_END

# Next up: install Emissary-ingress 3.1.0 as the ingress. This is mostly following
# the quickstart: the kustomize commands change the replica counts for emissary-apiext
# and emissary itself to 1 instead of 3, to lighten the load on k3d.

#### EMISSARY_INSTALL_START
EMISSARY_CRDS=https://app.getambassador.io/yaml/emissary/3.1.0/emissary-crds.yaml
EMISSARY_INGRESS=https://app.getambassador.io/yaml/emissary/3.1.0/emissary-emissaryns.yaml

kubectl create namespace emissary && \
curl -o kustomized/emissary-crds/emissary-crds.yaml $EMISSARY_CRDS
curl -o kustomized/emissary/emissary-emissaryns.yaml $EMISSARY_INGRESS

kubectl kustomize kustomized/emissary-crds | kubectl apply -f -
kubectl wait --timeout=90s --for=condition=available deployment emissary-apiext -n emissary-system
kubectl kustomize kustomized/emissary | linkerd inject - | kubectl apply -f - 
kubectl -n emissary wait --for condition=available --timeout=90s deploy -lproduct=aes
#### EMISSARY_INSTALL_END

# Finally, configure Emissary for HTTP - not HTTPS! - host-based routing to
# our cluster...
#### EMISSARY_CONFIGURE_START
kubectl apply -f emissary-yaml
#### EMISSARY_CONFIGURE_END
