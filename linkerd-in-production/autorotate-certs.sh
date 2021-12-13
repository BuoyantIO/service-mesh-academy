#!/bin/bash

set -eu

CERT_ROOT="${CERT_DIR:-.}"

kubectl create secret tls \
    linkerd-trust-anchor \
    --cert="${CERT_ROOT}"/ca.crt \
    --key="${CERT_ROOT}"/ca.key \
    --namespace=linkerd