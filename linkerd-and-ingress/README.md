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

<!-- @import demo-tools.sh -->
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
The instructions below are taken directly from that, with two differences:

1. We use `sed` to reduce the replica count from 3 to 1, to make things easier
   on the `k3d` cluster.

2. We use `linkerd inject` to bring Emissary into the Linkerd mesh from the
   moment of installation.

```bash
EMISSARY_CRDS=https://app.getambassador.io/yaml/emissary/3.1.0/emissary-crds.yaml
EMISSARY_INGRESS=https://app.getambassador.io/yaml/emissary/3.1.0/emissary-emissaryns.yaml

kubectl create namespace emissary && \
curl --proto '=https' --tlsv1.2 -sSfL $EMISSARY_CRDS | \
    sed -e 's/replicas: 3/replicas: 1/' | \
    kubectl apply -f -
kubectl wait --timeout=90s --for=condition=available deployment emissary-apiext -n emissary-system

curl --proto '=https' --tlsv1.2 -sSfL $EMISSARY_INGRESS | \
    sed -e 's/replicas: 3/replicas: 1/' | \
    linkerd inject - | \
    kubectl apply -f -
```

Let's also annotate Emissary to skip incoming ports 80 and 443, in case we
later want to use the client's incoming IP address:

```bash
kubectl annotate -n emissary deploy/emissary-ingress config.linkerd.io/skip-incoming-ports=80,443
```

Then we can wait for the deployments to be ready:

```bash
kubectl rollout status -n emissary deployments -lproduct=aes --timeout=30s
```

<!-- @clear -->

Now that Emissary-ingress is installed, let's quickly configure it. Emissary
is configured using its own CRDs: at minimum, it requires a `Listener`, a
`Host`, and one or more `Mapping`s to actually route traffic. We're not going
to dig to far into these, but we'll take a quick look:

```bash
less emissary-yaml/listeners-and-hosts.yaml
less emissary-yaml/emojivoto-mapping.yaml
```

We can install these resources with `kubectl apply`...

```bash
kubectl apply -f emissary-yaml
```

...and Emissary should be happy to route requests for us now.

<!-- @browser_then_terminal -->

If we look at the Linkerd Viz dashboard, we can see that Emissary is meshed,
and that it's talking to Emojivoto's web service.

```bash
linkerd viz dashboard
```

<!-- @clear -->

OK! Let's clean up Emissary-ingress to get ready for NGINX. First, scale
Emissary's deployment to 0, just to lighten the load on `k3d`.

```bash
kubectl scale -n emissary deploy/emissary-ingress --replicas=0
kubectl scale -n emissary deploy/emissary-ingress-agent --replicas=0
```

Next, delete the Service so that nothing is competing for the port we need to
use for NGINX.

```bash
kubectl delete svc -n emissary emissary-ingress
```

<!-- @wait_clear -->

## NGINX

Next up: NGINX, an open-source web server and API server that predates even
Kubernetes. You can read more about it at https://nginx.com/; its source is at
https://hg.nginx.org/nginx/.

We'll install NGINX using Helm, per the instructions at
https://docs.nginx.com/nginx-ingress-controller/installation/installation-with-helm/:

```bash
helm repo add nginx-stable https://helm.nginx.com/stable
helm repo update
helm install nginx nginx-stable/nginx-ingress
```

Once installed, we need to inject NGINX into the service mesh:

```bash
kubectl get deploy nginx-nginx-ingress -o yaml \
    | linkerd inject - \
    | kubectl apply -f -
```

For routing, NGINX uses an `Ingress` resource with the `nginx` `IngressClass`
(which was just installed by Helm):

```bash
less nginx-yaml/nginx-ingress.yaml
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

<!-- @clear -->

OK! Let's clean up NGINX by deleting its Helm installation.

```bash
helm delete nginx
```

<!-- @wait_clear -->

## Envoy Gateway

Finally, let's take a quick look at Envoy Gateway, a new open-source project
for managing Envoy Proxy as a standalone Kubernetes ingress controller, using
the Gateway API. Read more about Envoy Gateway at https://gateway.envoyproxy.io/;
its source is at https://github.com/envoyproxy/gateway.

We'll install Envoy Gateway using its quickstart, which you can find at
https://gateway.envoyproxy.io/v0.2.0/user/quickstart.html:

```bash
kubectl apply -f https://github.com/envoyproxy/gateway/releases/download/v0.2.0/install.yaml
kubectl wait --timeout=5m -n envoy-gateway-system deployment/envoy-gateway --for=condition=Available
```

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
kubectl rollout status -n envoy-gateway-system deployments --timeout=30s
```

OK! Now, finally, we can install the Gateway API resources needed to route to
Emojivoto:

```bash
less envoy-gateway-yaml/gateway.yaml
kubectl apply -f envoy-gateway-yaml/gateway.yaml
```

We should also wait for the Envoy Proxy deployment to be spun up:

```bash
kubectl rollout status -n envoy-gateway-system deployments --timeout=30s
```

At this point, Envoy Gateway should be able to route to Emojivoto for us.

<!-- @browser_then_terminal -->

And, as always, the Linkerd Viz dashboard should show that Envoy Gateway is
meshed, and that it's talking to Emojivoto's web service.

```bash
linkerd viz dashboard
```

<!-- @SHOW -->
<!-- @clear -->

So there you have it! Three separate ingress controllers, all working cleanly
with Linkerd!

You can find the source for this workshop at

https://github.com/BuoyantIO/service-mesh-academy/tree/main/linkerd-and-ingress

and, as always, we welcome feedback. Join us at https://slack.linkerd.io/ for
more.

<!-- @wait -->
<!-- @show_slides -->


