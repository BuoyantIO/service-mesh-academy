<!--
SPDX-FileCopyrightText: 2024 Buoyant Inc.
SPDX-License-Identifier: Apache-2.0

SMA-Description: Multicluster failover with Linkerd and the linkerd-failover extension
-->

# Multicluster Failover With Linkerd

This is the documentation - and executable code! - for the Service Mesh
Academy Multicluster Failover workshop. The easiest way to use this file is to
execute it with [demosh], but you can certainly just read it.

Things in Markdown comments are safe to ignore when reading this later. When
executing this with [demosh], things after the horizontal rule below (which is
just before a commented `@SHOW` directive) will get displayed.

[demosh]: https://github.com/BuoyantIO/demosh

This workshop requires that you have two Kubernetes clusters, named `east` and
`west`. If you want to create `k3d` clusters for this, [CREATE.md](CREATE.md)
has what you need! Otherwise, make sure your clusters are called `east` and
`west`; if your clusters have other names, remember to substitute the same
cluster for `east` or `west` every time those names appear in these
instructions (or you can use `kubectl config rename-context` to rename your
clusters' contexts to match).

In addition, you will need following CLIs installed locally:

- [smallstep](https://smallstep.com/docs/step-cli/installation)
- [kubectl](https://kubernetes.io/docs/tasks/tools/#kubectl)
- [the latest version of Linkerd](https://linkerd.io/2.11/getting-started/#step-1-install-the-cli)

<!-- @import demo-tools.sh -->
<!-- @import check-requirements.sh -->
<!-- @start_livecast -->
---
<!-- @SHOW -->

We're going to walk through configuring Linkerd in a multicluster
configuration multicluster configuration with the linkerd-failover extension.
Once this architecture is in place, you will be able to use mirrored services
as failover services for your application traffic.

**NOTE**: This is a long README! We're actually going through _everything_
starting from two empty clusters. It works out, though, just stick with it.

# Initial Cluster Setup

We'll start with setting up our two brand-new `k3d` clusters. All of this part
should work fine with other cluster types, too.

## 1. Verify cluster access

For this workshop, we'll be using clusters called `east` and `west`, so we'll
start by making sure that we have access to both clusters.

```bash
kubectl get pods -n kube-system --context east
kubectl get pods -n kube-system --context west
```

## 2. Verify cluster support for Linkerd

Next up, make sure that we'll be able to deploy Linkerd on both clusters.

```bash
linkerd check --pre --context east
linkerd check --pre --context west
```

<!-- @wait_clear -->
## 3. Set up certificates

For multicluster to work properly, both clusters need to be using the same
trust anchor. We'll set all this up with `smallstep`.

<!-- @HIDE -->

For more details here, you can check out the Service Mesh Academy [Certificate Management] workshop.

[Certificate Management]: https://github.com/BuoyantIO/service-mesh-academy/tree/main/l5d-certificate-management

<!-- @SHOW -->

### Common trust root

Start by setting up the _trust anchor_, which will be shared between the two
clusters. The `smallstep` `root-ca` profile is appropriate for this: it will
create a CA certificate with an X.509 path length of 1, so it will be able to
sign the issuer certificates that we'll need.

Arguments to `step` we use here:

- `root.linkerd.cluster.local` is the CN of the trust anchor. This name is
  _required_.
- `root.crt` and `root.key` give the filenames into which `step` will write
  the certificate files.
- `--profile root-ca` specifies the profile, as described above.
- `--no-password --insecure` says we don't want a password, which we accept is
  insecure.

```bash
#@immed
rm -f root.crt root.key

step certificate create \
  root.linkerd.cluster.local \
  root.crt root.key \
  --profile root-ca \
  --no-password --insecure
```

<!-- @wait_clear -->

### Issuer certificates for each cluster

Given the trust anchor, we can create the issuer certificates for each
cluster. These can - and should! - be different, so we'll run `step` twice.
Although the parameters are identical (except for the filenames), these
certificates will not be the same, since their private keys will be different.

Note that we're using the `smallstep` `intermediate-ca` profile here: still a
CA certificate, but the X.509 path length will be 0, meaning that these
certificates can only be used to sign workload certificates.

New `step` arguments:

- `identity.linkerd.cluster.local` is the name required for issuer
  certificates.
- `--profile intermediate-ca` sets the profile, as described above.
- `--ca root.crt` gives the public key certificate to use to sign the new cert
- `--ca-key root.key` gives the private key for the `--ca` certificate
- `--not-after 8760h` specifies that we want a one-year expiry for this
  certificate. (It's unfortunate that we have to use hours for this.)

```bash
#@immed
rm -f east-issuer.crt east-issuer.key west-issuer.crt west-issuer.key

step certificate create \
  identity.linkerd.cluster.local \
  east-issuer.crt east-issuer.key \
  --profile intermediate-ca \
  --ca root.crt \
  --ca-key root.key \
  --not-after 8760h \
  --no-password --insecure

step certificate create \
  identity.linkerd.cluster.local \
  west-issuer.crt west-issuer.key \
  --profile intermediate-ca \
  --ca root.crt \
  --ca-key root.key \
  --not-after 8760h \
  --no-password --insecure
```

<!-- @wait_clear -->

## 4. Install Linkerd

Finally we're ready to install Linkerd! We'll use the command line for this.
There's nothing terribly magical here _except_ that it's critical that we give
each cluster the correct certificates.

### East cluster

```bash
linkerd install --crds --context east | kubectl apply --context east -f -

linkerd install --context east \
  --identity-trust-anchors-file root.crt \
  --identity-issuer-certificate-file east-issuer.crt \
  --identity-issuer-key-file east-issuer.key | \
  kubectl apply --context east -f -
```

### West cluster

```bash
linkerd install --crds --context west | kubectl apply --context west -f -

linkerd install --context west \
  --identity-trust-anchors-file root.crt \
  --identity-issuer-certificate-file west-issuer.crt \
  --identity-issuer-key-file west-issuer.key | \
  kubectl apply --context west -f -
```

<!-- @wait_clear -->

## 6. Make sure Linkerd is happy

We'll run `linkerd check` on both clusters to make sure that all is well.

```bash
linkerd --context east check
linkerd --context west check
```

<!-- @wait_clear -->

## 5. Install `linkerd-viz`

The `linkerd-viz` extension provides tools to more easily visualize what's
going on in our clusters. Let's get that installed too. Note that this is
completely identical between the two clusters.

<!-- @HIDE -->

For more details about `linkerd-viz`, check out its documentation at
https://linkerd.io/2.12/features/dashboard/.

<!-- @SHOW -->

We start by installing Grafana.

```bash
#@immed
GRAFANA_VALUES_URL=https://raw.githubusercontent.com/linkerd/linkerd2/main/grafana/values.yaml

helm repo add grafana https://grafana.github.io/helm-charts

helm install --kube-context east \
  grafana -n grafana --create-namespace grafana/grafana \
  -f ${GRAFANA_VALUES_URL} \
  --wait

helm install --kube-context west \
  grafana -n grafana --create-namespace grafana/grafana \
  -f ${GRAFANA_VALUES_URL} \
  --wait
```

Once that's done, we can install `linkerd-viz` itself.

```bash
linkerd --context=east viz install --set grafana.url=grafana.grafana:3000 \
  | kubectl --context=east apply -f -
linkerd --context=west viz install --set grafana.url=grafana.grafana:3000 \
  | kubectl --context=west apply -f -
```

Finally, check to make sure everything is still OK.

```bash
linkerd check --context east
linkerd check --context west
```

<!-- @wait_clear -->

## 6. Install an ingress controller

We're going to use Emissary-ingress here, but the actual choice of ingress
controller isn't important -- in fact, the real reason we're installing an
ingress controller is just to avoid needing `kubectl port-forward` while using
the browser to check things out.

```bash
#@immed
EMISSARY_CRDS=https://app.getambassador.io/yaml/emissary/3.2.0/emissary-crds.yaml
#@immed
EMISSARY_INGRESS=https://app.getambassador.io/yaml/emissary/3.2.0/emissary-emissaryns.yaml

for ctx in east west; do \
  echo "Installing Emissary-ingress in $ctx..." ;\
  kubectl --context $ctx create namespace emissary ;\
  \
  curl --proto '=https' --tlsv1.2 -sSfL ${EMISSARY_CRDS} | \
    sed -e 's/replicas: 3/replicas: 1/' | \
    kubectl apply --context $ctx -f - ;\
  \
  echo "" ;\
  echo "  waiting for webhooks in $ctx..." ;\
  kubectl --context $ctx wait --timeout=90s --for=condition=available \
     -n emissary-system deployment emissary-apiext ;\
  \
  curl --proto '=https' --tlsv1.2 -sSfL ${EMISSARY_INGRESS} | \
      sed -e 's/replicas: 3/replicas: 1/' | \
      linkerd inject --context $ctx - | \
      kubectl apply --context $ctx -f - ;\
done

for ctx in east west; do \
  echo "" ;\
  echo "  waiting for Emissary to be ready in $ctx..." ;\
  kubectl --context east wait --for condition=available --timeout=90s \
      -n emissary deployment -lproduct=aes ;\
  echo "" ;\
  echo "  all ready in $ctx..." ;\
done
```

## 7. Install our demo application

For our demo application, we're going to use `emojivoto`. Again, we'll set
this up in both clusters.

```bash
for ctx in east west; do \
  echo "Installing emojivoto in $ctx..." ;\
  curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/emojivoto.yml \
      | linkerd inject --context $ctx - \
      | kubectl apply --context $ctx -f - ;\
  \
  echo "" ;\
  echo "  waiting for emojivoto to be ready in $ctx..." ;\
  kubectl --context east wait --for condition=available --timeout=90s \
      -n emojivoto deployment -lapp.kubernetes.io/name=emoji ;\
  echo "" ;\
  echo "  all ready in $ctx..." ;\
done
```

## 8. Configure access via the ingress controller.

Finally, we'll set up Emissary-ingress so that we can talk to our
applications. We'll mimic the real world here, and have separate configuration
resources for each cluster.

(If you actually look into these resources, they'll look a little odd because
we're using `k3d` here, which causes both ingress controllers to appear on the
same host IP address and forces us to differentiate them by port number. In
the real world, they'd have actual different hostnames, and likely not use the
port number.)

```bash
kubectl --context east apply -f emissary-yaml-east
kubectl --context west apply -f emissary-yaml-west
```

## 9. Test!!

At this point, we should be able to use both the `east` and `west` emojivoto
applications from the browser, and we should be able to use `linkerd viz` to
study them in both clusters, too.

<!-- @browser_then_terminal -->

# Setting up Failover and Multicluster

Now that our clusters are working independently, it's time to set things so
that we can use them together.

## 1. `linkerd-smi` and `linkerd-failover`

For failover, we need the `linkerd-smi` extension and the `linkerd-failover`
extension: `linkerd-failover` actually relies on `linkerd-smi` for the heavy
lifting of traffic splitting.

Since `linkerd-smi` is actually built in to the standard Linkerd distribution,
we'll use the `linkerd` CLI to install it:

```bash
for ctx in east west; do \
    echo "" ;\
    echo "Installing linkerd-smi on cluster ${ctx}" ;\
    linkerd smi --context="$ctx" install | \
        kubectl --context="$ctx" apply -f - ;\
done
```

`linkerd-failover`, though, is a completely separate thing, so we'll use
`Helm` to install that:

```bash
for ctx in east west; do \
    echo "" ;\
    echo "Installing linkerd-failover on cluster ${ctx}" ;\
    \
    helm install --kube-context $ctx \
         -n linkerd-failover --create-namespace \
         linkerd-failover linkerd/linkerd-failover \
         --wait ;\
done
```

Once those are ready, we can make sure all's well again.

```bash
linkerd --context east check
linkerd --context west check
```

<!-- @wait_clear -->

## 2. `linkerd-multicluster`

After getting `linkerd-smi` and `linkerd-failover` set up, we'll install the
`linkerd-multicluster` extension. This is another builtin, so we'll use the
`linkerd` CLI for this.

```bash
for ctx in east west ; do \
    echo "" ;\
    echo "Installing linkerd-multicluster on cluster ${ctx}" ;\
    kubectl --context="$ctx" create ns linkerd-multicluster ;\
    kubectl --context="$ctx" annotate ns/linkerd-multicluster \
        config.linkerd.io/proxy-log-level='linkerd=info,warn' ;\
    sleep 2 ;\
    \
    linkerd --context="$ctx" multicluster install | \
        kubectl --context="$ctx" apply -f - ;\
done
```

## 3. Test again!

Finally, once again, we'll check that all is well:

```bash
linkerd --context east check
linkerd --context west check
```

Everything should still be working from the browser as two independent
clusters, too: we've installed the extensions but not linked everything
together at this point.

<!-- @browser_then_terminal -->

# Linking Clusters

OK -- let's link our clusters together, bidirectionally, so that we can
shuffle traffic from cluster to cluster.

## 1. Where's the APIServer?

`k3d` makes things a bit weird at this point.

Our two clusters are attached to the same host network, which means that their
APIservers actually have the same IP address, which the host running `k3d`
sees as `localhost`. This makes the multicluster link tricky, since it will
try to read credentials for the Kubernetes cluster we're linking to... but it
will do that from the `linkerd` CLI running on the host, so it will see
`localhost` instead of an IP address that'll actually work from the other
`k3d` cluster.

<!-- @wait_clear -->

So we're going to cheat a bit. This `apiserveraddr` function first checks
`kubectl cluster-info` to figure out if it sees a `localhost` address, and, if
so, it instead uses the load balancer address of the `emissary-ingress`
service to find the right IP address. (Emissary-ingress doesn't have to route
APIserver traffic -- this is just a simple way to find the `k3d` APIserver's
IP address.)

```bash
apiserveraddr () {
  cluster="$1"

  # Is this localhost?
  url=$(env TERM=dumb kubectl --context="$cluster" cluster-info \
                      | grep 'control plane' \
                      | sed -e 's/^.*https:/https:/')

  is_local=$(echo "$url" | fgrep -c '//0.0.0.0:')

  if [ -n "$url" -a \( $is_local -eq 0 \) ]; then
    # This should be fine.
    echo "$url"
  else
    # Use the emissary-ingress service to find the APIserver's IP.
    lb_ip=$(kubectl --context="$cluster" get svc -n emissary emissary-ingress \
                    -o 'go-template={{ (index .status.loadBalancer.ingress 0).ip }}')

    echo "https://${lb_ip}:6443"
  fi
}
```

<!-- @clear -->

## 2. Link the cluster

Now that we have a way to get the APIserver address, we can use it to link
clusters.

**NOTE:** The `linkerd multicluster link` command and the `kubectl apply`
command use **different contexts** here. This is intentional: we get the
credentials from the `east` cluster and use that to define a `link` object
using information in the `east` cluster, but then we need to actually apply
that `link` object into the `west` cluster. And vice versa, of course.

```bash
#@immed
echo ""
#@immed
echo "east APIserver is at $(apiserveraddr east)"
#@immed
echo "west APIserver is at $(apiserveraddr west)"

# First, link east to west...
linkerd multicluster --context=west link \
    --cluster-name=west \
    --api-server-address="$(apiserveraddr west)" \
    | kubectl --context east apply -f -

# ...then link west to east.
linkerd multicluster --context=east link \
    --cluster-name=east \
    --api-server-address="$(apiserveraddr east)" \
    | kubectl --context west apply -f -
```

<!-- @wait_clear -->

## 3. Export services

At this point our clusters are linked, meaning that they're ready to mirror
services – but they'll only mirror services that have been explicitly
exported. We'll export the `emoji-svc` service in each of our clusters.

```bash
kubectl --context=east -n emojivoto label svc/emoji-svc \
    mirror.linkerd.io/exported=true

kubectl --context=west -n emojivoto label svc/emoji-svc \
    mirror.linkerd.io/exported=true
```

We should now see mirrored services in both clusters, still in the `emojivoto`
namespace, but named `emoji-svc-$othercluster`:

```bash
kubectl --context east get svc -n emojivoto
kubectl --context west get svc -n emojivoto
```

<!-- @SHOW -->

## 4. Test again!

At this point, everything should still be working from the browser. The
mirrored services are in the clusters, but they're not taking any traffic yet.
We can see this using `linkerd viz stat`:

```bash
linkerd --context=east viz stat -n emojivoto svc

linkerd --context=west viz stat -n emojivoto svc
```

And, of course, we can see it in the browser too.

<!-- @browser_then_terminal -->

# Failing Over

There's one last step before we can try a failover: we need to set up a
`TrafficSplit` resource, because the `linkerd-failover` extension actually
uses the `linkerd-smi` extension for its heavy lifting.

What happens here is that all `linkerd-failover` does is modify the weight in
a `TrafficSplit`; it trusts `linkerd-smi` to actually reroute the traffic. In
turn, for our use case here, `linkerd-smi` is effectively trusting
`linkerd-multicluster` to bridge from one cluster to another.

<!-- @wait -->

## 1. Install the `TrafficSplit`

So. We start by installing a `TrafficSplit` that can switch traffic between
`emoji-svc` and `emoji-svc-west`.

Here's what the `TrafficSplit` looks like. Pay careful attention to the
weights, and also to the labels and annotations:

- The `failover.linkerd.io/controlled-by: linkerd-failover` label is what
  tells `linkerd-failover` that's it OK to for it to change this
  `TrafficSplit`.
- The `failover.linkerd.io/primary-service: emoji-svc` annotation is what
  tells `linkerd-failover` which service it should prefer, if nothing is going
  wrong.

<!-- @wait -->

```bash
more failover-config/emoji-split-east.yaml
```

<!-- @wait_clear -->

Let's go ahead and apply that.

```bash
kubectl --context east apply -f failover-config/emoji-split-east.yaml
```

This shouldn't affect anything in our application at all, so let's go check
that out. We can see that we're still using the primary service using `linkerd
viz stat`:

```bash
watch linkerd --context=east viz stat -n emojivoto svc
```

And, again, we can check it in the browser.

<!-- @browser_then_terminal -->

## 2. Fail a service!

We can test failover by simply scaling `east`'s `emoji` deployment to zero
replicas:

```bash
kubectl --context east scale -n emojivoto deploy emoji --replicas=0
```

At this point, we should see the `TrafficSplit` weights flip:

```bash
kubectl --context east get ts -o yaml -n emojivoto
```

## 3. Test again!

Everything should **still** be working fine from the browser!

<!-- @browser_then_terminal -->

We can see that we're now using the `west` service using `linkerd viz stat`:

```bash
watch linkerd --context=east viz stat -n emojivoto svc
```

<!-- @wait_clear -->

# Summary

This is a rather exhaustive view into how to set up a pair of clusters for
multicluster failover with Linkerd – and it barely scratches the surface. In
particular, the layered approach where

- `linkerd-multicluster` handles communications and service mirroring between
  clusters;
- `linkerd-smi` handles traffic splitting for a single service; and
- `linkerd-failover` just modifies the traffic split rules

means that you have enormous flexibility in constructing custom failover logic
and more complex splits. As always, you can find us at `slack.linkerd.io` for
more!

<!-- @wait -->