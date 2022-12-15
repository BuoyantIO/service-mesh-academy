# `k3d` Setup for mTLS Workshop

This is the documentation - and executable code! - for creating a simple `k3d`
cluster for the Service Mesh Academy workshop on mTLS. The easiest way to use
this file is to execute it with [demosh].

Things in Markdown comments are safe to ignore when reading this later. When
executing this with [demosh], things after the horizontal rule below (which is
just before a commented `@SHOW` directive) will get displayed.

[demosh]: https://github.com/BuoyantIO/demosh

We'll do nothing at all if there's already an `mtls` cluster.

```bash
set -e
DEMOSH_QUIET_FAILURE=true

if kubectl --context mtls config get-contexts mtls >/dev/null 2>&1; then \
    echo "Cluster 'mtls' already exists" >&2 ;\
    exit 1 ;\
fi
```

<!-- @import demo-tools.sh -->
----
<!-- @SHOW -->

The mTLS workshop can use pretty much any kind of cluster, but using `k3d` for
it can be particularly convenient. Here, we'll set up the one cluster that we
need, but we won't install anything yet.

The only weird bit here is that we're deliberately not deploying `k3d`
`local-storage`, `metrics`, or Traefik -- we don't need them, and it's a
little easier on the host not to run them.

```bash
k3d cluster create mtls \
        --port "80:80@loadbalancer" \
        --port "443:443@loadbalancer" \
        --k3s-arg='--no-deploy=local-storage,metrics-server@server:*' \
        --k3s-arg '--no-deploy=traefik@server:*;agents:*' \
        --kubeconfig-update-default \
        --kubeconfig-switch-context=false
```

After that, rename the context so it doesn't start with `k3d-`...

```bash
kubectl config rename-context k3d-mtls mtls
```

...switch into it...

```bash
kubectx mtls
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

Done! The `mtls` cluster should be ready for the rest of the mTLS workshop.

<!-- @wait_clear -->
