# `k3d` Multicluster Setup

There are some gotchas when setting up `k3d` clusters to work with
multicluster Linkerd, so here's documentation - and executable code! - about
that. The easiest way to use this file is to execute it with [demosh].

Things in Markdown comments are safe to ignore when reading this later. When
executing this with [demosh], things after the horizontal rule below (which is
just before a commented `@SHOW` directive) will get displayed.

[demosh]: https://github.com/BuoyantIO/demosh

<!-- @import demo-tools.sh -->
<!-- @clear -->
----
<!-- @SHOW -->

Setting up `k3d` clusters to work with multicluster Linkerd can be a little
tricky. Here's what you need to know to get it to work:

1. You have to put all the clusters on the same Docker network, so that they
   have IP connectivity. (This is the `--network` argument.)

2. Each cluster has to get a separate API port (`--api-port`), since the API
   port has to appear in the *host's* port space.

3. It's helpful to give each of them their own cluster domain so that it's a
   little easier to keep track of which cluster is which. (This is the `k3s`
   `--cluster-domain` argument, so you'll see it included in a `--k3s-arg`
   below.)

<!-- @wait_clear -->

We'll set up two clusters, named `east` and `west`, all according to the rules
above. Note that we're also deliberately not deploying `k3d` `local-storage`,
`metrics`, or Traefik -- we don't need them, and it's a little easier on the
host not to run them.

```bash
#@immed
set -e

API_PORT=6440
HTTP_PORT=80
HTTPS_PORT=443
ORG_DOMAIN=k3d.example.com
CLUSTERS="east west"
```

These next three loops could (and arguably should) be combined into a single `for` loop, but it's tougher to read that way, so they're split out.

First, for each of our cluster names, if `k3d` doesn't already have a cluster
with that name, create it. The `k3d cluster create` command looks messy, but
the real magic is specifying the API port and network name. We also map ports
starting with 80 to the HTTP port of the ingress, and ports starting with 443
to the HTTPS port of the ingress.

```bash
for cluster in ${CLUSTERS} ; do \
    echo "Creating cluster $cluster..." ;\
    if k3d cluster get "$cluster" >/dev/null 2>&1; then \
        echo "Cluster $cluster already exists" >&2 ;\
    else \
        k3d cluster create "$cluster" \
            --api-port="$((API_PORT++))" \
            --network=multicluster-example \
            --port "$((HTTP_PORT++)):80@loadbalancer" \
            --port "$((HTTPS_PORT++)):443@loadbalancer" \
            --k3s-arg='--no-deploy=local-storage,metrics-server@server:*' \
            --k3s-arg '--no-deploy=traefik@server:*;agents:*' \
            --kubeconfig-update-default \
            --kubeconfig-switch-context=false ;\
    fi ;\
done
```

Once the clusters - and contexts - are created, rename the contexts so that
they don't have the leading `k3d-` prefix.

```bash
for ctx in east west; do \
    if kubectl config get-contexts k3d-$ctx >/dev/null 2>&1; then \
        echo "renaming k3d-$ctx to $ctx" ;\
        kubectl config delete-context $ctx >/dev/null 2>&1 || true ;\
        kubectl config rename-context k3d-$ctx $ctx ;\
    fi ;\
done
```

After that, wait until the clusters have some running pods...

```bash
for cluster in ${CLUSTERS} ; do \
    echo "  ...waiting for cluster $cluster to start..." ;\
    while true; do \
        count=$(kubectl --context="$cluster" get pods -n kube-system -l k8s-app=kube-dns -o json | jq '.items | length') ;\
        if [ $count -gt 0 ]; then break; fi ;\
    done ;\
done
```

...then loop a final time to wait for the `kube-dns` Pod to be ready. (This is
the reason that the previous loop is there: trying to wait for a Pod that
doesn't yet exist will throw an error.)

```bash
for cluster in ${CLUSTERS} ; do \
    echo "  ...waiting for cluster $cluster to be ready..." ;\
    kubectl --context="$cluster" wait pod --for=condition=ready \
            --namespace=kube-system --selector=k8s-app=kube-dns \
            --timeout=1m ;\
    \
    echo "  ...done" ;\
done
```

Done! Clusters `east` and `west` should be ready to work with multicluster
Linkerd.
