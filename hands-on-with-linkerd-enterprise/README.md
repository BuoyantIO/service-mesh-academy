# Hands on with Linkerd Enterprise

Welcome to hands on with Linkerd Enterprise. Follow along with the presenters by configuring your own cluster and deploying emojivoto across multiple azs. You can follow the trial guide here: https://docs.buoyant.io/buoyant-enterprise-linkerd/installation/trial/

## Getting Started

If you're following along and need a Kubernetes cluster with 3 azs use the following command to have k3d create a multi az cluster for you:

```bash
k3d cluster create -c cluster/hazl.yaml --wait
```

## Deploying Emojivoto

To deploy emojivoto in a multi az fashion use the included kustomization files to modify emojivoto:

```bash
kubectl apply -k emojivoto/
```
