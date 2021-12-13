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

step certificate create identity.linkerd.cluster.local \
  "${CERT_ROOT}/issuer.crt" "${CERT_ROOT}/issuer.key" \
  --profile intermediate-ca \
  --not-after 8760h \
  --no-password \
  --insecure \
  --ca "${CERT_ROOT}/ca.crt" --ca-key "${CERT_ROOT}/ca.key"

helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.6.1 \
  --set installCRDs=true

helm install linkerd2 \
  --set-file identityTrustAnchorsPEM=$CERT_ROOT/ca.crt \
  --set-file identity.issuer.tls.crtPEM=$CERT_ROOT/issuer.crt \
  --set-file identity.issuer.tls.keyPEM=$CERT_ROOT/issuer.key \
  --set identity.issuer.crtExpiry=$(date -d '+8760 hour' +"%Y-%m-%dT%H:%M:%SZ") \
  --set controllerLogLevel=trace \
  -f https://raw.githubusercontent.com/linkerd/linkerd2/stable-2.10.2/charts/linkerd2/values-ha.yaml \
  linkerd/linkerd2 \
  --version 2.10.2
