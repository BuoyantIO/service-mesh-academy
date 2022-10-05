#!/bin/env bash

set -ex

# BEFORE STARTING: arrange for "emoji.example.com", "books.example.com", and
# "viz.example.com" to resolve to 127.0.0.1, perhaps by editing /etc/hosts.

# Make sure that we're in the namespace we expect...
kubectl ns default

linkerd () {
    $HOME/bin/linkerd-edge-22.10.1 "$@"
}

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

# Once that's done, install emojivoto from its quickstart, injecting it into the
# mesh...

#### EMOJIVOTO_INSTALL_START
curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/emojivoto.yml | linkerd inject - | kubectl apply -f -
#### EMOJIVOTO_INSTALL_END

# ...then do the same for the booksapp -- but also install its ServiceProfiles.

#### BOOKS_INSTALL_START
kubectl create ns booksapp
curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/booksapp.yml | \
  linkerd inject - | kubectl apply -n booksapp -f -

curl --proto '=https' --tlsv1.2 -sSfL \
  https://raw.githubusercontent.com/JasonMorgan/linkerd-demos/main/101/service_profiles/source/booksapp.yaml | \
  kubectl apply -f -
#### BOOKS_INSTALL_END

# Next up: install Emissary-ingress 3.1.0 as the ingress. This is mostly following
# the quickstart, but we force every Deployment to one replica to reduce the load
# on k3d.

#### EMISSARY_INSTALL_START
EMISSARY_CRDS=https://app.getambassador.io/yaml/emissary/3.1.0/emissary-crds.yaml
EMISSARY_INGRESS=https://app.getambassador.io/yaml/emissary/3.1.0/emissary-emissaryns.yaml

kubectl create namespace emissary && \
curl --proto '=https' --tlsv1.2 -sSfL $EMISSARY_CRDS | \
    sed -e 's/replicas: 3/replicas: 1/' | \
    kubectl apply -f -
kubectl wait --timeout=90s --for=condition=available deployment emissary-apiext -n emissary-system

curl --proto '=https' --tlsv1.2 -sSfL $EMISSARY_INGRESS | \
    sed -e 's/replicas: 3/replicas: 1/' | \
    linkerd inject - | \
    kubectl apply -f -

kubectl -n emissary wait --for condition=available --timeout=90s deploy -lproduct=aes
#### EMISSARY_INSTALL_END

# Finally, configure Emissary for HTTP - not HTTPS! - host-based routing to
# our cluster, and inject it into the mesh.
#### EMISSARY_CONFIGURE_START
kubectl apply -f emissary-yaml
#### EMISSARY_CONFIGURE_END
