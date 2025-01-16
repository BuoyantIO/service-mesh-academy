<!--
SPDX-FileCopyrightText: 2024 Buoyant Inc.
SPDX-License-Identifier: Apache-2.0

SMA-Description: Getting Started with Linkerd
-->

# Linkerd 101

This is the documentation - and executable code! - for the Service Mesh
Academy Linkerd 101 workshop. The easiest way to use this file is to execute
it with [demosh].

Things in Markdown comments are safe to ignore when reading this later. When
executing this with [demosh], things after the horizontal rule below (which is
just before a commented `@SHOW` directive) will get displayed.

[demosh]: https://github.com/BuoyantIO/demosh

This workshop requires that you have a running Kubernetes cluster. The README
is written assuming that you're using a cluster that has working LoadBalancer
services, such that you can grab the external IP for a LoadBalancer and talk
to it. (On a Mac, you'll probably need to use [OrbStack](https://orbstack.dev)
to get this for local clusters.)

<!-- @import demosh/check-requirements.sh -->
<!-- @start_livecast -->
---
<!-- @SHOW -->

# Linkerd 101

Welcome to Linkerd 101! In this workshop, we'll show

- installing the Linkerd CLI
- using the CLI to install Linkerd to a Kubernetes cluster
- setting up a deliberately-broken demo application
- using Linkerd to observe the application
- using Linkerd to make the broken application behave better

To get started, let's make sure that our cluster is empty.

```bash
kubectl get ns
kubectl get all
```

So far so good! Next up, let's install the Linkerd CLI.

<!-- @wait_clear -->

# Installing the Linkerd CLI

For this workshop, we'll use Buoyant Enterprise for Linkerd (BEL) 2.17.0.
_This does require you to sign up for a free account with Buoyant._ But
really, it's worth it, and we won't sell your information to anyone! To get
set up, go to https://enterprise.buoyant.io/ and sign up.

Once done, you'll get to a page that'll show you three environment variables:

- `API_CLIENT_ID`
- `API_CLIENT_SECRET`
- `BUOYANT_LICENSE`

For this workshop, you only need `BUOYANT_LICENSE`, but go ahead and save all
three.

<!-- @wait -->

After that, you can install the CLI. (You can leave out setting
`LINKERD2_VERSION` if you want the latest -- we're pinning it here just to be
cautious!)

```bash
curl --proto '=https' --tlsv1.2 -sSfL https://enterprise.buoyant.io/install \
     | env LINKERD2_VERSION=enterprise-2.17.0 sh
export PATH=$HOME/.linkerd2/bin:$PATH
```

OK! Next up, let's make sure that our cluster is capable of running Linkerd:

```bash
linkerd check --pre
```

This should give us solid green checkmarks: if it doesn't, you'll need to fix
whatever errors show up before running Linkerd.

<!-- @wait_clear -->

# Installing the Linkerd CRDs

Next up, we need to install the Linkerd CRDs. This is a one-time operation for
each cluster, and it's what allows Linkerd to extend Kubernetes with its own
custom resources. We'll use this command for that:

```
linkerd install --crds | kubectl apply -f -
```

You'll see this idiom a lot: the `linkerd` CLI never modifies the cluster
directly. Instead, it generates Kubernetes YAML and prints it to stdout, so
that you can inspect it, modify it, commit it for GitOps, or just pipe it
directly to `kubectl apply` like we do here.

<!-- @wait -->

So let's get the CRDs installed:

```bash
linkerd install --crds | kubectl apply -f -
```

Now we're ready to install the control plane itself! But first, let's start
our running tally of places that the workshop is deliberately simplifying
things...

<!-- @wait_clear -->

## SIMPLIFICATIONS

**1. The `linkerd` CLI is managing the Gateway API CRDs.**

We can get away with this for the workshop because we're not going to have
Linkerd working with any other Gateway API project. If we _were_ (say, if we
wanted to use Linkerd and a Gateway API ingress controller), we'd want to
manage the Gateway API CRDs ourselves.

<!-- @wait_clear -->

# Installing the Linkerd Control Plane

OK, let's get to the control plane! This is another one-line installation:

```
linkerd install | kubectl apply -f -
```

This will install the control plane into the `linkerd` namespace, but it won't
wait for everything to start running (since we might have other things that
need doing while that's going on). So, whenever we're ready, we'll use
`linkerd check` - _without_ the `--pre` switch - to make sure the control
plane got happily bootstrapped.

For this workshop, we can just run them back to back:

```bash
linkerd install | kubectl apply -f -
linkerd check
```

and at this point, we should have a happily-running Linkerd in the `linkerd`
namespace in our cluster! If we want, we can take a look at what's running
there:

```bash
kubectl get ns
kubectl get pods -n linkerd
```

But it's time to add another simplification to our tally...

<!-- @wait_clear -->

## SIMPLIFICATIONS

1. The `linkerd` CLI is managing the Gateway API CRDs.

**2. The `linkerd` CLI is managing our certificates, too.**

Linkerd uses mTLS for secure communications -- and mTLS requires certificates.
For this workshop, we're letting the `linkerd` CLI silently generate the
certificates that Linkerd needs to run. This is a terrible idea for real-world
use, but it makes things _much_ simpler for the workshop!

<!-- @wait_clear -->

# Installing Linkerd Viz

We're also going to install Linkerd Viz, which gives us a simple dashboard for
observing what's up with our Linkerd installation. As with the control plane
itself, we'll use the `linkerd` CLI to generate manifests that we apply, then
we'll run `linkerd check` to make sure everything is running:

```bash
linkerd viz install | kubectl apply -f -
linkerd check
```

At this point, we can see that we now have a `linkerd-viz` namespace with some
things in it:

```bash
kubectl get ns
kubectl get pods -n linkerd-viz
```

and we can take a look at the dashboard in a web browser:

```bash
linkerd viz dashboard
```

And we have another simplification to call out here!

<!-- @wait_clear -->

## SIMPLIFICATIONS

1. The `linkerd` CLI is managing the Gateway API CRDs.
2. The `linkerd` CLI is managing our certificates, too.

**3. We let Linkerd Viz install Prometheus for us.**

Linkerd Viz is really a visualization layer built on top of Prometheus, so it
needs a running Prometheus. If you don't tell `linkerd viz install` otherwise,
it will install a Prometheus for you -- but that Prometheus keeps all its
metrics in memory, so it _will_ lose all your data when it restarts (which
happens frequently). For real-world use, you'd want to use your own Prometheus
installation.

<!-- @wait_clear -->

# Installing the Faces Demo

Now that we have Linkerd running, let's install a demo application to play
with. We'll use the world-famous Faces demo, which is a deliberately-broken
application intended to show how complex things can get with even just a few
microservices: it's at <https://github.com/BuoyantIO/faces-demo>.

We start by creating a namespace for Faces:

```bash
kubectl create ns faces
```

and then we annotate the namespace to tell Linkerd to inject its sidecar into
any pod created in that namespace:

```bash
kubectl annotate ns faces linkerd.io/inject=enabled
```

After that, we can use Helm to install Faces! The only configuration we're
supplying here setting the `gui.serviceType` to `LoadBalancer`, so that Faces
knows to pretend to be its own ingress controller, and enabling the `smiley2`
and `color2` workloads.

```bash
helm install -n faces faces \
     oci://ghcr.io/buoyantio/faces-chart \
     --version 2.0.0-rc.2 \
     --set gui.serviceType=LoadBalancer \
     --set smiley2.enabled=true \
     --set color2.enabled=true
```

Finally, let's wait for Faces to be running:

```bash
kubectl rollout status -n faces deploy
```

Now that Faces is running, we can connect to the `faces-gui` Service in the
`faces` namespace to see the Faces GUI! How you do this will depend on your
cluster.

- My local cluster, created with the `create-cluster.sh` script, exposes the
  `faces-gui` Service on localhost, so I can connect to `http://localhost/`.

- If you're using a cloud provider cluster, you'll want to use the external IP
  address of the `faces-gui` Service.

- If all else fails, you can use `kubectl port-forward` to get access.

<!-- @browser_then_terminal -->

Here's another simplification, too.

<!-- @wait_clear -->

## SIMPLIFICATIONS

1. The `linkerd` CLI is managing the Gateway API CRDs.
2. The `linkerd` CLI is managing our certificates, too.
3. We let Linkerd Viz install Prometheus for us.

**4. We're not running Faces behind an ingress controller.**

This is honestly just to save the time of installing and configuring the
ingress controller in this workshop. In the real world, you almost never want
to expose your application directly to the Internet: use an ingress controller
that's been hardened for that!

<!-- @wait_clear -->

# Observing Faces with Linkerd

Faces obviously doesn't look good. Let's take a look at what Linkerd can tell us
about it immediately. We'll start by heading over to Linkerd Viz again.

```bash
linkerd viz dashboard
```

So Linkerd Viz makes an enormous amount of information available to us,
ranging from mTLS status to the golden metrics! (This is all available via the
command line, too, though we're not going to show it in this workshop.)

What this information shows us about Faces is that it's in horrible shape: the
`face`, `smiley`, and `color` workloads are _all_ failing about 20% of the
time, which explains what we're seeing in the GUI. So let's take a look at how
to make things happier there.

<!-- @wait_clear -->
<!-- @show_5 -->

# Retries

A really obvious thing we can do here is to add retries. Let's start by going
after the purple frowning faces: those show up when the "ingress" (really the
`faces-gui` workload) gets a failure from the `face` workload. We should be
able to make those go away by retrying those requests, which we can do by
simply annotating the `face` Service itself. The purple frowning faces should
nearly all vanish from the GUI as soon as we run this command:

```bash
kubectl annotate -n faces svc face retry.linkerd.io/http=5xx
```

"Nearly" is because we're allowing only one retry, so if the
`face` workload fails twice in a row, we'll still see a purple
frowning face. We can make that less of an issue by simply
allowing more retries:

```bash
kubectl annotate -n faces svc face retry.linkerd.io/limit=3
```

Now we shouldn't see any purple cursing faces at all! On the other
hand, if we switch back to Linkerd Viz, we'll see that the load on
`face` has gone up quite a bit: retries provide for a better user
experience, but they don't protect the workload at all!

```bash
linkerd viz dashboard
```

<!-- @clear -->

# Retries

Next, we can tackle the cursing faces: those are when the `face` workload gets
a failure from the `smiley` workload, so we can tackle those by annotating the
`smiley` Service:

```bash
kubectl annotate -n faces svc smiley \
    retry.linkerd.io/http=5xx \
    retry.linkerd.io/limit=3
```

Finally, the grey backgrounds show up when `face` gets a failure
from `color`. That's a gRPC request, so the annotation looks
slightly different:

```bash
kubectl annotate -n faces svc color \
    retry.linkerd.io/grpc=internal \
    retry.linkerd.io/limit=3
```

That should get rid of the grey backgrounds!

<!-- @wait -->

...but it didn't work. Why not?

<!-- @wait_clear -->

# Retries

The reason is that Linkerd sees gRPC traffic as HTTP unless we apply a
GRPCRoute to tell it that traffic is really gRPC. Let's do that for `color`
and `color2`:

```bash
bat color-routes.yaml
kubectl apply -f color-routes.yaml
```

Once we do _that_, we see the grey backgrounds vanish from the GUI.

It's instructive to go back to the Viz dashboard here and see how
retries show up...

```bash
linkerd viz dashboard
```

<!-- @clear -->
<!-- @show_terminal -->

# Retries and Stats

The short answer is in fact that _they don't_. Retries just look like extra
traffic to the Viz dashboard at present: however, we do have a command-line
tool that we can use:

```bash
linkerd viz stat-outbound -n faces deploy/face
```

This is a great way to get more insight into what's going on. It's tough to
read with the window narrow enough for this workshop's livestream, though, so
we'll run it through a Python script to strip out the `LATENCY_P95` and
`LATENCY_P99` columns:

```bash
linkerd viz stat-outbound -n faces deploy/face | python filter-stats.py
```

<!-- @wait_clear -->
<!-- @show_5 -->

# Dynamic Routing

We can do a _lot_ more with reliability, but in the interest of time, let's
show just one more thing: dynamic request routing. We'll first install an
HTTPRoute that just unilaterally switches all our requests to `smiley` to go
to `smiley2` instead: this will switch all our cells to have heart-eyed
smilies instead of grinning smilies.

```bash
bat all-heart-eyes.yaml
kubectl apply -f all-heart-eyes.yaml
```

If we look back to Linkerd Viz, we'll slowly see the traffic
rate to `smiley` falling while the traffic rate to `smiley2`
rises (it doesn't happen immediately due to sampling intervals).

```bash
linkerd viz dashboard
```

<!-- @clear -->
<!-- @show_5 -->

# Dynamic Routing

Of course, we can do more fine-grained routing than just switching all
traffic. As it happens, the `face` workload uses two separate paths when
talking to `smiley`:

- `/center` for the central four cells
- `/edge` for all the cells around the edges

So let's modify our HTTPRoute to only switch the edge cells to
have heart-eyed smilies.

```bash
bat edge-heart-eyes.yaml
kubectl apply -f edge-heart-eyes.yaml
```

<!-- @wait_clear -->

# Dynamic Routing

We can do the same for the `color` workload: it uses the `Center` and `Edge`
gRPC Methods to distinguish between the central and edge cells. Let's switch
the center cells to have a green background, from `color2`, and leave the edge
cells alone.

```bash
bat edge-green.yaml
kubectl apply -f edge-green.yaml
```

<!-- @wait_clear -->
<!-- @show_terminal -->

# Auth

One last thing: we mentioned that Linkerd can use mTLS identities for
authentication and authorization of workloads. Auth policy can get _extremely_
complex, but let's show a very simple example: we'll set up a policy that will
only allow the `faces-gui` ServiceAccount to talk to the `face` workload.

This is the most complex YAML in this workshop - we need three interlocking
resources to get this done - but really it's not that awful.

```bash
bat face-auth.yaml
```

<!-- @clear -->
<!-- @show_5 -->

# Auth

Applying this YAML will instantly break our demo -- we'll be back to frowning
faces on purple backgrounds.

```bash
kubectl apply -f face-auth.yaml
```

<!-- @wait_clear -->
<!-- @show_terminal -->

# Auth

The reason is that the `faces-gui` workload is currently using the `default`
ServiceAccount, which we can see using the `linkerd identity` command.

(`linkerd identity` works in terms of pods, since identity is a property of
Linkerd's microproxy, and the microproxy is attached to a pod. You can either
supply pod names directly or use label selectors, as we do here.)

```bash
linkerd identity -n faces -l service=faces-gui
```

That shows us the whole proxy, which is more than we need -- let's focus in on
the `Subject:`, which is the name of the identity this microproxy will present
when it makes requests:

```bash
linkerd identity -n faces -l service=faces-gui | grep Subject:
```

Now we can see that `faces-gui` is currently using the `default`
ServiceAccount, which is why nothing is working.

<!-- @wait_clear -->
<!-- @show_5 -->

# Auth

To fix that, we first create the `faces-gui` ServiceAccount:

```bash
kubectl create serviceaccount -n faces faces-gui
```

and then we switch the `faces-gui` workload to use it.

```bash
kubectl set serviceaccount -n faces \
    deployment/faces-gui faces-gui
```

This will take a few seconds, since the `faces-gui` Deployment
has to restart, but things will start working again as soon as
it does!

<!-- @wait_clear -->
<!-- @show_terminal -->

# Wrapping Up

So that's a whirlwind tour of Linkerd basics. There is a _lot_ more that we
could go into:

- Dynamic request routing dovetails beautifully with progressive delivery and
  GitOps, providing tremendous control anywhere in the call graph.

<!-- @wait -->

- In addition to retries, Linkerd supports timeouts, circuit breaking, rate
  limiting, and egress controls.

<!-- @wait -->

- Linkerd has very powerful multicluster capabilities, as well as the ability
  to extend the mesh to non-Kubernetes workloads.

<!-- @wait -->

- Buoyant Enterprise for Linkerd includes the Buoyant Lifecycle Operator,
  which can automate the installation and management of Linkerd in a
  Kubernetes cluster, and of course extra capabilities for managing cross-zone
  traffic.

<!-- @wait -->

- BEL also includes policy generation tools to help with creating policy.

For more on all of these, check out https://buoyant.io/sma!

Finally, feedback is always welcome! You can reach me at flynn@buoyant.io or
as @flynn on the Linkerd Slack (https://slack.linkerd.io).

<!-- @wait -->
<!-- @show_slides -->
