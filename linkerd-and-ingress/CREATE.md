# `k3d` Setup for Linkerd and Ingress Workshop

This is the documentation - and executable code! - for creating a simple `k3d`
cluster for the Service Mesh Academy workshop on Linkerd and ingress
controllers. The easiest way to use this file is to execute it with [demosh].

Things in Markdown comments are safe to ignore when reading this later. When
executing this with [demosh], things after the horizontal rule below (which is
just before a commented `@SHOW` directive) will get displayed.

[demosh]: https://github.com/BuoyantIO/demosh

We'll do nothing at all if there's already cluster named `ingress`.

```bash
set -e
DEMOSH_QUIET_FAILURE=true

if k3d cluster list ingress >/dev/null 2>&1; then \
    if ! kubectl --context ingress config get-contexts ingress >/dev/null 2>&1; then \
        k3d kubeconfig merge -d -s ingress >/dev/null 2>&1;\
    fi ;\
    exit 1 ;\
fi
set +e
```

----
<!-- @SHOW -->

The Linkerd and ingress workshop can use pretty much any kind of cluster, but
using `k3d` for it can be particularly convenient. Here, we'll set up the one
cluster that we need, but we won't install anything yet.

The only weird bits here are:

1. We're deliberately not deploying `k3d` `local-storage`, `metrics`, or
   Traefik -- we don't need them, and it's a little easier on the host not to
   run them.

2. We're mapping ports 80 and 443 through from the host network to the `k3d`
   cluster, to make it easier to access the `LoadBalancer` service we'll use.

```bash
k3d cluster create ingress \
    -p 80:80@loadbalancer \
    -p 443:443@loadbalancer \
    --k3s-arg '--disable=local-storage,traefik,metrics-server@server:0'
```

After that, rename the context so it doesn't start with `k3d-`...

```bash
kubectl config rename-context k3d-ingress ingress
```

...switch into it...

```bash
kubectl config use-context ingress
```

...and then wait until the cluster has some running pods. The `kubectl`
command in the loop will give `[]` when no pods exist, so any result with more
than 2 characters in it indicates that some pods exist. (This is obviously a
pretty basic check, but it's the way to do this without needing `jq` or the
like.)

```bash
while true; do \
    count=$(kubectl get pods -n kube-system -l k8s-app=kube-dns -o jsonpath='{ .items }' | wc -c) ;\
    if [ $count -gt 2 ]; then break; fi ;\
done
```

Finally, wait for the `kube-dns` Pod to be ready. (This is the reason that the
previous loop is there: trying to wait for a Pod that doesn't yet exist will
throw an error.)

```bash
kubectl wait pod --for=condition=ready \
        --namespace=kube-system --selector=k8s-app=kube-dns \
        --timeout=1m
```

Done! The `ingress` cluster should be ready for the rest of the workshop.

<!-- @wait_clear -->
