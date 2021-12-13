#!/bin/bash

set -eu

CERT_ROOT=.

k3d cluster create \
    workshop \
    --servers 3 \
    --wait

step certificate create \
  root.linkerd.cluster.local \
  "${CERT_ROOT}/ca.crt" "${CERT_ROOT}/ca.key" \
  --profile root-ca \
  --no-password --insecure \
  --force


kubectl label namespace kube-system config.linkerd.io/admission-webhooks=disabled

helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.6.1 \
  --set installCRDs=true

kubectl create ns linkerd

kubectl create secret tls \
    linkerd-trust-anchor \
    --cert="${CERT_ROOT}"/ca.crt \
    --key="${CERT_ROOT}"/ca.key \
    --namespace=linkerd

kubectl apply -f ./cert-manager.yml

helm install linkerd2 \
  --set-file identityTrustAnchorsPEM=$CERT_ROOT/ca.crt \
  --set identity.issuer.scheme=kubernetes.io/tls \
  --set controllerLogLevel=trace \
  --set installNamespace=false \
  -f https://raw.githubusercontent.com/linkerd/linkerd2/stable-2.10.2/charts/linkerd2/values-ha.yaml \
  linkerd/linkerd2 \
  --version 2.10.2
