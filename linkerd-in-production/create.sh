#!/bin/bash

set -eu

CERT_ROOT=.

if ! command -v k3d &> /dev/null
then
    echo "k3d could not be found, you can get it from https://k3d.io"
    exit
fi

if ! command -v step &> /dev/null
then
    echo "step could not be found, you can get it from https://smallstep.com/docs/step-cli/installation"
    exit
fi

if ! command -v kubectl &> /dev/null
then
    echo "kubectl could not be found, you can get it from https://kubernetes.io/docs/tasks/tools/#kubectl"
    exit
fi

if ! command -v linkerd &> /dev/null
then
    echo "linkerd could not be found, you can get it by running `curl -fsL https://run.linkerd.io/install | sh`"
    exit
fi

if ! command -v helm &> /dev/null
then
    echo "helm could not be found, you can get it from https://helm.sh/docs/intro/install/"
    exit
fi

echo "Hooray! All dependencies have been met!"

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

step certificate create \
  identity.linkerd.cluster.local \
  ${CERT_ROOT}/issuer.crt ${CERT_ROOT}/issuer.key \
  --profile intermediate-ca \
  --not-after 8760h --no-password --insecure \
  --ca ${CERT_ROOT}/ca.crt --ca-key ${CERT_ROOT}/ca.key \
  --force

kubectl label namespace kube-system config.linkerd.io/admission-webhooks=disabled

# helm install \
#   cert-manager jetstack/cert-manager \
#   --namespace cert-manager \
#   --create-namespace \
#   --version v1.6.1 \
#   --set installCRDs=true

# kubectl create ns linkerd

# kubectl create secret tls \
#     linkerd-trust-anchor \
#     --cert="${CERT_ROOT}"/ca.crt \
#     --key="${CERT_ROOT}"/ca.key \
#     --namespace=linkerd

# kubectl apply -f ./cert-manager.yml

helm install linkerd2 \
  --set-file identityTrustAnchorsPEM=${CERT_ROOT}/ca.crt \
  --set-file identity.issuer.tls.crtPEM=${CERT_ROOT}/issuer.crt \
  --set-file identity.issuer.tls.keyPEM=${CERT_ROOT}/issuer.key \
  --set identity.issuer.crtExpiry=$(date -d '+8760 hour' +"%Y-%m-%dT%H:%M:%SZ") \
  -f values-ha.yaml \
  -f https://raw.githubusercontent.com/linkerd/linkerd2/stable-2.11.1/charts/linkerd2/values-ha.yaml \
  linkerd/linkerd2 
