# Sneak Peek: Linkerd 2.14

This is the documentation - and executable code! - for the Service Mesh
Academy workshop about what's coming in Linkerd 2.14. The easiest way to use
this file is to execute it with [demosh].

Things in Markdown comments are safe to ignore when reading this later. When
executing this with [demosh], things after the horizontal rule below (which
is just before a commented `@SHOW` directive) will get displayed.

[demosh]: https://github.com/BuoyantIO/demosh

<!-- set -e >
<!-- @import demosh/demo-tools.sh -->
<!-- @import demosh/check-requirements.sh -->

<!-- @start_livecast -->

```bash
BAT_STYLE="grid,numbers"
```

---
<!-- @SHOW -->

# Sneak Peek: Linkerd 2.14

Welcome to the Service Mesh Academy Sneak Peek for Linkerd 2.14! We're going
to show off a multicluster version of the Faces demo using `k3d`.

**NOTE**: `k3d` is great because it's easy for anyone to lay hands on.
However, setting up `k3d` for a flat-network multicluster demo is _extremely_
tricky, enough so that we're not going to do it during the demo. Instead, all
the gory details are in `create-clusters.sh` and `setup-demo.sh`, and this
demo assumes that you've run both of those.

<!-- @wait -->

So! To set everything up, first run

    `demosh create-clusters.sh`

to create the clusters with all the necessary network setup, and then

    `demosh setup-demo.sh`

to install Linkerd, the Linkerd multicluster extension, Emissary, and the
multicluster Faces demo, and link the clusters together in the mesh.

(You can run them with `bash` instead of `demosh` if you like, but it'll be
much less clear what's going on.)

<!-- @wait_clear -->

That's all done? Good. At this point, our Faces demo should be happily
running. Let's take a look in the browser.

<!-- @browser_then_terminal -->

This looks like a pretty typical Faces demo, but under the hood it's quite
different: we have three clusters running, all on a flat network so that pods
in each cluster can talk to the pods in the others, with Linkerd installed and
all three clusters linked. Let's take a look at what that looks like.

<!-- @wait_clear -->

## The clusters

Our three clusters are called `face`, `smiley`, and `color` after the primary
workload in each cluster:

- The `face` cluster has the Faces GUI and the `face` workload
- The `smiley` cluster has the `smiley` workload
- The `color` cluster has the `color` workload

Our KUBECONFIG has a context for each cluster, with the same name as the
cluster, so that we can easily talk to any of them from the command line:

```bash
kubectl --context face cluster-info
kubectl --context smiley cluster-info
kubectl --context color cluster-info
```

<!-- @wait_clear -->

## Links and gateways

We've linked our clusters together so that pods in the `face` cluster can
communicate with pods in the `smiley` and `color` clusters. An easy way to see
this is to use the `linkerd multicluster gateways` command:

```bash
linkerd --context face multicluster gateways
```

We see that we have gateways to the `smiley` and `color` clusters, and they're
alive... but wait, we're talking about pod-to-pod communication without
gateways, aren't we?

<!-- @wait -->

Yes -- on the data plane. The Linkerd control plane still relies on the
gateways to help with service discovery, which is why you see them here. And
if a gateway doesn't show as alive, you definitely have a problem (though this
can be transient).

<!-- @wait_clear -->

If we check the other clusters, we won't see any gateways (unfortunately, this
also takes 30 seconds at the moment, so we'll only check one cluster):

```bash
linkerd --context smiley multicluster gateways
```

This is because links are _unidirectional_, and for multicluster Faces, we
only need the `face` cluster to be able to reach out to the other two. Linking
in both directions works fine, it's just unnecessary for what we're doing
here.

<!-- @wait_clear -->

We actually did the linking in `setup-demo.sh`, with the `linkerd multicluster
link` command, for example:

```
linkerd --context=smiley multicluster link --cluster-name smiley \
    | kubectl --context=face apply -f -
```

**Pay careful attention to the contexts here.**

<!-- @wait -->

- We run `linkerd multicluster link` in the `smiley` context; that tells
  `smiley`'s Linkerd installation to generate a Link resource that will tell
  some other cluster's Linkerd how to talk to it.

<!-- @wait -->

- We apply that `Link` resource in the `face` context, which tells `face`'s
  Linkerd how to talk to `smiley`'s Linkerd.

<!-- @wait -->

Again, we could set up a link in the opposite direction if we want to, but we
don't need it here.

<!-- @wait_clear -->

If we want, we can get a lower-level look at the links by examing the Link
resources:

```bash
kubectl --context face get link -n linkerd-multicluster
```

We see one for each linked cluster, and if we look at the resource itself
we'll see a bunch of information about the linked cluster:

```bash
kubectl --context face get link -n linkerd-multicluster smiley -o yaml | bat -l yaml
```

This also gives us a much better way to check the other clusters to observe
that they have no links:

```bash
kubectl --context smiley get link -n linkerd-multicluster
kubectl --context color get link -n linkerd-multicluster
```

Only the `face` cluster has links, as we said before.

<!-- @wait_clear -->

## The `face` cluster

The `face` cluster is the one users connect to. It has a lot of stuff running
in it. First, let's take a look at what's running in the `faces` namespace.

```bash
kubectl --context face get pods -n faces
```

We see the Faces GUI, the `face` workload, and the `color` workload... but...
uh... no `smiley` workload? So... where are the smileys coming from?

What do the services here look like?

```bash
kubectl --context face get svc -n faces
```

We see `faces-gui` for the GUI, `face` and `color`, and... `smiley` and
`smiley-smiley`?

<!-- @wait_clear -->

## Mirrored services

What's going on here is that `smiley-smiley` is _mirrored_ from the linked
`smiley` _cluster_. If we look at the `faces` namespace in the `smiley`
cluster, we can see a little bit more of the picture:

```bash
kubectl --context smiley get svc,pods -n faces
```

That's Faces' typical `smiley` and `smiley2` setup, so the `smiley` workloads
must actually be running here. The magic is actually in the labels on the
`smiley` Service:

```bash
kubectl --context smiley get svc smiley -n faces -o yaml | bat -l yaml
```

The `mirror.linkerd.io/exported: remote-discovery` label tells the Linkerd
control plane in _other_ clusters linked to this one to mirror the Service for
direct pod-to-pod communication. (If you're familiar with the way Linkerd did
multicluster in 2.13, you might remember this label with a value of `enabled`.
That still works, but it's not what we want here.)

<!-- @wait_clear -->

When remote discovery is enabled, the Linkerd control plane mirrors the
Service across the Link -- in this case, since the `face` Service is looking
into the `smiley` cluster, the `smiley` Service gets pulled from `smiley` into
`face`.

The mirrored service currently gets a name of `$ServiceName-$ClusterName`. In
our case, the Service and cluster are both named `smiley`, so you see
`smiley-smiley`. (Sorry about that.)

<!-- @wait_clear -->

It's also instructive to check out the endpoints of both our `smiley` Service
and our `smiley-smiley` Service.

```bash
kubectl --context smiley get endpoints smiley -n faces
```

Two endpoints, since we have two replicas. This makes sense.

```bash
kubectl --context face get endpoints smiley-smiley -n faces
```

No endpoints. On the face of it, this seems wrong: how can anything work with
no endpoints? but what's going on here is that the Linkerd control plane is
tracking endpoints for us. The `linkerd diagnostics endpoints` command will
show them to us (note that we have to give it the fully-qualified name of the
Service):

```bash
linkerd --context face diagnostics endpoints smiley-smiley.faces.svc.face:80
```

Two endpoints, like we'd expect because there are two replicas. Also note that
the IP addresses are the same, which is a great sign since this is supposed to
be a flat network.

<!-- @wait_clear -->

## Bringing in the Gateway API

OK, so we have a mirrored `smiley-smiley` Service, the Linkerd control plane
is managing its endpoints, all is well. However, the Faces app doesn't talk to
`smiley-smiley`: it just talks to `smiley`. So how is that working?

Answer: we're using an HTTPRoute under the hood.

First, the astute reader will have noticed that the `face` cluster has a
`smiley` Service in addition to `smiley-smiley`. Let's take a quick, but
careful, look at that.

```bash
kubectl --context face get svc -n faces smiley -o yaml | bat -l yaml
```

If you look closely, you'll realize that something is missing: this Service
has no `selector`, so it can match no Pods, so it will never have any
endpoints.

<!-- @wait_clear -->

## The `smiley-router` HTTPRoute

In fact, the only purpose of the `smiley` Service is to have this HTTPRoute
attached to it:

```bash
#@immed
yq 'select(document_index==5)' k8s/01-face/faces-mc.yaml | bat -l yaml
```

This HTTPRoute says "take all traffic sent to the `smiley` service and divert
it to `smiley-smiley` instead, with a five-second timeout". That's what's
permitting the Faces demo to work.

<!-- @wait_clear -->

## Some inconvenient truths

Note that we use a `policy.linkerd.io/v1beta3` HTTPRoute, not a
`gateway.networking.k8s.io` HTTPRoute. That's because we're using a timeout.

We're using Gateway API v0.8.0-rc1 at the moment -- and HTTPRoute timeouts are
defined by GEP-1742, which didn't quite make the cut for v0.8.0. They'll be in
Gateway API v1.0.0, but to use HTTPRoute timeouts with Linkerd, you need to
stick with `policy.linkerd.io/v1beta3`.

<!-- @wait -->

Also, you can't use an HTTPRoute in the `face` cluster to direct traffic to a
mirrored Service from `smiley`, then have an HTTPRoute in the `smiley` cluster
further split the traffic. That's because the `face` cluster finds the
endpoints and goes directly to one of them, rather than allowing anything in
the `smiley` cluster to affect the chosen endpoint. (This is also true with
HTTPRoutes in the same cluster: you can't stack them.)

<!-- @wait_clear -->

## HTTPRoute timeouts

Let's see if we can put timeouts to work. Setting a 300ms timeout has worked
out well in the past to improve the Faces user experience, so let's edit the
HTTPRoute and change its timeout to 300ms.

```bash
kubectl --context face edit httproute smiley-router -n faces
```

If we flip to the browser, sure enough, we'll see fewer faded cells and more
counts incrementing in the corners.

<!-- @browser_then_terminal -->

(The reason why the fading cells don't _all_ disappear is left as an exercise
for the reader. 😇)

<!-- @wait_clear -->
<!-- @SHOW -->

## Splitting across clusters

We aren't limited, of course, to just redirecting all our traffic to another
cluster. We can also use an HTTPRoute to split traffic across multiple
clusters. Let's take 50% of our color traffic and send it across to the
`color` cluster's `color2` Service as a demo.

We need to start by mirroring the `color2` Service into our `face` cluster
(which is already linked to the `color` cluster). All we need to make that
happen is to put the correct label on the Service in the `color` cluster:

```bash
kubectl --context color -n faces label svc/color2 mirror.linkerd.io/exported=remote-discovery
```

As soon as we do that, we'll see the mirror Service `color2-color` appear in
the `face` cluster:

```bash
kubectl --context face -n faces get svc
```

And, if we check out the endpoints, we should be good to go:

```bash
kubectl --context color get endpoints color2 -n faces
linkerd --context face diagnostics endpoints color2-color.faces.svc.face:80
```

So Linkerd knows the right endpoints for the `color2-color` Service.

<!-- @wait_clear -->

At that point, we can add an HTTPRoute to split traffic.

```bash
#@immed
bat k8s/02-canary/color-canary.yaml
```

Let's apply that and see how it goes:

```bash
kubectl --context face apply -f k8s/02-canary/color-canary.yaml
```

Back to the browser to see what we see...

<!-- @browser_then_terminal -->

Now that our split is working, we can do something kind of cool. We can
migrate `color` completely off the `face` cluster just by editing the
HTTPRoute. We'll use `kubectl edit` to delete the `backendRef` for the local
`color` Service.

```bash
kubectl --context face edit httproute color-canary -n faces
```

At this point, we'll see all blue cells in the browser.

<!-- @browser_then_terminal -->

Just to round things out, let's delete the `color` Deployment in the `face`
cluster...

```bash
kubectl --context face delete -n faces deployment color
```

...and prove that it's gone.

```bash
kubectl --context face get pods -n faces
```

This is an amazing thing about having multicluster running smoothly: you can
migrate between clusters simply by deleting things. 🙂

<!-- @wait_clear -->

# Sneak Peek: Linkerd 2.14

So there's a quick sampling of Linkerd 2.14 pod-to-pod multicluster, with a
touch of timeouts thrown in. You can find the source for this demo at

https://github.com/BuoyantIO/service-mesh-academy

in the `sneak-peek-2-14` directory -- the black magic of setup, again, is in
`create-clusters.sh` and `setup-demo.sh`.

As always, we welcome feedback! Join us at https://slack.linkerd.io/
for more.

<!-- @wait -->
<!-- @show_slides -->
