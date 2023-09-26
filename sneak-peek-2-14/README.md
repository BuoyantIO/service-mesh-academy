# Sneak Peek: Linkerd 2.14

This is the documentation - and executable code! - for the Service Mesh
Academy workshop about what's coming in Linkerd 2.14. The easiest way to use
this file is to execute it with [demosh].

Things in Markdown comments are safe to ignore when reading this later. When
executing this with [demosh], things after the horizontal rule below (which
is just before a commented `@SHOW` directive) will get displayed.

[demosh]: https://github.com/BuoyantIO/demosh

<!-- set -e >

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

    `bash create-clusters.sh`

to create the clusters with all the necessary network setup, and then

    `bash setup-demo.sh`

to install Linkerd, the Linkerd multicluster extension, Emissary, and the
multicluster Faces demo, and link the clusters together in the mesh. You are
**strongly** encouraged to read these scripts, but recognize that some of
`create-clusters.sh` is serious `k3d` wizardry. 🙂

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

Our three clusters are called `north`, `east`, and `west` just to make them
easier to tell apart than using numbers or some such:

- The `north` cluster has the Faces GUI and the `face` workload, and is
  cluster that users will first talk to (so it's where the north-south
  communication) happens. An instance of the `color` workload runs here, too.
- The `east` cluster is running only a `smiley` workload.
- The `west` cluster runs another `color` workload.

Our KUBECONFIG has a context for each cluster, with the same name as the
cluster, so that we can easily talk to any of them from the command line:

```bash
kubectl --context north cluster-info
kubectl --context east cluster-info
kubectl --context west cluster-info
```

<!-- @wait_clear -->

## Multicluster Links

We've linked our clusters together so that pods in the `north` cluster can
communicate with pods in the `east` and `west` clusters. We actually did the
linking in `setup-demo.sh`, with the `linkerd multicluster link` command, for
example:

```
linkerd --context=east multicluster link --gateway=false --cluster-name east \
    | kubectl --context=north apply -f -
```

**Pay careful attention to the contexts here.**

<!-- @wait -->

- We run `linkerd multicluster link` in the `east` context; that tells
  `east`'s Linkerd installation to generate a Link resource that will tell
  some other cluster's Linkerd how to talk to it.

- We also supply `--gateway=false` to tell Linkerd to use Pod-to-Pod
  networking.

<!-- @wait -->

- We apply that `Link` resource in the `north` context, which tells `north`'s
  Linkerd how to talk to `east`'s Linkerd.

<!-- @wait -->

If we wanted to, we could do basically the same thing to set up a link from
`east` back to `north`, but we don't need it here so we didn't set it up.

<!-- @wait_clear -->

If we want, we can get a lower-level look at the links by examing the Link
resources:

```bash
kubectl --context north get link -n linkerd-multicluster
```

We see one for each linked cluster, and if we look at the resource itself
we'll see a bunch of information about the linked cluster:

```bash
kubectl --context north get link -n linkerd-multicluster east -o yaml | bat -l yaml
```

We can use the same trick to verify that there aren't any Links back from the
other clusters:

```bash
kubectl --context east get link -n linkerd-multicluster
kubectl --context west get link -n linkerd-multicluster
```

As we said before, we made links from `north` to `east` and `west`, but not
the other direction. We could have - it would work fine - but we don't need
them for this demo.

<!-- @wait_clear -->

## No Gateways

As a quick aside for those familiar with Linkerd 2.13 multicluster operations:
when we use Linkerd 2.14's Pod-to-Pod networking, the multicluster gateways
you'd see in Linkerd 2.14 don't exist:

```bash
linkerd --context north multicluster gateways
```

The way this works is that the Linkerd control plane in the `north` cluster
talks directly to the `east` and `west` control planes to do service
discovery, and the gateways aren't necessary to rely traffic any more, so they
don't appear.

<!-- @wait_clear -->

## The `north` cluster

The `north` cluster is the one users connect to. It has a lot of stuff running
in it. First, let's take a look at what's running in the `faces` namespace.

```bash
kubectl --context north get pods -n faces
```

We see the Faces GUI, the `face` workload, and the `color` workload... but...
uh... no `smiley` workload? So... where are the smileys coming from?

What do the services here look like?

```bash
kubectl --context north get svc -n faces
```

We see `faces-gui` for the GUI, `face` and `color`, and... `smiley` and
`smiley-east`?

<!-- @wait_clear -->

## Mirrored services

What's going on here is that `smiley-east` is a _mirror_ of the `smiley`
Service from the linked `east` _cluster_. If we look at the `faces` namespace
in the `east` cluster, we can see a little bit more of the picture:

```bash
kubectl --context east get svc,pods -n faces
```

That's Faces' typical `smiley` and `smiley2` setup, so the `smiley` workloads
must actually be running here. The magic is actually in the labels on the
`smiley` Service:

```bash
kubectl --context east get svc smiley -n faces -o yaml | bat -l yaml
```

The `mirror.linkerd.io/exported: remote-discovery` label tells the Linkerd
control plane in _other_ clusters linked to this one to mirror the Service for
direct pod-to-pod communication. (If you're familiar with the way Linkerd did
multicluster in 2.13, you might remember this label with a value of `enabled`.
That still works if you configure multicluster with gateways, but it's not
what we want here.)

<!-- @wait_clear -->

When remote discovery is enabled, the Linkerd control plane mirrors the
Service across the Link. In this case, the `north` cluster has a Link
connecting it to the `east` cluster, so when the Linkerd control plane sees
the `mirror.linkerd.io/exported` label, it will pull a copy of the `smiley`
Service from `east` into `north`.

The mirrored service currently gets a name of `$ServiceName-$ClusterName`, so
`smiley-east` is the mirrored `smiley` Service from the `east` cluster.

<!-- @wait_clear -->

It's also instructive to check out the endpoints of both our `smiley`
Service (in the `east` cluster) and our `smiley-east` Service (in the
`north` cluster):

```bash
kubectl --context east get endpoints smiley -n faces
```

Two endpoints, since we have two replicas. This makes sense.

```bash
kubectl --context north get endpoints smiley-east -n faces
```

No endpoints. On the face of it, this seems wrong - how can anything work with
no endpoints - but what's going on here is that the Linkerd control plane is
tracking endpoints for us. The `linkerd diagnostics endpoints` command will
show them to us (note that we have to give it the fully-qualified name of the
Service):

```bash
linkerd --context north diagnostics endpoints smiley-east.faces.svc.cluster.local:80
```

Two endpoints, like we'd expect because there are two replicas. Also note that
the IP addresses are the same, which is a great sign since this is supposed to
be a flat network.

<!-- @wait_clear -->

## Bringing in the Gateway API

OK, so we have a mirrored `smiley-east` Service, the Linkerd control plane
is managing its endpoints, all is well. However, the Faces app doesn't talk to
`smiley-east`: it just talks to `smiley`. So how is that working?

Answer: we're using an HTTPRoute under the hood.

First, the astute reader will have noticed that the `north` cluster has a
`smiley` Service in addition to `smiley-east`. Let's take a quick, but
careful, look at that.

```bash
kubectl --context north get svc -n faces smiley -o yaml | bat -l yaml
```

<!-- @wait -->

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
it to `smiley-east` instead, with a five-second timeout". That's what's
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

Also, you can't use an HTTPRoute in the `north` cluster to direct traffic to a
mirrored Service from `east`, then have an HTTPRoute in the `east` cluster
further split the traffic. That's because the `north` cluster finds the
endpoints and goes directly to one of them, rather than allowing anything in
the `east` cluster to affect the chosen endpoint. (This is also true with
HTTPRoutes in the same cluster: you can't stack them.)

<!-- @wait_clear -->

## HTTPRoute timeouts

Let's see if we can put timeouts to work. Setting a 300ms timeout has worked
out well in the past to improve the Faces user experience, so let's edit the
HTTPRoute and change its timeout to 300ms.

```bash
kubectl --context north edit httproute smiley-router -n faces
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
`west` cluster's `color2` Service as a demo.

We need to start by mirroring the `color2` Service into our `north` cluster
(which is already linked to the `west` cluster). All we need to make that
happen is to put the correct label on the Service in the `west` cluster:

```bash
kubectl --context west -n faces label svc/color2 mirror.linkerd.io/exported=remote-discovery
```

As soon as we do that, we'll see the mirrored Service `color2-west` appear in
the `north` cluster:

```bash
kubectl --context north -n faces get svc
```

And, if we check out the endpoints, we should be good to go:

```bash
kubectl --context west get endpoints color2 -n faces
linkerd --context north diagnostics endpoints color2-west.faces.svc.cluster.local:80
```

So Linkerd knows the right endpoints for the `color2-west` Service.

<!-- @wait_clear -->

At that point, we can add an HTTPRoute to split traffic.

```bash
#@immed
bat k8s/02-canary/color-canary.yaml
```

Let's apply that and see how it goes:

```bash
kubectl --context north apply -f k8s/02-canary/color-canary.yaml
```

Back to the browser to see what we see...

<!-- @browser_then_terminal -->

Now that our split is working, we can do something kind of cool. We can
migrate `color` completely off the `north` cluster just by editing the
HTTPRoute. We'll use `kubectl edit` to delete the `backendRef` for the local
`color` Service.

```bash
kubectl --context north edit httproute color-canary -n faces
```

At this point, we'll see all blue cells in the browser.

<!-- @browser_then_terminal -->

Just to round things out, let's delete the `color` Deployment in the `face`
cluster...

```bash
kubectl --context north delete -n faces deployment color
```

...and prove that it's gone.

```bash
kubectl --context north get pods -n faces
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
