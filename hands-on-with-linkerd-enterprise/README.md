<!--
SPDX-FileCopyrightText: 2024 Buoyant Inc.
SPDX-License-Identifier: Apache-2.0

SMA-Description: Exploring new features in Buoyant Enterprise for Linkerd
-->

# Hands on with BEL

Welcome to hands on with **Buoyant Enterprise for Linkerd**. Follow along with the presenters by configuring your own cluster and deploying emojivoto across multiple availability zones. You can follow the trial guide here: https://docs.buoyant.io/buoyant-enterprise-linkerd/installation/trial/

## Getting Started

If you're following along and need a Kubernetes cluster with 3 azs use the following command to have k3d create a multi az cluster for you:

```bash
k3d cluster create -c cluster/hazl.yaml --wait
```

### Preloaded Manifests

If you're following along with the workshop and you run into any issues creating certificates or loading them into you manifests you can use the manifests included in this repo. Please be aware these certificates should **ONLY** be used for a trial cluster.

### Pregenerated certs

If you'd like to skip the steps where you generate certificates you can use the certificates in the certs directory. Once again, these certs should be considered insecure and **ONLY** be used for a trial cluster.

## Deploying Emojivoto

To deploy emojivoto in a multi az fashion use the included kustomization files to modify emojivoto:

```bash
kubectl apply -k emojivoto/
```

## Deploying Colorz

```bash
kubectl apply -k colorz/
```
