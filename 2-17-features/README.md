<!--
SPDX-FileCopyrightText: 2024 Buoyant Inc.
SPDX-License-Identifier: Apache-2.0

SMA-Description: Exploring Linkerd 2.17 federated Services and egress
-->

# Linkerd 2.17 Features: Federated Services and Egress

This is the documentation - and executable code! - for the Service Mesh
Academy workshop about new features in Linkerd 2.17. The easiest way to use
this file is to execute it with [demosh].

Things in Markdown comments are safe to ignore when reading this later. When
executing this with [demosh], things after the horizontal rule below (which
is just before a commented `@SHOW` directive) will get displayed.

[demosh]: https://github.com/BuoyantIO/demosh

The setup for this SMA is a bit more complex than usual: `init.sh` will get
everything set up. It requires you to have Linkerd 2.17 installed (or Linkerd
edge-24.11.8) and it requires ctlptl to create its four clusters.

As written, it also relies on OrbStack's automatic DNS. If you're not using
OrbStack, you'll need to adjust the `init.sh` script to arrange for the
`k3d-face` cluster to be able to resolve the DNS name `color` to the IP
address of the external `color` container.

<!-- set -e >

<!-- @start_livecast -->

```bash
BAT_STYLE="grid,numbers"
WORKLOAD_IMAGE_TAG=1.4.1
```

---
<!-- @SHOW -->

# Linkerd 2.17 Features: Federated Services and Egress

In this workshop, we'll explore two of the biggest new features in Linkerd
2.17: federated Services and egress!

Since the setup here is complex, we're starting out with all four of the
clusters we need already running. Here's the current setup:

- Cluster `k3d-face` is running the Faces GUI and the `face` workload
- Clusters `kind-smiley-1`, `kind-smiley-2`, and `kind-smiley-3` are running
  the `smiley` workload
- The `color` workload isn't running anywhere yet.

```bash
kubectl --context k3d-face get pods,svc -n faces
kubectl --context kind-smiley-1 get pods,svc -n faces
kubectl --context kind-smiley-2 get pods,svc -n faces
kubectl --context kind-smiley-3 get pods,svc -n faces
```

Additionally, the `face` workload is going to try to talk to
`smiley-federated` instead of `smiley` to get smilies. Note that that Service
doesn't exist yet!

Since we have no working `smiley` or `color` workload yet, if we flip to the
browser right now, we won't see good things happening.

<!-- @browser_then_terminal -->

## Setting Up Federated Services

Let's start by setting up `smiley` as a federated Service spanning all three
of our Kind clusters. We'll start by installing Linkerd multicluster
everywhere.

```bash
linkerd --context=k3d-face multicluster install --gateway=false \
  | kubectl --context=k3d-face apply -f -
linkerd --context=kind-smiley-1 multicluster install --gateway=false \
  | kubectl --context=kind-smiley-1 apply -f -
linkerd --context=kind-smiley-2 multicluster install --gateway=false \
  | kubectl --context=kind-smiley-2 apply -f -
linkerd --context=kind-smiley-3 multicluster install --gateway=false \
  | kubectl --context=kind-smiley-3 apply -f -

linkerd --context=k3d-face multicluster check
linkerd --context=kind-smiley-1 multicluster check
linkerd --context=kind-smiley-2 multicluster check
linkerd --context=kind-smiley-3 multicluster check
```

After that, we need to link clusters. We only need to link from `k3d-face` to the
three `smiley` clusters, not the other way around.

```bash
linkerd multicluster --context=kind-smiley-1 link \
    --gateway=false \
    --cluster-name=smiley-1 \
    | kubectl --context k3d-face apply -f -

linkerd multicluster --context=kind-smiley-2 link \
    --gateway=false \
    --cluster-name=smiley-2 \
    | kubectl --context k3d-face apply -f -

linkerd multicluster --context=kind-smiley-3 link \
    --gateway=false \
    --cluster-name=smiley-3 \
    | kubectl --context k3d-face apply -f -
```

Let's make sure that the links are up.

```bash
linkerd --context=k3d-face multicluster check
```

<!-- @wait_clear -->

## Mirroring Services

Once our links are up, we can mark the `smiley` service in each of the
`smiley` clusters for federation! This will make it so that `smiley-federated`
appears in the `k3d-face` cluster as the union of all the `smiley` services in
the other clusters.

```bash
kubectl --context kind-smiley-1 -n faces label svc/smiley \
        mirror.linkerd.io/federated=member
kubectl --context kind-smiley-2 -n faces label svc/smiley \
        mirror.linkerd.io/federated=member
kubectl --context kind-smiley-3 -n faces label svc/smiley \
        mirror.linkerd.io/federated=member
```

At this point, we should see `smiley-federated` in the `k3d-face` cluster...

```bash
kubectl --context k3d-face -n faces get svc smiley-federated
```

...and we can see that it's routing to the `smiley` services in the other
clusters.

```bash
linkerd --context k3d-face diagnostics endpoints \
    smiley-federated.faces.svc.cluster.local:80
```

If we flip to the browser now, we should see smiley faces!

<!-- @browser_then_terminal -->

Of course, it's hard to be sure that `smiley-federated` is really spreading
requests across all three `smiley` clusters... but we can change the smiley
being returned in each cluster to make that obvious.

<!-- @show_5 -->

```bash
kubectl --context kind-smiley-2 -n faces \
    set env deployment/smiley SMILEY=HeartEyes
kubectl --context kind-smiley-3 -n faces \
    set env deployment/smiley SMILEY=RollingEyes
```

And now we see a mix of smileys, depending on which
cluster actually serves the request.

<!-- @wait_clear -->

## Federated Services in Action

One of the fascinating things about federated Services is that they act like
Services, even though their endpoints happen to be in different clusters. So,
for example, if some of the endpoints go away, things... just keep working.

```bash
kubectl --context kind-smiley-1 -n faces \
    scale deployment/smiley --replicas=0
```

A quick look under the hood shows that the endpoint in
the `kind-smiley-1` cluster has in fact vanished from
the `smiley-federated` Service.

```bash
linkerd --context k3d-face diagnostics endpoints \
    smiley-federated.faces.svc.cluster.local:80
```

If that endpoint comes back, it will automatically reappear
in the `smiley-federated` Service -- and, of course, multiple
endpoints will work, too.

```bash
kubectl --context kind-smiley-1 -n faces \
    scale deployment/smiley --replicas=2

linkerd --context k3d-face diagnostics endpoints \
    smiley-federated.faces.svc.cluster.local:80
```

<!-- @wait_clear -->

## Federated Services in Action

Of course, unhappy workloads won't always be so polite as to simply vanish
entirely. Suppose our various workloads just become unreliable?

```bash
kubectl --context kind-smiley-1 -n faces \
    set env deployment/smiley ERROR_FRACTION=30
kubectl --context kind-smiley-2 -n faces \
    set env deployment/smiley ERROR_FRACTION=30
kubectl --context kind-smiley-3 -n faces \
    set env deployment/smiley ERROR_FRACTION=30
```

If we wait a moment, we'll start to see cursing faces in
our GUI. We can get a sense of how bad things are with
`linkerd viz stat-outbound`.

```bash
watch linkerd --context k3d-face viz stat-outbound -n faces deploy/face
```

The natural way to want to manage this with Linkerd is with
retries! and, in fact, since `smiley-federated` is a Service,
we can just annotate it to get Linkerd to retry failures _no
matter which cluster the failing endpoint lives in_.

```bash
kubectl --context k3d-face annotate -n faces \
    service smiley-federated \
        retry.linkerd.io/http=5xx \
        retry.linkerd.io/limit=3

watch linkerd --context k3d-face viz stat-outbound -n faces deploy/face
```

<!-- @clear -->

## Federated Services and Auth

One thing to remember about federated Services is that even though they act
like Services, you really do have to remember that they're in different
clusters when it comes to authorization (at least, for the moment). So, for
example, here's a policy that will deny traffic to the `smiley`
workload unless it comes from the `face` ServiceAccount in the
`faces` namespace:

```bash
bat k8s/smiley-sa.yaml k8s/smiley-auth.yaml
```

Right now, the `face` workload is using the `default`
ServiceAccount:

```bash
linkerd identity --context k3d-face -n faces -l service=face \
    | grep CN
```

So, if we apply the policy, we should no longer be able to
fetch smilies!

```bash
kubectl --context k3d-face apply -f k8s/smiley-sa.yaml
kubectl --context k3d-face apply -f k8s/smiley-auth.yaml
```

<!-- @wait_clear -->

## Federated Services and Auth

As you can see, it doesn't actually do anything. This is because auth
decisions happen at the _inbound_ proxy, and the inbound proxies for the
`smiley` workloads aren't in the `k3d-face` cluster! So we need to put the
auth in the clusters where the workloads are.

```bash
kubectl --context k3d-face delete -f k8s/smiley-auth.yaml
kubectl --context kind-smiley-1 apply -f k8s/smiley-auth.yaml
kubectl --context kind-smiley-2 apply -f k8s/smiley-auth.yaml
kubectl --context kind-smiley-2 apply -f k8s/smiley-auth.yaml
```

Now we get all the cursing faces we could ask for... and if we
edit the `face` deployment to use the correct ServiceAccount,
everything starts working again.

```bash
kubectl --context k3d-face -n faces \
    set serviceaccount deployment/face face
```

And now we're back to seeing smilies as we should!

<!-- @wait -->

One note: _we didn't create the ServiceAccount_ in the
`smiley` clusters. With Linkerd multicluster, we don't need
to: we can rely on the mesh to keep any clients honest about
their identity, so all we need is the name.

<!-- @wait_clear -->

## Bringing in Color

Now that we have `smiley` federated, let's bring in the `color` workload...
which isn't going to be running in Kubernetes at all.

```bash
docker run --network egress --detach --rm --name color \
       -e FACES_SERVICE=color \
       -e USER_HEADER_NAME=X-Faces-User \
       ghcr.io/buoyantio/faces-color:2.0.0-rc.2
```

(We're relying on OrbStack here to arrange for the DNS to resolve
`color` to the right IP address: if you're not using OrbStack, you
might need to fix this on your own.)

We can see that we now have blue backgrounds in the GUI!

<!-- @wait_clear -->
<!-- @show_terminal -->

## Monitoring Egress Traffic

At this point, since `color` is running outside of Kubernetes, we have egress
traffic happening! but we don't have a lot of visibility into it yet.

```bash
linkerd --context k3d-face diagnostics proxy-metrics -n faces deploy/face \
    | grep _route_request_statuses_total \
    | grep egress
```

That's a mess. We can make it slightly easier to read by putting in newlines
at strategic points.

```bash
linkerd --context k3d-face diagnostics proxy-metrics -n faces deploy/face \
    | grep _route_request_statuses_total \
    | grep egress \
    | sed -e 's/\([,{}]\)/\1\n/g'
```

All that really shows us, though, is that some egress is happening with a
hostname of `color` using `egress-fallback`. And it says it's HTTP, even
though we know that `color` traffic is really gRPC.

<!-- @wait_clear -->

## Monitoring Egress Traffic

To get a better handle on what's happening, we can set up an EgressNetwork
policy that allows all egress traffic. This won't stop anything from
happening, but it will let us see more about what's going on.

```bash
bat k8s/allow-all-egress.yaml
kubectl --context k3d-face apply -f k8s/allow-all-egress.yaml
```

Now there's a new entry in the metrics output!

```bash
linkerd --context k3d-face diagnostics proxy-metrics -n faces deploy/face \
    | grep _route_request_statuses_total \
    | grep egress \
    | sed -e 's/\([,{}]\)/\1\n/g'
```

We can see that it's using the `all-egress` EgressNetwork, that it's on port
8000, that the hostname is `color`... and if we run that again, we'll see that
the count for the `all-egress` entry is climbing, while the `egress-fallback`
entry is not.

```bash
linkerd --context k3d-face diagnostics proxy-metrics -n faces deploy/face \
    | grep _route_request_statuses_total \
    | grep egress \
    | sed -e 's/\([,{}]\)/\1\n/g'
```

But really, this is past the point of ugliness, so we'll bring in a Python
script to break this down for us. (We could also build a Grafana dashboard,
but this is a little more immediate here.)

<!-- @wait_clear -->
<!-- @show_5 -->

# Breaking Color

Next up: let's exercise some control, and deny all the egress traffic.

```bash
bat k8s/deny-all-egress.yaml
kubectl --context k3d-face apply -f k8s/deny-all-egress.yaml
```

Instantly we see grey backgrounds, and we also see a `color 403`
line in our metrics output. All the egress traffic is being
blocked with a permissions error.

<!-- @wait_clear -->

# Re-allowing Color

To re-allow `color` traffic, we need to apply a GRPCRoute with a `parentRef`
of our EgressNetwork. Here's the simplest way to do that:

```bash
bat k8s/allow-color-all.yaml
kubectl --context k3d-face apply -f k8s/allow-color-all.yaml
```

Now we're back to blue backgrounds! and if we wait a bit,
we'll see our metrics catch up.

<!-- @wait_clear -->

# Selective Egress

Of course, blanket egress isn't really all that interesting. Using HTTPRoutes
as the way to talk about traffic we'll allow lets us get much more specific.

For example, the Faces demo actually uses two different gRPC
services when fetching cells: both use the `ColorService`
provider, but cells in the center use the `Center` method,
while cells on the edges use the `Edge` method. We can use this
to block access only for the center cells:

```bash
bat k8s/allow-edge.yaml
kubectl --context k3d-face apply -f k8s/allow-edge.yaml
```

Now we'll see grey cells in the center, but blue cells on the
edges. And we'll see some `PERMISSION_DENIED` errors in our
metrics as well!

<!-- @wait_clear -->

# Selective Egress, Round 2

Suppose we want to get fancier than that, and allow the center cells for some
users but not others? We can do that, too: if we supply a user name in the
`User` field in the GUI, our requests will carry an `X-Faces-User` header with
the name we supply. (In the real world, obviously we'd have
authentication for this as well! but we're not going to bother
for this demo.)

Let's allow center-cell access only for the user `Center`:

```bash
bat k8s/allow-edge-2.yaml
kubectl --context k3d-face apply -f k8s/allow-edge-2.yaml
```

If we flip back to the browser and then log in as `Center`,
we'll see blue cells in the center, but for any other user,
they'll still be grey.

<!-- @browser_then_terminal -->

## Wrapping Up

So there you have it: a whirlwind tour of Linkerd 2.17 federated Services and
egress! Obviously there's a _lot_ more to Linkerd 2.17 than this -- we've
barely scratched the surface. We look forward to seeing what you come up with!

<!-- @wait -->

Finally, feedback is always welcome! You can reach me at flynn@buoyant.io or
as @flynn on the Linkerd Slack (https://slack.linkerd.io).

<!-- @wait -->
<!-- @show_slides -->
