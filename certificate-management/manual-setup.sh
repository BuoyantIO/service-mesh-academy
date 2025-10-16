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

### SET UP CLUSTER

k3d cluster delete manual
k3d cluster create manual \
    --no-lb \
    --k3s-arg --disable=traefik@server:0

kubectl config rename-context k3d-manual manual

### GENERATE CERTIFICATES

mkdir -p certs

rm -rf certs/anchor.crt certs/anchor.key

step certificate create \
     --profile root-ca --no-password --insecure \
     --not-after='87600h' \
     root.linkerd.cluster.local \
     certs/anchor.crt certs/anchor.key

rm -rf "certs/issuer.crt" "certs/issuer.key"

step certificate create \
     --profile intermediate-ca --no-password --insecure \
     --ca certs/anchor.crt --ca-key certs/anchor.key \
     --not-after='2160h' \
     identity.linkerd.cluster.local \
     certs/issuer.crt certs/issuer.key

### SET UP CAs

kubectl create namespace linkerd

kubectl create configmap \
        linkerd-identity-trust-roots -n linkerd \
        --from-file=ca-bundle.crt=certs/anchor.crt

kubectl create secret generic \
    linkerd-identity-issuer -n linkerd \
    --type=kubernetes.io/tls \
    --from-file=ca.crt=certs/anchor.crt \
    --from-file=tls.crt=certs/issuer.crt \
    --from-file=tls.key=certs/issuer.key

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


