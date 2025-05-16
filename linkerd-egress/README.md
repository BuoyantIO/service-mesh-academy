<!--
SPDX-FileCopyrightText: 2024 Buoyant Inc.
SPDX-License-Identifier: Apache-2.0

SMA-Description: Linkerd Egress and Routing
-->

# Linkerd Egress and Routing

This is the documentation - and executable code! - for the Service Mesh
Academy Egress and Routing workshop, which draws heavily from the "One Gateway
API to Rule Them All" talk from KubeCon NA 2024. Things in Markdown comments
are safe to ignore when reading this later.

The simplest way to use this file is:

1. Run `init.sh` to initialize your environment. Make sure that the cluster's
   DNS can resolve `smiley` and `color` to the IP addresses of the Docker
   containers running the `smiley` and `color` workloads -- if you use
   Orbstack, this should happen automatically, but if not you might need to
   mess with some other things.

2. Run `python metrics.py` in another window to watch egress metrics.

3. Use [demosh] to execute this file.

When executing this with [demosh], things after the horizontal rule below
(which is just before a commented `@SHOW` directive) will get displayed.

[demosh]: https://github.com/BuoyantIO/demosh

The README is written assuming that you've set up your local environment using
the `init.sh` script -- this is important, since the setup is pretty involved!
In particular, the cluster's DNS _must_ be able to resolve `smiley` and
`color` to the IP addresses of the Docker containers running the `smiley` and
`color` workloads.

<!-- @clear -->
<!-- @SHOW -->

# Linkerd and Egress

In this workshop, we're going to take a look at how Linkerd's egress controls
work, and (a bit) at how Gateway API can be used for ingress, mesh routing,
and egress. To show all this, we have a cluster set up with Envoy Gateway for
ingress, Linkerd for a mesh, and the Faces demo application.

However, we're doing things kind of differently than we normally do. The Faces
demo requires four workloads running in concert, named `faces-gui`, `face`,
`smiley`, and `color`, but instead of running them all in our cluster, we have
`smiley` and `color` running as Docker containers _outside_ our cluster:

```bash
kubectl get ns
docker ps | grep smiley
docker ps | grep color
```

We've deliberately connected these two containers to a Docker container called
`egress`:

```bash
docker inspect smiley | jq -r '.[0].NetworkSettings.Networks | keys | .[]'
docker inspect color | jq -r '.[0].NetworkSettings.Networks | keys | .[]'
```

We've also connected our cluster to `egress` -- but even that is set up
carefully!

```bash
docker inspect k3d-oneapi-server-0 | jq -r '.[0].NetworkSettings.Networks | keys | .[]'
```

The main network for the `oneapi` cluster is `k3d-oneapi`, but we've _also_
connected the cluster to `egress` -- technically this is a multinetwork
cluster. This is critical because for egress controls to work, egress traffic
_must_ use a CIDR range different from the cluster's internal network.

We can see that Linkerd is running OK.

```bash
linkerd check --proxy
```

We can see that we have a Gateway set up for Envoy Gateway.

```bash
kubectl get -n default gateway ingress
```

We can see the IP address for the Gateway, but since we're running on k3d,
we've just set up port forwarding on localhost port 80 -- so we should be able
to open `http://localhost/gui` in a browser and see the Faces demo
application!

<!-- @browser_then_terminal -->

## Ingress Routing

Well... that didn't work. The reason is that while we have a Gateway, we don't
yet have any ingress routes. We need two:

- `/gui` should go to the `faces-gui` workload
- `/face` should go to the `face` workload

These are all in the `faces` namespace. Here's the one for `/face`:

```bash
bat k8s/face-route.yaml
```

The one for `/gui` is similar enough that we won't take the time to look at
it. Let's get them both applied and then head back to the browser.

```bash
kubectl apply -f k8s/gui-route.yaml
kubectl apply -f k8s/face-route.yaml
```

<!-- @browser_then_terminal -->

## And Now, Egress!

We're going to skip mesh routing for a moment and poke at egress a bit.

Recall that the `smiley` and `color` workloads are both running outside the
cluster, meaning that calls to them are egress traffic. Right now, they're
both allowed, but also unmonitored:

```bash
linkerd dg proxy-metrics -n faces deploy/face \
  | grep outbound_http_route_request_statuses_total \
  | grep Egress
```

Let's start by monitoring them.

```bash
bat k8s/allow-all-egress.yaml
kubectl apply -f k8s/allow-all-egress.yaml
```

If we repeat that `linkerd dg` command, we should see that we're now getting
metrics for the egress traffic.

```bash
linkerd dg proxy-metrics -n faces deploy/face \
  | grep outbound_http_route_request_statuses_total \
  | grep Egress
```

Obviously this is painful to read, so we have a simple monitoring program
running in another window -- and you'll note that it just started showing us
things. (We could use Prometheus and Grafana for this, too, I'm just showing
off that you can do it by hand.)

<!-- @wait_clear -->

## Blocking Egress

OK, we have monitoring for our working application! Time to break things.
We'll create an EgressNetwork to block _all_ egress traffic.

```bash
bat k8s/deny-all-egress.yaml
kubectl apply -f k8s/deny-all-egress.yaml
```

As soon as we apply that, we see that the GUI shows us everything broken
again.

<!-- @wait_clear -->

## Allowing `smiley` Requests

The `face` workload uses HTTP to talk to `smiley` -- specifically, it makes
requests to `http://smiley/center` and `http://smiley/edge`. Let's allow all
of that traffic to start with.

```bash
bat k8s/allow-smiley-all.yaml
kubectl apply -f k8s/allow-smiley-all.yaml
```

That gets our grinning faces back! On to the backgrounds.

<!-- @wait_clear -->

## Allowing `color` Requests

The `face` workload uses gRPC to talk to `color`, using the `ColorService`
service and the `Center` and `Edge` methods. Let's allow all of that traffic
using a gRPC service match rather than a hostname match, just for variety.

```bash
bat k8s/allow-color-all.yaml
kubectl apply -f k8s/allow-color-all.yaml
```

And now we have blue backgrounds again.

<!-- @wait_clear -->

## More Restrictions

There's a lot more that can be done here. We're not going to go too far down
the rabbit hole, but just as a quick example, let's allow just traffic to the
edge cells -- this means Path matching for the HTTPRoute and Method matching
for the gRPCRoute.

```bash
bat k8s/allow-edge.yaml
kubectl apply -f k8s/allow-edge.yaml
```

Once that hits the system, our central cells are back to cursing faces on grey
backgrounds.

<!-- @wait_clear -->

## Using an Egress Controller

So far, our egress routes have simply allowed egress traffic directly out of
the cluster, but we can also use an egress controller. Since purpose-built
egress controllers are still a bit thin on the ground, we're going to abuse
Envoy Gateway for the moment.

We already have this Gateway set up:

```bash
kubectl get -n default gateway egress
```

and we configured it so that its Service is called `egress-svc`, so that we
know how to route to it.

```bash
kubectl get -n envoy-gateway-system service egress-svc
```

Let's force the center cells through the egress controller.

```bash
bat k8s/allow-center-egress-controller.yaml
kubectl apply -f k8s/allow-center-egress-controller.yaml
```

Of course, to actually have that do anything, we need to set up routes for our
egress controller! So that we can see a difference, we'll use the egress
controller to route to `smiley2`, which returns a heart-eyes smiley, and
`color2`, which returns green. (A small confession: these are both running in
the cluster, but we're going to pretend they're outside.)

```bash
bat k8s/egress-routes.yaml
kubectl apply -f k8s/egress-routes.yaml
```

And now we have heart-eyes on green backgrounds in the center cells!

<!-- @wait_clear -->

## One More Thing

We're going to wrap up by using mesh routing to just completely bypass all
this egress madness.

Our `face` workload is the thing that's fielding requests from the GUI; it
does so by making requests, in turn, to `smiley` and `color`. But we also have
a `face2` workload running, which is configured to talk to `smiley3` and
`color3`, which are both in the cluster.

```bash
kubectl get service,deploy -n faces face2
```

Our ingress Gateway is sending all requests from the GUI to the `face` Service
-- so we'll tell the mesh to route all requests to `face` over to `face2`
instead. (We could tell the Gateway to do this, too! since it's right at the
edge of the call graph -- but mesh routing is the thing we haven't demoed
yet!)

```bash
bat k8s/face2-direct.yaml
kubectl apply -f k8s/face2-direct.yaml
```

The moment that Route goes in, we see rolling eyes on blue backgrounds.

<!-- @wait_clear -->

## One API to Rule Them All

And that's our whirlwind tour of Gateway API for ingress, mesh, and egress!
There is a **lot** more that we could show here, of course, but these are the
quick highlights.

<!-- @wait -->
