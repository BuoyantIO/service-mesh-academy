#!/usr/bin/env bash
#
# SPDX-FileCopyrightText: 2025 Buoyant Inc.
# SPDX-License-Identifier: Apache-2.0
#
# Copyright 2025 Buoyant Inc.
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

set -e

### SET UP CLUSTER

k3d cluster delete auto || true
k3d cluster create auto \
    --no-lb \
    --k3s-arg --disable=traefik@server:0

kubectl config delete-context auto || true
kubectl config rename-context k3d-auto auto

### INSTALL CERT-MANAGER

helm repo add jetstack https://charts.jetstack.io --force-update

helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true

kubectl rollout status -n cert-manager deploy

helm install \
  trust-manager jetstack/trust-manager \
  --namespace cert-manager \
  --set app.trust.namespace=cert-manager

kubectl rollout status -n cert-manager deploy

### SET UP CERT-MANAGER

kubectl create namespace linkerd

# Create the Issuer and Certificate for the trust anchor

kubectl apply -f cert-manager/trust-anchor-issuer.yaml
kubectl apply -f cert-manager/trust-anchor-cert.yaml

# Wait for the trust anchor to be issued

while true; do
    if kubectl get secret -n cert-manager linkerd-trust-anchor >/dev/null 2>&1; then
        break
    fi
    echo "Waiting for trust anchor to be issued..."
    sleep 5
done

# Create the ClusterIssuer and Certificate for the identity issuer

kubectl apply -f cert-manager/identity-issuer-clusterissuer.yaml
kubectl apply -f cert-manager/identity-issuer-cert.yaml

# Wait for the identity issuer to be issued

while true; do
    if kubectl get secret -n linkerd linkerd-identity-issuer >/dev/null 2>&1; then
        break
    fi
    echo "Waiting for identity issuer to be issued..."
    sleep 5
done

# Copy the current trust anchor to the previous trust anchor

kubectl get secret -n cert-manager linkerd-trust-anchor -o yaml \
        | sed -e s/linkerd-trust-anchor/linkerd-previous-anchor/ \
        | egrep -v '^  *(resourceVersion|uid)' \
        | kubectl apply -f -

# Create the trust roots bundle

kubectl apply -f cert-manager/linkerd-identity-trust-roots-bundle.yaml

# We have to install Linkerd before the trust bundle will actually be created. Sigh.

### INSTALL GATEWAY API

kubectl apply --server-side=true \
    -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/standard-install.yaml

### INSTALL LINKERD CRDS

linkerd install --crds | kubectl apply -f -

### INSTALL LINKERD

linkerd install \
    --identity-external-ca=true \
    --identity-external-issuer=true \
    | kubectl apply -f -

linkerd check

### INSTALL FACES

kubectl create ns faces
kubectl annotate ns/faces linkerd.io/inject=enabled

helm install -n faces faces \
     oci://ghcr.io/buoyantio/faces-chart \
     --version 2.0.0 \
     --set gui.serviceType=LoadBalancer \
     --set face.errorFraction=0 \
     --set backend.errorFraction=0

kubectl rollout status -n faces deploy


