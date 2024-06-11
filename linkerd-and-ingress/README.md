<!--
SPDX-FileCopyrightText: 2024 Buoyant Inc.
SPDX-License-Identifier: Apache-2.0

SMA-Description: Using Linkerd with various ingress controllers
-->

# Linkerd and Ingress

This is the documentation - and executable code! - for the Service Mesh
Academy Ingress workshop. The easiest way to use this file is to execute it
with [demosh].

Things in Markdown comments are safe to ignore when reading this later. When
executing this with [demosh], things after the horizontal rule below (which
is just before a commented `@SHOW` directive) will get displayed.

[demosh]: https://github.com/BuoyantIO/demosh

This workshop requires that you have a running Kubernetes cluster. The README
is written assuming that you're using a local cluster that has ports exposed
to the local network: you can use [CREATE.md](CREATE.md) to set up a `k3d`
cluster that will work well. If you want to use some other kind of cluster,
make sure that the DNS is set up, and modify the DNS names to match for the
rest of the instructions.

<!-- @import check-requirements.sh -->
<!-- @start_livecast -->
---
<!-- @SHOW -->

In this workshop, we will deploy Linkerd to a cluster, then demonstrate three
different ingress controllers working with Linkerd:

- `Emissary-ingress` (https://getambassador.io/)
- `NGINX` (https://nginx.com/)
- `Envoy Gateway` (https://gateway.envoyproxy.io/)

All manifests used in the demo are in the `/manifests` directory, for some
additional work after the workshop, check out the homework assignment in
HOMEWORK.md.

First things first: make sure that everything is set up for the workshop.

```bash
#@$SHELL CREATE.md
#@$SHELL INSTALL-LINKERD.md
#@$SHELL INSTALL-EMOJIVOTO.md
```

OK, everything should be ready to go!

<!-- @wait_clear -->

## Emissary-ingress

We'll start with Emissary-ingress. Emissary is an open-source, Envoy-based,
Kubernetes-native API gateway. It's a CNCF incubating project; read more about
it at https://www.getambassador.io/products/api-gateway, or check out its
source at https://github.com/emissary-ingress/emissary.

The simplest way to install Emissary-ingress is to follow the quick start:
https://www.getambassador.io/docs/emissary/latest/tutorials/getting-started.
The instructions below are taken directly from that, except that we're setting
`replicaCount=1` to reduce the replice count from 3 to 1, to make things
easier on the `k3d` cluster. (You wouldn't want to do this in production!)

First we'll get our Helm repo set up...

```bash
helm repo add datawire https://app.getambassador.io
helm repo update
```

...then we can install Emissary's CRDs.

```bash
kubectl apply -f https://app.getambassador.io/yaml/emissary/3.9.1/emissary-crds.yaml
```

Installing the CRDs also installs the conversion webhook, so let's wait for
that.

```bash
kubectl rollout status -n emissary-system deploy
```

Once that's running, we create Emissary's namespace, including Linkerd's
auto-injection annotation, so that Emissary's Pods will automatically get
brought into the Linkerd mesh.

```bash
kubectl create ns emissary
kubectl annotate ns emissary linkerd.io/inject=enabled
```

Then it's time to install Emissary itself:

```bash
helm install emissary-ingress --namespace emissary \
     datawire/emissary-ingress \
     --set replicaCount=1
```

Then we can wait for the deployments to be ready:

```bash
kubectl rollout status -n emissary deployments
```

<!-- @wait_clear -->

Now that Emissary-ingress is installed, let's quickly configure it. Emissary
is configured using its own CRDs: at minimum, it requires a `Listener`, a
`Host`, and one or more `Mapping`s to actually route traffic. We're not going
to dig to far into these, but we'll take a quick look:

```bash
bat emissary-yaml/listeners-and-hosts.yaml
bat emissary-yaml/emojivoto-mapping.yaml
```

We can install these resources with `kubectl apply`...

```bash
kubectl apply -f emissary-yaml/listeners-and-hosts.yaml
kubectl apply -f emissary-yaml/emojivoto-mapping.yaml
```

...and Emissary should be happy to route requests for us now.

<!-- @browser_then_terminal -->

If we look at the Linkerd Viz dashboard, we can see that Emissary is meshed,
and that it's talking to Emojivoto's web service.

```bash
linkerd viz dashboard
```

<!-- @show_terminal -->
<!-- @clear -->

OK! Let's clean up Emissary-ingress to get ready for NGINX. First, we'll
delete the Service so that nothing is competing for the port we need to use
for NGINX.

```bash
kubectl delete svc -n emissary emissary-ingress
```

Then we'll summarily delete Emissary's namespaces.

```bash
kubectl delete ns emissary emissary-system
```

<!-- @clear -->

## NGINX

Next up: NGINX, an open-source web server and API server that predates even
Kubernetes. You can read more about it at https://nginx.com/; its source is at
https://hg.nginx.org/nginx/.

We'll install NGINX using Helm, per the instructions at
https://docs.nginx.com/nginx-ingress-controller/installation/installation-with-helm/:

```bash
helm repo add nginx-stable https://helm.nginx.com/stable
helm repo update
```

We're modifying the instructions slightly to use an `nginx` namespace, which
we've annotated for Linkerd injection.

```bash
kubectl create ns nginx
kubectl annotate ns nginx linkerd.io/inject=enabled
helm install nginx \
     -n nginx \
     nginx-stable/nginx-ingress
```

Once installed, let's make sure everything is running.

```bash
kubectl rollout status -n nginx deploy
```

For routing, NGINX uses an `Ingress` resource with the `nginx` `IngressClass`
(which was just installed by Helm):

```bash
bat nginx-yaml/nginx-ingress.yaml
```

Applying it with `kubectl apply` should cause NGINX to route requests to
Emojivoto.

```bash
kubectl apply -f nginx-yaml/nginx-ingress.yaml
```

Let's check that in the browser.

<!-- @browser_then_terminal -->

In the Linkerd Viz dashboard, we'll now see that NGINX is meshed, and that
it's talking to Emojivoto's web service.

```bash
linkerd viz dashboard
```

<!-- @show_terminal -->
<!-- @clear -->

OK! Let's clean up NGINX the same way we dealt with Emissary.

```bash
kubectl delete svc -n nginx nginx-nginx-ingress-controller
kubectl delete ns nginx
```

<!-- @clear -->

## Envoy Gateway

Finally, let's take a quick look at Envoy Gateway, a new open-source project
for managing Envoy Proxy as a standalone Kubernetes ingress controller, using
the Gateway API. Read more about Envoy Gateway at https://gateway.envoyproxy.io/;
its source is at https://github.com/envoyproxy/gateway.

We'll install Envoy Gateway using its quickstart, which you can find at
https://gateway.envoyproxy.io/v0.6.0/user/quickstart.html:

```bash
kubectl apply -f https://github.com/envoyproxy/gateway/releases/download/v0.6.0/install.yaml
kubectl wait --timeout=5m -n envoy-gateway-system deployment/envoy-gateway --for=condition=Available
```

OK, we should be good to go!

<!-- @wait_clear -->

Envoy Gateway uses the Gateway API's `Gateway` resource to define which port
to listen on, etc., and `HTTPRoute` resources to define how requests will get
routed. The interesting thing, though, is that when the `Gateway` resource is
created or edited, Envoy Gateway will create a new Deployment, in the
`envoy-gateway-system` namespace, for the actual Envoy Proxy itself. Since
these Deployments are dynamic, we need to tell Linkerd to do automatic
injection on the entire `envoy-gateway-system` namespace:

```bash
kubectl annotate ns envoy-gateway-system linkerd.io/inject=enabled
```

After doing that, we'll need to restart the running Envoy Gateway controller:

```bash
kubectl rollout restart -n envoy-gateway-system deployments
kubectl rollout status -n envoy-gateway-system deployments
```

OK! Now, finally, we can install the Gateway API resources needed to route to
Emojivoto:

```bash
bat envoy-gateway-yaml/gateway.yaml
kubectl apply -f envoy-gateway-yaml/gateway.yaml
```

We should also wait for the Envoy Proxy deployment to be spun up:

```bash
kubectl rollout status -n envoy-gateway-system deployments
```

At this point, Envoy Gateway should be able to route to Emojivoto for us.

<!-- @browser_then_terminal -->

And, as always, the Linkerd Viz dashboard should show that Envoy Gateway is
meshed, and that it's talking to Emojivoto's web service.

```bash
linkerd viz dashboard
```

<!-- @show_terminal -->
<!-- @clear -->

So there you have it! Three separate ingress controllers, all working cleanly
with Linkerd!

You can find the source for this workshop at

https://github.com/BuoyantIO/service-mesh-academy/tree/main/linkerd-and-ingress

and, as always, we welcome feedback. Join us at https://slack.linkerd.io/ for
more.

<!-- @wait -->
<!-- @show_slides -->


