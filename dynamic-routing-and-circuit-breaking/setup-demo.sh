#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: 2022 Buoyant Inc.
# SPDX-License-Identifier: Apache-2.0
#
# Copyright 2022 Buoyant Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License.  You may obtain
# a copy of the License at
#
#     http:#www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Next up: install Emissary-ingress 3.1.0 as the ingress. This is mostly following
# the quickstart, but we force every Deployment to one replica to reduce the load
# on k3d.

#@SHOW

# Start by installing Linkerd. We'll use the latest stable version.

curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install | sh

linkerd check --pre
linkerd install --crds | kubectl apply -f -
linkerd install | kubectl apply -f -
linkerd viz install | kubectl apply -f -
linkerd check

# After that, we'll install Emissary as an ingress controller. The choice
# of ingress controller doesn't actually matter for this demo, we just need
# one to make it easy to get access to the Faces demo.
#
# This is almost straight out of the Emissary quickstart, but we force it
# to one replica to reduce the load on k3d, and we make sure to inject Emissary
# into the mesh.

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
    linkerd inject - | kubectl apply -f -

kubectl -n emissary wait --for condition=available --timeout=90s deploy -lproduct=aes
#### EMISSARY_INSTALL_END

# Finally, configure Emissary for HTTP - not HTTPS! - routing to our cluster.
#### EMISSARY_CONFIGURE_START
kubectl apply -f emissary-yaml
#### EMISSARY_CONFIGURE_END

# Once that's done, install Faces, being sure to inject it into the mesh.
# Install its Mappings too: all of these things are in the k8s/01-base
# directory.

#### FACES_INSTALL_START
FACES_DEMO_BASE=https://raw.githubusercontent.com/BuoyantIO/faces-demo/main
FACES_K8S=${FACES_DEMO_BASE}/k8s/01-base

kubectl create namespace faces
linkerd inject k8s/01-base | kubectl apply -f -
#### FACES_INSTALL_END

# After that, wait for the Faces application to be ready.
kubectl -n faces wait --for condition=available --timeout=90s deploy --all

while true; do
    EMISSARY_IP=$(kubectl -n emissary get svc emissary-ingress -o 'go-template={{range .status.loadBalancer.ingress}}{{or .ip .hostname}}{{end}}')
    if [ -n "$EMISSARY_IP" ]; then
        echo "Emissary IP: $EMISSARY_IP"
        break
    fi
    echo "...waiting for IP..."
    sleep 1
done

# If OVERRIDE_EMISSARY_IP is set, use its value instead.
if [ -n "$OVERRIDE_EMISSARY_IP" ]; then
    EMISSARY_IP=$OVERRIDE_EMISSARY_IP
fi

# Wait until the Faces application is actually talking to us.

REMAINING=60
while true; do \
    printf "." ;\
    status=$(curl -s -o /dev/null -w "%{http_code}" http://${EMISSARY_IP}/faces/) ;\
    if [ "$status" = "200" ]; then \
        echo "Faces ready!" ;\
        break ;\
    fi ;\
    REMAINING=$((REMAINING-1)) ;\
    if [ "$REMAINING" -le 0 ]; then \
        echo "Faces not ready after 60 seconds" ;\
        exit 1 ;\
    fi ;\
    sleep 1 ;\
done
