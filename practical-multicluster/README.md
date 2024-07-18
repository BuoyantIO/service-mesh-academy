<!--
SPDX-FileCopyrightText: 2024 Buoyant Inc.
SPDX-License-Identifier: Apache-2.0

SMA-Description: Using Linkerd in IPv6 and dualstack Kubernetes clusters
-->

# Linkerd and IPv6

This is the documentation - and executable code! - for the Service Mesh
Academy workshop about Linkerd and IPv6. The easiest way to use this file is
to execute it with [demosh].

Things in Markdown comments are safe to ignore when reading this later. When
executing this with [demosh], things after the horizontal rule below (which
is just before a commented `@SHOW` directive) will get displayed.

[demosh]: https://github.com/BuoyantIO/demosh

This workshop requires kind _and_ k3d, and assumes that you can run a lot of
clusters at once.

<!-- @import demosh/check-requirements.sh -->
<!-- @start_livecast -->
---
<!-- @SHOW -->

# Practical Multicluster with Linkerd

We talk a lot about multicluster as a performance or availability tool, but
today we're going to show it off more as a tool for managing development,
using entire clusters for progressive delivery, etc.

This demo runs using both kind and k3d - at the same time - to dynamically
create and delete clusters. Basically, we're using kind as one cloud provider
and k3d as a different cloud provider. We'll use Buoyant Enterprise for
Linkerd to tie everything together, and we'll use a new tool called
`localcluster` to spin clusters up and down and handle routing, etc.

<!-- @wait_clear -->

## CAVEATS

**This demo will not work with Docker Desktop for Mac.** Sorry about that, but
unfortunately Docker Desktop doesn't meaningfully bridge the Docker network to
the host network. If you're on a Mac, try Orbstack instead (www.orbstack.dev).

Also, **we're only showing IPv4 at the moment**. Everything _should_ work with
IPv6 or dualstack, but that's for a later version!

<!-- @wait -->

Finally, we're not _really_ going to show a proper global high-availability
ingress in this demo, since this is _Service Mesh_ Academy, not _Ingress_
Academy. We're going to use a cluster called 'cdn' to kind of fake having a
CDN in front of everything handling proper ingress.

And with all that said, let's get started!

<!-- @wait_clear -->

## Starting Out: CDN + a single cluster

As a starting point, we've set up our `cdn` cluster and a single `faces`
cluster running in kind. (We also have clusters called `color` and `color-b`
which we're not using yet.)

```bash
kind get clusters
```

In the `faces` cluster, we have Faces running with a LoadBalancer service for
its GUI. As usual, this is really not the right way to run Faces, it's just
the simplest setup for this demo!

```bash
kubectl --context faces get svc -n faces faces-gui
```

The `faces-gui` Service is mirrored to the `cdn` cluster, so we can access it
from there, too:

```bash
kubectl --context cdn get svc -n faces
```

It appears as the `faces-gui-faces` Service, since the mirrored services get
the cluster name tacked on the end.

Also in the `cdn` cluster, we have Emissary running as a simple CDN wannabe:
yup, we're using an _entire Envoy_ to do a single L4 route. (We'll be updating
this later with a Rust L4 proxy instead -- but that's for another day!)

```bash
kubectl --context cdn get tcpmapping -n faces -o yaml
kubectl --context cdn get svc -n emissary emissary -o jsonpath='{.spec.ports}' | jq
```

So! We should be able to grab the LoadBalancer IP address of the `emissary`
Service in the `cdn` cluster...

```bash
CDNADDR=$(kubectl --context cdn get svc -n emissary emissary -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
#@immed
echo "CDN IP: http://${CDNADDR}/"
```

...and use that to check out Faces in the browser!

<!-- @browser_then_terminal -->

# Going More Multicluster

This is entertaining, but it's not really multicluster yet, even given the
"CDN", because we're still just using one cluster for the actual service. So
let's change that.

One of the really cool things you can start doing with Linkerd's pod-to-pod
multicluster is using _clusters_ the way we used to use _namespaces_. Why? It
lets your development teams have tremendous control and autonomy and _they
can't mess up anything else_. So let's start by splitting the `faces` cluster
up. Let's suppose we want our `smiley` team to have their own cluster.

<!-- @wait -->

This first means we need a cluster, which... wow, there are a lot of details
to keep track of when doing that. For Linkerd's pod-to-pod multicluster, the
clusters need IP routing set up, they need non-overlapping Pod CIDRs, they
need... enough stuff that it can be tricky. So we're going to use a tool
called `localcluster` to handle all that. (At the moment, `localcluster` lives
in this repo.)

Here's the `localcluster` definition file for our `smiley` cluster:

```bash
bat clusters/smiley/sma.yaml
```

And here's what it does to create the `smiley` cluster:

```bash
./localcluster create --dryrun clusters smiley
```

You can see that, uh, there's a lot of stuff that goes on in there! So let's
get to it.

```bash
./localcluster create clusters smiley
```

OK, given the cluster, let's get Linkerd going.

```bash
#@immed
rm -f clusters/smiley/issuer*
./localcluster certs clusters smiley
./localcluster linkerd --dryrun clusters smiley
./localcluster linkerd clusters smiley
```

...and let's link up `smiley` with the rest of its group. This is another one
that will affect more than just `smiley`.

```bash
./localcluster group clusters smiley
linkerd --context faces mc check
```

<!-- @wait_clear -->

## Splitting Faces

OK, let's get Faces running in the `smiley` cluster. We'll have its `smiley`
workload return heart-eyed smilies.

```bash
kubectl --context smiley create ns faces
kubectl --context smiley annotate ns/faces linkerd.io/inject=enabled

helm install --kube-context smiley \
     faces -n faces \
     oci://ghcr.io/buoyantio/faces-chart --version 1.4.0 \
     --set smiley.smiley=HeartEyes \
     --set smiley.errorFraction=0
```

We _only_ want the `smiley` workload, so let's delete all the others.
(Obviously this is a silly way to do things, but that's the reality of the
Faces chart at the moment.)

```bash
kubectl --context smiley delete deploy -n faces faces-gui face color
kubectl --context smiley rollout status -n faces deploy
```

Then we mirror the `smiley` Service using pod-to-pod multicluster...

```bash
kubectl --context smiley label -n faces \
    svc/smiley mirror.linkerd.io/exported=remote-discovery
```

...which should cause it to appear in the `faces` cluster.

```bash
kubectl --context faces get svc -n faces
```

At this point we can use an HTTPRoute in the `faces` cluster to switch traffic
over to the mirrored `smiley` workload.

<!-- @show_5 -->

```bash
bat clusters/smiley/route-to-smiley.yaml
kubectl --context faces apply -f clusters/smiley/route-to-smiley.yaml
```

After that, we can delete the `smiley` workload from the `faces` cluster.

```bash
kubectl --context faces delete deploy -n faces smiley
```

<!-- @wait_clear -->
<!-- @show_2 -->

## WAIT A MINUTE (part 1)

Did anyone catch what we just did? There are three _incredibly cool_ things
that we just did that are worth calling out.

<!-- @wait -->

1. We took a workload that was running in one cluster, and we moved it to
   another cluster.

<!-- @wait -->

2. We did it _without changing the workload at all_.

<!-- @wait -->

3. We did it in a way that permits progressive delivery.

<!-- @wait -->

Let's prove point 3 by _progressively migrating_ `color` out of the `faces`
cluster. I've set up a `color` cluster the same as the `smiley` cluster
already, with the `color` workload running (set to return green):

```bash
kubectl --context color get pods -n faces
```

...so we can go ahead and mirror its `color` Service to the `faces` cluster.

```bash
kubectl --context color label -n faces \
    svc/color mirror.linkerd.io/exported=remote-discovery
kubectl --context faces get svc -n faces
```

At this point, we'll once again do an HTTPRoute in the `faces` cluster to
switch traffic over, but we'll do it _gradually_ this time.

<!-- @show_5 -->

```bash
bat clusters/color/route-to-color-10.yaml
kubectl --context faces apply -f clusters/color/route-to-color-10.yaml
kubectl --context faces edit httproute -n faces color-route
kubectl --context faces edit httproute -n faces color-route
kubectl --context faces edit httproute -n faces color-route
```

At this point everything is green, and we can delete the `color` workload from
the `faces` cluster.

```bash
kubectl --context faces delete deploy -n faces color
```

<!-- @wait_clear -->

But wait! there's more! I also have a precreated `color-b` cluster with just
the `color` workload, returning the original blue... and we can progressively
switch between those two, from `faces`.

```bash
kubectl --context color-b get pods -n faces
kubectl --context color-b label -n faces \
    svc/color mirror.linkerd.io/exported=remote-discovery
kubectl --context faces get svc -n faces
bat clusters/color-b/route-to-color-b-10.yaml
kubectl --context faces apply -f clusters/color-b/route-to-color-b-10.yaml
kubectl --context faces edit httproute -n faces color-route
kubectl --context faces edit httproute -n faces color-route
kubectl --context faces edit httproute -n faces color-route
```

<!-- @wait_clear -->
<!-- @show_2 -->

## WAIT A MINUTE (part 2)

Everybody caught that bit, too, right? We have an HTTPRoute in one cluster
doing actual progressive delivery where the two versions of our workload are
in two _other_ clusters. In other words, we're progressively delivering
_clusters_ now.

There are a lot of really fascinating things we could do here:

- Obviously, this is a great tool for letting development teams work
  independently. If they have their own clusters, it's really hard to step on
  each other's toes.

<!-- @wait -->

- If you have different clusters, you can also vary a _lot_ more things.
  Linkerd multicluster is perfectly happy to use different versions of
  Kubernetes, different versions of Linkerd, different CNIs, different
  versions of CRDs... the sky's the limit.

<!-- @wait -->

- Remember also that as you vary those things... you can do progressive
  delivery. Or A/B testing.

<!-- @wait_clear -->

## Routing Notes

Remember that what we have set up looks like this:

- Our HTTP request goes to the Emissary Service in the `cdn` cluster.

<!-- @wait -->

- Emissary sends it to a Service in the `cdn` cluster that's mirrored from the
  `faces` cluster.

<!-- @wait -->

- Linkerd in the `cdn` cluster sends the request to the `faces` cluster,
  because that's what mirrored services do.

<!-- @wait -->

- The `faces` GUI in the `faces` cluster makes a new request to the `face`
  workload in the `faces` cluster. Linkerd does mTLS but no cluster-crossing
  stuff here.

<!-- @wait -->

- The `face` workload talks to `smiley` and `color`, which are HTTPRoutes in
  the `face` cluster.

<!-- @wait -->

- Both `smiley` and `color` redirect to Services mirrored from other clusters.

<!-- @wait -->

- Linkerd in the `faces` cluster sends the request to the `smiley` or `color`
  cluster, because, again, that's the point of mirrored services.

<!-- @wait_clear -->

There's an axiom in Gateway API routing: you only get one layer of routing --
a given HTTPRoute can't use another HTTPRoute as a backend. So how are we able
to do two layers of routing here? (Hint: it's not because Emissary isn't using
Gateway API.)

<!-- @wait -->

The critical bit here is that we're routing *two separate requests*:

<!-- @wait -->

1. Browser -> `cdn` Emissary -> Linkerd mirrored Service -> `face` workload in
   the `faces` cluster

<!-- @wait -->

2. `face` workload in the `faces` cluster -> `smiley` or `color` HTTPRoute ->
    Linkerd mirrored Service -> `smiley` or `color` clusters

<!-- @wait -->

The request in step 2 is _not_ the same request as the one in step 1, which
means that it gets its own chance to do routing magic. As long as you set
things up like that, you can do arbitrarily complex things with routing.
Obviously, there's a latency cost, but Linkerd is fast enough that it often
simply doesn't matter.

<!-- @wait_clear -->

## Multicloud and Multicluster

We haven't really talked about where these clusters are running, yet. As it
happens, we're using kind clusters so far.

```bash
kind get clusters
```

...or, well, OK, I lied. We're using kind _and_ k3d clusters:

```bash
k3d cluster list
```

**Every** request being made here hits the k3d `cdn` cluster and then Linkerd
multicluster takes it over to the kind `faces` cluster (mTLS'd all the way).
This isn't relying on _any_ special networking: where the kind clusters are,
at the moment, doing pod-to-pod multicluster, the `cdn` cluster is doing
gateway-based multicluster to the `faces` cluster. Those clusters do _not_
have any special routing going on, and we can prove it by looking at some
CIDRs and endpoints:

```bash
./localcluster info clusters cdn
kubectl --context cdn get svc -n faces faces-gui-faces
kubectl --context cdn get endpoints -n faces faces-gui-faces

./localcluster info clusters faces
kubectl --context faces get svc -n faces faces-gui
kubectl --context faces get endpoints -n faces faces-gui
```

The endpoint for the `faces-gui-faces` Service in the `cdn` cluster is
_definitely_ not something the `faces` cluster's CIDRs... also, it's on a
bizarre port. Turns out that's the Linkerd multicluster gateway!

```bash
kubectl --context faces get svc -n linkerd-multicluster linkerd-gateway
```

And hey, look, that's a LoadBalancer Service -- which means that its
`EXTERNAL-IP` address really _should_ be globally routable.

<!-- @wait_clear -->

Compare and contrast with what goes on between `faces` and `smiley`:

```bash
./localcluster info clusters faces
kubectl --context faces get svc -n faces smiley-smiley
kubectl --context faces get endpoints -n faces smiley-smiley
linkerd --context faces diagnostics endpoints smiley-smiley.faces.svc.cluster.local

./localcluster info clusters smiley
kubectl --context smiley get svc -n faces smiley
kubectl --context smiley get endpoints -n faces smiley
```

where we can see that the `faces` cluster is routing directly across to a Pod
in the `smiley` cluster.

<!-- @wait_clear -->

## Disaster Recovery

Onward with another application! Honestly, disaster recovery is kind of
anticlimactic after what we've already shown, because it's really just another
application of what we've already shown... but's let's look anyway, because
there is one important bit to pay attention to.

<!-- @wait -->

As before, I've precreated a `faces-dr` cluster that's already running Faces.
It's even already linkerd to the `cdn` cluster, so if we mirror its
`faces-gui` Service, we should see a `faces-gui-faces-dr` Service appear in the
`cdn` cluster.

```bash
kubectl --context faces-dr label -n faces \
    svc/faces-gui mirror.linkerd.io/exported=true
kubectl --context cdn get svc -n faces
```

If we then apply a second TCPMapping in the `cdn` cluster, we should see a
50/50 split between the `faces-gui-faces` and `faces-gui-faces-dr` Services.

```bash
bat clusters/faces-dr/tcpmapping.yaml
```

<!-- @show_5 -->

```bash
kubectl --context cdn apply -f clusters/faces-dr/tcpmapping.yaml
```

<!-- @wait_clear -->

So... what's the important bit? Well, it's that we haven't talked about what
kind of DR we want and how to make it happen. What I'm showing here is really
active-active failover: split traffic between two clusters (which, in the real
world, would be set up to behave the same) and then if one goes down...
well... what happens?

```bash
kubectl --context faces scale deploy -n faces faces-gui --replicas=0
```

As it happens, Emissary handles this pretty gracefully when we're using it as
an L4 router, but that's mostly just luck. Let's scale our "failing"
`faces-gui` back up and see what happens.

```bash
kubectl --context faces scale deploy -n faces faces-gui --replicas=1
```

The right way to manage this, of course, is with active health checking that
simply stops routing to the broken cluster, for example:

```bash
kubectl --context cdn delete tcpmapping -n faces faces-dr-mapping
```

<!-- @wait_clear -->

There are other kinds of failover, of course. You could do active-passive. You
could, in fact, spin up an entirely new cluster only after your main cluster
crashes -- it feels like `localcluster` took forever with the `smiley` cluster
in the beginning, but in fact setting up all the clusters I use for this demo
takes only five minutes or so on my Mac, and maybe that kind of downtime is
fine. The point is that switching the entire app to a different cluster is
_easy_, and _fast_, with multicluster.

<!-- @wait_clear -->
<!-- @show_2 -->

## WAIT A MINUTE (part 3)

As usual, there are a couple of really cool things that I haven't told you
yet.

First: `faces` and its brethren are running in kind clusters, but `faces-dr`
is a k3d cluster. So this is actually showing a **multi-cloud** failover:
there's _nothing_ special about the networking between the `cdn`, `faces`, and
`faces-dr` clusters, which means it'll work everywhere.

Wanna do GKE to AWS? Knock yourself out. EKS to Azure? Sure. It's all the
same: the _only_ thing that Linkerd gateway-based multicluster relies on is
working LoadBalancer services. (It's fine if the traffic goes over the public
Internet, too: mTLS for the win!)

<!-- @wait -->

Second: `faces-dr` doesn't actually have a running `smiley` workload:

```bash
kubectl --context faces-dr get pods -n faces
```

That screaming-face `smiley` workload is actually running in a separate
`smiley-dr` cluster, with its Service mirrored to the `faces-dr` cluster.

```bash
kubectl --context smiley-dr get pods -n faces
kubectl --context faces-dr get svc -n faces smiley
```

So we're showing multicloud multicluster, just to reinforce that you're not
limited to one multicluster setup: you can do all the tricks with progressive
delivery, etc., across multiple clusters at the same time.

<!-- @wait -->

Finally, to reinforce the obvious: the `cdn` cluster is a single point of
failure in this demo. If you're really serious about multicloud, you need to
get serious about globally distributed ingress, which is a whole thing all its
own. Using a proper CDN is one of the simpler ways to do it, though there are
others.

<!-- @wait_clear -->

## Migration

Finally, migration.

<!-- @wait -->

We already showed this, actually:

- We moved the `smiley` workload from the `faces` cluster to the `smiley`
  cluster.

<!-- @wait -->

- We progressively moved the `color` workload from the `faces` cluster to the
  `color` cluster, then we progressively moved it to the `color-b` cluster.
  (We could move it back, of course.)

<!-- @wait -->

- We did an active-active failover with the `faces` and `faces-dr` clusters.

<!-- @wait -->

...OK, fine, we didn't really show the full-on cross-cloud migration, since we
rolled back to the `faces` cluster after splitting to `faces-dr`. So OK, let's
do that.

<!-- @wait -->

First, we reapply the CDN mapping that splits the traffic between `faces` and
`faces-dr`:

<!-- @show_5 -->

```bash
kubectl --context cdn apply -f clusters/faces-dr/tcpmapping.yaml
```

Then, we delete the mapping that's carrying traffic to `faces`.

```bash
kubectl --context cdn delete tcpmapping -n faces faces-mapping
```

Then we're **done**. Let's prove it by deleting all the clusters on the
`faces` side:

```bash
./localcluster delete clusters faces color color-b smiley
```

Oh look, our app is still working! So... there you go, there's a cross-cloud
migration.

<!-- @wait -->

That's probably the most important lesson about multicluster: once you have a
really easy way to route across clusters, you have a really easy way to
migrate too.

<!-- @wait_clear -->
<!-- @show_2 -->

## Summary

So there you have it! Honestly, the hardest part of this demo is creating
clusters dynamically, and linking them together: once the links are in place,
actually running things across clusters is _easy_.

Ultimately, that's the point of practical multicluster work: namespaces aren't
your only tool any more, and many areas where we found limitations because of
cluster boundaries aren't that big a deal any more. You can do a _lot_ with
multicluster; we're pretty much just scratching the surface here.

<!-- @wait -->

Finally, feedback is always welcome! You can reach me at flynn@buoyant.io or
as @flynn on the Linkerd Slack (https://slack.linkerd.io).

<!-- @wait -->
<!-- @show_slides -->
