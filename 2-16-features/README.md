<!--
SPDX-FileCopyrightText: 2024 Buoyant Inc.
SPDX-License-Identifier: Apache-2.0

SMA-Description: Exploring new features in Linkerd 2.16
-->

# Linkerd 2.16 Features

This is the documentation - and executable code! - for the Service Mesh
Academy workshop about new features in Linkerd 2.16. The easiest way to use
this file is to execute it with [demosh].

Things in Markdown comments are safe to ignore when reading this later. When
executing this with [demosh], things after the horizontal rule below (which
is just before a commented `@SHOW` directive) will get displayed.

[demosh]: https://github.com/BuoyantIO/demosh

This workshop WILL DESTROY any running k3d cluster named `mesh-exp`, and any
Docker containers named `dnsmasq`, `smiley-1`, and `color-1` as well. Be
careful!

When you use `demosh` to run this file, requirements will be checked for
you.

<!-- set -e >
<!-- @import demosh/check-requirements.sh -->

<!-- @start_livecast -->

```bash
BAT_STYLE="grid,numbers"
WORKLOAD_IMAGE_TAG=1.4.1
```

---
<!-- @SHOW -->

# New Linkerd 2.16 features!

In this workshop, we'll explore some of the new features in Linkerd 2.16,
notably including:

- Support for IPv6
- Authorization policy "audit mode"
- Support for Gateway API gRPCRoute
- Timeouts and retries for HTTPRoute and gRPCRoute

# IPv6

First things first: IPv6 support in Linkerd 2.16! This has been around in edge
releases for some time, but 2.16 is its first appearance in a stable release.

<!-- @wait -->

There's weirdly little to show here, but check it out:

```bash
kubectl get svc -n faces
```

You can see that in fact I'm running on a dualstack cluster, that my Services
mostly have IPv6 addresses... and everything Just Works, as we can see if we
flip to a browser:

<!-- @browser_then_terminal -->

The Fine Print:

- This is a `kind` cluster. `k3d` doesn't yet support IPv6.

<!-- @wait -->

- `kind` doesn't have native loadbalancer support, so I'm also using MetalLB
  so that I can use Services of type LoadBalancer... and I'm using the IPv4
  load balancer address to show off the automagic dual-stack support and
  address-family translation in Linkerd.

<!-- @wait -->

- In the interests of time, I'm not showing how the cluster is set up -- for
  all the gory details, check out the `setup.sh` script in the workshop repo,
  or check out our IPv6 Service Mesh Academy workshop:

  https://buoyant.io/service-mesh-academy/ipv6-with-linkerd-future-proofing-your-network

<!-- @wait_clear -->

# External Workload Automation

Next up we'll show off some automation features in 2.16 that make it _much_
easier to work with external workloads. We'll head back to the IPv4 world for
this (keep an eye out for dualstack external workloads in a later Linkerd
release!).

<!-- @wait -->

We're going to have a k3d cluster running the Linkerd control plane with an
in-cluster workload, then we'll have multiple VMs running _outside_ the
cluster (but connected to the same Docker network). Let's start by getting our
cluster running, connected to the `mesh-exp` Docker network.

```bash
#@immed
k3d cluster delete mesh-exp >/dev/null 2>&1

k3d cluster create mesh-exp \
    --network=mesh-exp \
    --port 80:80@loadbalancer \
    --port 443:443@loadbalancer \
    --k3s-arg '--disable=traefik,metrics-server@server:0'
```

Once that's done, let's get Linkerd up and running. Since we're showing off
the external workload automation feature for this, you'll need a free Buoyant
account for this. If you don't already have an account, hit up
https://enterprise.buoyant.io to get one.

Once that's done and you've set the environment variables it'll tell you
about, it's time to make sure we have the right version of Linkerd installed!

```bash
curl --proto '=https' --tlsv1.2 -sSfL https://enterprise.buoyant.io/install | \
    LINKERD2_VERSION=enterprise-2.16.0 sh
linkerd version --proxy --client --short
```

Once that's done, we install Linkerd's CRDs, being careful to tell Linkerd
that we want to manage external workloads -- if you forget that `--set`,
you'll end up missing the crucial ExternalGroup resource, so make sure it's
there.

```bash
linkerd install --crds --set manageExternalWorkloads=true | kubectl apply -f -
```

After that we install Linkerd itself. Note that we're explicitly specifying
the trust anchor and identity issuer certificate -- these are certs that I
generated earlier and have stored locally, which is important because we'll
need to use those certificates for identity in our external workloads.

```bash
linkerd install \
    --identity-trust-anchors-file ./certs/ca.crt \
    --identity-issuer-certificate-file ./certs/issuer.crt \
    --identity-issuer-key-file ./certs/issuer.key \
    --set manageExternalWorkloads=true \
    --set disableIPv6=false \
  | kubectl apply -f -
linkerd check
```

<!-- @wait_clear -->

## Starting the Kubernetes Workload

OK! Now that we have Linkerd running in our cluster, let's get an application
running there too. We're going to use our usual Faces demo for this, so let's
start by just installing it using its Helm chart.

First, we'll set up the `faces` namespace, with Linkerd injection for the
whole namespace...

```bash
kubectl create namespace faces
kubectl annotate namespace faces linkerd.io/inject=enabled
```

...and then we'll install the Faces demo itself. We'll tell the chart to make
the GUI service a LoadBalancer, to make it easy to talk to, and we'll also
tell it to make the workloads error-free -- for now...

```bash
helm install faces -n faces \
     oci://ghcr.io/buoyantio/faces-chart --version 1.4.1 \
     --set gui.serviceType=LoadBalancer \
     --set color2.enabled=true \
     --set color2.color=green \
     --set face.errorFraction=0 \
     --set backend.errorFraction=0
```

We'll wait for our Pods to be running before we move on.

```bash
kubectl rollout status -n faces deploy
kubectl get pods -n faces
kubectl get svc -n faces
```

OK! If we flip over to look at the GUI right now (using the IP address shown
for the `faces-gui` Service), we should see grinning faces on blue
backgrounds.

<!-- @browser_then_terminal -->

## On to the Edge

So this is all well and good, but it's also not very interesting because it's
just running a Kubernetes application. Let's change that. We'll run the
`smiley` and `color` workloads outside the cluster, but still using Linkerd
for secure communications.

Let's start by ditching those workloads in Kubernetes.

```bash
kubectl delete -n faces deploy smiley color
```

If we flip over to look now, we'll see endless cursing faces on grey
backgrounds, since the `face` workload is responding, but `smiley` and `color`
are not. Let's fix that.

<!-- @browser_then_terminal -->

## External Workload Requirements

OK, first things first: what needs to happen to get an external workload
hooked up with Linkerd? At a VERY high level:

1. Our external workload needs to be on a machine with direct IP access to the
   Pod and Service IP ranges of the cluster.

2. Our external workload needs to have access to the Kubernetes DNS, so that
   workloads can talk to other workloads (and so that we can use a DNS name to
   refer to the control plane!).

3. Our external workload needs a SPIFFE identity so that the Linkerd proxy
   knows that it's safe.

4. Our external workload needs to run the Linkerd proxy next to it, just like
   we do in Kubernetes.

5. New for BEL and the autoregistration harness, we need an ExternalGroup
   resource in the cluster, so that the autoregistration harness can manage
   ExternalWorkload resources for us! just like Deployments and Pods.

SO. Let's get started on this.

<!-- @wait_clear -->

## Routing

We'll start with routing. Our external workloads will be running in containers
attached to the same network as our k3d cluster, but they still need to be
explicitly told how to route to the cluster. Specifically, we're going to run
`ip route add` in our containers to tell them to route to the Pod and Service
CIDRs via the Node's IP. We can get the Node's IP and the Pod CIDR from
Kubernetes itself:

```bash
NODE_IP=$(kubectl get nodes  -ojsonpath='{.items[0].status.addresses[0].address}')
#@immed
echo "NODE_IP is ${NODE_IP}"
POD_CIDR=$(kubectl get nodes  -ojsonpath='{.items[0].spec.podCIDR}')
#@immed
echo "POD_CIDR is ${POD_CIDR}"
```

...but we can't get the Service CIDR, weirdly. So we'll just hardcode that;
be aware that you might need to change this if your cluster is weirder than
ours.

```bash
export SVC_CIDR="10.43.0.0/16"
```

<!-- @wait_clear -->

## DNS

We're going to tackle DNS by first editing the `kube-dns` Service to make it a
NodePort on UDP port 30000, so we can talk to it from our Node, then running
`dnsmasq` as a separate Docker container to forward DNS requests for cluster
Services to the `kube-dns` Service.

This isn't a perfect way to tackle this in production, but it's not completely
awful: we probably don't want to completely expose the cluster's DNS to the
outside world. So, first we'll switch `kube-dns` to a NodePort:

```bash
kubectl edit -n kube-system svc kube-dns
kubectl get -n kube-system svc kube-dns
```

...and then we'll fire up `dnsmasq` in a container using the
`drpsychick/dnsmasq` image, volume mounting a custom entrypoint script:

```bash
bat bin/dns-forwarder.sh
#@immed
docker kill dnsmasq >/dev/null 2>&1
#@immed
docker rm dnsmasq >/dev/null 2>&1

docker run --detach --rm --cap-add NET_ADMIN --net=mesh-exp \
       -v $(pwd)/bin/dns-forwarder.sh:/usr/local/bin/dns-forwarder.sh \
       --entrypoint sh \
       -e DNS_HOST=${NODE_IP} \
       --name dnsmasq drpsychick/dnsmasq \
       -c /usr/local/bin/dns-forwarder.sh
```

Once that's done, we can get the IP address of the `dnsmasq` container to use
later.

```bash
DNS_IP=$(docker inspect dnsmasq | jq -r '.[].NetworkSettings.Networks["mesh-exp"].IPAddress')
#@immed
echo "DNS_IP is ${DNS_IP}"
```

<!-- @wait_clear -->

## SPIFFE

This is the most horrible bit in this demo. The way you manage SPIFFE
identities is that you run a SPIRE agent, which talks to a SPIRE server. The
agent is given some information to prove which entity it belongs to (a process
called _attestation_), and in turn the server provides the SPIFFE identity
itself.

For this demo, we're just going to run an agent and a server in every workload
container, mounting the Linkerd trust anchor into our container for the SPIRE
server to use.

**This is a terrible idea in the real world. Don't do this.** But, since this
is not a SPIRE attestation demo, it's what we're going to do.

We have this baked into our Docker image as a script called `bootstrap-spire`:

```bash
bat -l bash bin/bootstrap-spire
```

<!-- @wait_clear -->

## The Linkerd Proxy

Finally, we need to run the Linkerd proxy for our external workloads... and
this is where the autoregistration harness really shines. The harness is a new
feature in BEL that manages both the nuts and bolts of managing iptables and
running the proxy, and _also_ talks to the autoregistration controller to
manage ExternalWorkload resources for us.

- The harness itself ships as a Debian or RPM package.
- You install it on your external workload machine (or container, in our case).
- It provides a `systemd` resource that knows how to handle iptables and the
  proxy for you(!!).

The autoregistration system _requires_ an ExternalGroup resource to be present in
the cluster, so that it can know how to create ExternalWorkload resources!

<!-- @wait_clear -->

### The `demo-bel-external-base` and `faces-bel-external-workload` Images

`ghcr.io/buoyantio/demo-bel-external-base` is a Docker image built in this
directory, to serve as a base for external workloads that use the BEL
autoregistration harness. It contains the harness package, the SPIRE agent,
the SPIRE server, and the BEL bootstrap script, which is honestly really
simple:

```bash
bat -l bash bin/bootstrap-bel
```

It just installs the harness, bootstraps SPIRE as we saw before, then starts
the workload itself.

Of course, that assumes that there's a workload present! For this demo, we've
taken the `demo-bel-external-workload` image and built an image on top of it
that includes the Faces workload. This is the `faces-bel-external-workload`
image, `ghcr.io/buoyantio/faces-bel-external-workload:${WORKLOAD_IMAGE_TAG}`.
It is _literally_ the `demo-bel-external-workload` image with the Faces
workload copied into `/workload/start`.

<!-- @wait_clear -->

## Starting the External Workloads

So let's actually get some external workloads running, starting with the
`smiley` workload. First things first: we need an ExternalGroup resource for
it!

```bash
bat bel/smiley-group.yaml
kubectl apply -f bel/smiley-group.yaml
```

This won't do anything yet, because we don't have any external workloads
registering. So. Onward!

<!-- @wait_clear -->

## Starting the `smiley-1` Workload

Now that we have an ExternalGroup, we'll fire up the `smiley` workload in a
container called `smiley-1`. we'll start the `smiley` workload in a container
called `smiley-1` (and we'll set its hostname so that the GUI can show it if
we want to.)

The `WORKLOAD_NAME` is critical here: it's how the autoregistration harness
knows which ExternalGroup to connect this workload to.

```bash
#@immed
docker kill smiley-1 >/dev/null 2>&1
#@immed
docker rm smiley-1 >/dev/null 2>&1
docker run --rm --detach \
       --cap-add=NET_ADMIN \
       --network=mesh-exp \
       --dns=${DNS_IP} \
       --name=smiley-1 \
       --hostname=smiley-docker-ext1 \
       -v "$(pwd)/certs:/opt/spire/certs" \
       -e WORKLOAD_NAME=smiley \
       -e WORKLOAD_NAMESPACE=faces \
       -e NODE_NAME='$(hostname)' \
       -e POD_CIDR=${POD_CIDR} \
       -e SVC_CIDR=${SVC_CIDR} \
       -e NODE_IP=${NODE_IP} \
       -e FACES_SERVICE=smiley \
       -e DELAY_BUCKETS=0,50,100,200,500,1000 \
       ghcr.io/buoyantio/faces-bel-external-workload:${WORKLOAD_IMAGE_TAG}
```

<!-- @wait_clear -->

## ExternalWorkloads!

Once we have that running, we should see an ExternalWorkload - and some
endpoints - appear for it... and when that happens, the GUI should show some
differences!

<!-- @show_5 -->

```bash
watch 'sh -c "kubectl get externalworkloads -n faces; linkerd dg endpoints smiley.faces.svc.cluster.local"'
```

<!-- @clear -->
<!-- @show_terminal -->

## The Smiley Workload

At this point we have grinning faces on grey backgrounds, because `smiley` is
now responding -- but of course, there's still no `color` workload. So let's
fix that, by doing exactly the same thing for `color` workload as we just did
for `smiley`. First, let's get its ExternalGroup set up:

```bash
bat bel/color-group.yaml
kubectl apply -f bel/color-group.yaml
```

...and then we'll start the `color` workload in a container called `color-1`.

```bash
#@immed
docker kill color-1 >/dev/null 2>&1
#@immed
docker rm color-1 >/dev/null 2>&1
docker run --rm --detach \
       --cap-add=NET_ADMIN \
       --network=mesh-exp \
       --dns=${DNS_IP} \
       --name=color-1 \
       --hostname=color-docker-ext1 \
       -v "$(pwd)/certs:/opt/spire/certs" \
       -e WORKLOAD_NAME=color \
       -e WORKLOAD_NAMESPACE=faces \
       -e NODE_NAME='$(hostname)' \
       -e POD_CIDR=${POD_CIDR} \
       -e SVC_CIDR=${SVC_CIDR} \
       -e NODE_IP=${NODE_IP} \
       -e FACES_SERVICE=color \
       -e DELAY_BUCKETS=0,50,100,200,500,1000 \
       ghcr.io/buoyantio/faces-bel-external-workload:${WORKLOAD_IMAGE_TAG}
```

<!-- @wait_clear -->

## ExternalWorkloads!

Once again, we should see things happen here!

<!-- @show_5 -->

```bash
watch 'sh -c "kubectl get externalworkloads -n faces; linkerd dg endpoints color.faces.svc.cluster.local"'
```

<!-- @clear -->
<!-- @show_terminal -->

## ExternalWorkloads and EndpointSlices

ExternalWorkloads end up defining EndpointSlices, too:

```bash
kubectl get endpointslices -n faces
```

You can see that there are a "normal" slices for both `smiley` and `color`,
created by the usual Kubernetes EndpointSlice controller, with no Endpoints --
this is because the Kubernetes EndpointSlice controller doesn't know about our
ExternalWorkloads. But there are also slices created by the Linkerd
EndpointSlice controller, which _does_ know about our ExternalWorkloads, so it
has the correct external workload IP addresses.

<!-- @wait_clear -->

## Level Up

So! this is well and good. Suppose we want to do more?

<!-- @wait -->

For starters, if you look closely, you'll realize that we're actually just
slotting ExternalWorkloads into the existing Service/Deployment/Pod paradigm:

- ExternalGroups are like Deployments; where Deployments cause Pods to be
  created, ExternalGroups cause ExternalWorkloads to be created.

- Services effectively select across Pods and ExternalWorkloads, because the
  Linkerd ExternalWorkload EndpointSlice controller creates EndpointSlices
  that Services can use.

<!-- @wait -->

So let's take a look at what happens if we create another external workload
called `smiley2`, which returns heart-eyed smileys but fails 25% of the time.
Note that this time we're _also_ setting up a new Service, `smiley2`, rather
than just using the labels from the `smiley` Service.

```bash
bat bel/smiley2.yaml
kubectl apply -f bel/smiley2.yaml

#@immed
docker kill smiley2-1 >/dev/null 2>&1
#@immed
docker rm smiley2-1 >/dev/null 2>&1
docker run --rm --detach \
       --cap-add=NET_ADMIN \
       --network=mesh-exp \
       --dns=${DNS_IP} \
       --name=smiley2-1 \
       --hostname=smiley2-docker-ext1 \
       -v "$(pwd)/certs:/opt/spire/certs" \
       -e WORKLOAD_NAME=smiley2 \
       -e WORKLOAD_NAMESPACE=faces \
       -e NODE_NAME='$(hostname)' \
       -e POD_CIDR=${POD_CIDR} \
       -e SVC_CIDR=${SVC_CIDR} \
       -e NODE_IP=${NODE_IP} \
       -e FACES_SERVICE=smiley \
       -e SMILEY=HeartEyes \
       -e ERROR_FRACTION=25 \
       -e DELAY_BUCKETS=0,50,100,200,500,1000 \
       ghcr.io/buoyantio/faces-bel-external-workload:${WORKLOAD_IMAGE_TAG}
```

<!-- @show_5 -->

As usual, we're expecting to see endpoints and such appear...

```bash
watch 'sh -c "kubectl get externalworkloads -n faces; linkerd dg endpoints smiley2.faces.svc.cluster.local"'
```

Note that we see the usual grinning faces, with no heart-eyed smileys yet...
but we can change that with an HTTPRoute!

```bash
bat bel/smiley-route.yaml
kubectl apply -f bel/smiley-route.yaml
```

(For some reason this can take a little while to take effect.
Just give it a minute or so.)

<!-- @show_5 -->
<!-- @wait -->

The fact that the workloads are external doesn't affect how Linkerd can work
with them. Also... we have metrics now.

<!-- @wait_clear -->
<!-- @show_terminal -->

# Per-Route Metrics with Gateway API

In Linkerd 2.16 we have per-route metrics for HTTP and gRPC routes, which is
pretty cool. We'll start with a look at HTTPRoute metrics.

One limitation of this, at the moment, is that the Linkerd core publishes
metrics, but Linkerd Viz doesn't know how to display them. There's some cool
stuff coming up in a future Linkerd release here, but for now, though, we'll
just look at things with the `linkerd diagnostics proxy-metrics` command.

`proxy-metrics` needs a pod name to work with, so we'll grab the name of the
`face` pod:

```bash
FACEPOD=$(kubectl get pods -n faces -l 'service=face' \
              -o jsonpath='{ .items[0].metadata.name }')
#@print "# Found face pod ${FACEPOD}"
```

Given that, we can now run `proxy-metrics` to see all the metrics for that
pod:

```bash
linkerd diagnostics proxy-metrics -n faces pod/${FACEPOD} | more
```

<!-- @clear -->

OK... that's a lot! We do a _lot_ more digging into all the metrics we have
available in the "Metrics, Dashboards, and Charts, Oh My!" Service Mesh
Academy workshop:

https://buoyant.io/service-mesh-academy/metrics-dashboards-and-charts-oh-my

but we're just going to cut to the chase right now: the metric called
`outbound_http_route_backend_response_statuses_total` will give us a breakdown
of how things went, broken down by HTTPRoute `backendRef`:

```bash
linkerd diagnostics proxy-metrics -n faces pod/${FACEPOD} \
    | grep outbound_http_route_backend_response_statuses_total \
    | more
```

<!-- @clear -->

Even that's a lot, so let's _just_ look at the first two:

```bash
linkerd diagnostics proxy-metrics -n faces pod/${FACEPOD} \
    | grep outbound_http_route_backend_response_statuses_total \
    | head -2 | sed -e 's/,/\n/g'
```

...and that, in turn, gives us a way to look just at outbound errors from the
`face` Pod to our `smiley-edge` route:


```bash
linkerd diagnostics proxy-metrics -n faces pod/${FACEPOD} \
    | grep outbound_http_route_backend_response_statuses_total \
    | grep 'route_name="smiley-edge"' \
    | grep -v 'http_status="200"' | sed -e 's/,/\n/g'
```

Do that twice, we can get a sense of the error rate:

```bash
linkerd diagnostics proxy-metrics -n faces pod/${FACEPOD} \
    | grep outbound_http_route_backend_response_statuses_total \
    | grep 'route_name="smiley-edge"' \
    | grep -v 'http_status="200"' | sed -e 's/,/\n/g' && \
sleep 10 && \
linkerd diagnostics proxy-metrics -n faces pod/${FACEPOD} \
    | grep outbound_http_route_backend_response_statuses_total \
    | grep 'route_name="smiley-edge"' \
    | grep -v 'http_status="200"' | sed -e 's/,/\n/g'
```

As primitive as it seems, this is how tools like Linkerd Viz and Grafana work
under the hood -- for more, again, check out the "Metrics, Dashboards, and
Charts, Oh My!" workshop.

<!-- @wait_clear -->

# Retries

Let's see if we can make the cursing faces go away. Back in the Linkerd 2.15
days, the only way to do this was to use a ServiceProfile... but now we can
just annotate our HTTPRoute.

<!-- @show_5 -->

```bash
kubectl annotate -n faces httproute smiley-edge  \
    retry.linkerd.io/http=5xx \
    retry.linkerd.io/limit=3
```

and there should be _dramatically_ fewer cursing faces.

<!-- @wait_clear -->
<!-- @show_terminal -->

We also have metrics for retries - under `outbound_http_route_retry_*` - so we
can see if retries are in play:

```bash
linkerd diagnostics proxy-metrics -n faces pod/${FACEPOD} \
    | grep outbound_http_route_retry | head
```

Note that we have the `route_name` in the metric, so we can look at retries
only for our `smiley-edge` route:

```bash
linkerd diagnostics proxy-metrics -n faces pod/${FACEPOD} \
    | grep outbound_http_route_retry \
    | grep 'route_name="smiley-edge"'
```

That's a little unwieldy to read, so let's pare that down to just the basics:

```bash
linkerd diagnostics proxy-metrics -n faces pod/${FACEPOD} \
    | grep outbound_http_route_retry \
    | grep 'route_name="smiley-edge"' \
    | sed -e 's/{.*}//'
```

Much better. We can see:

- `outbound_http_route_retry_requests_total`: lots of things are being retried
- `outbound_http_route_retry_successes_total`: most of the retries are succeeding
- `outbound_http_route_retry_limit_exceeded_total`: rather few are hitting the limit

And `outbound_http_route_retry_overflow_total` is zero, which tells us that
circuit breaking isn't in play here.

<!-- @wait_clear -->
<!-- @show_5 -->

# Timeouts

Our smiley faces look better now, but some of the cells are still fading away
because things are taking too long.

<!-- @wait -->

Let's see about making that better with a timeout.

We'll start with a 300ms timeout on the `color` Service itself --
yes, the Service, Linkerd 2.16's annotation-based timeouts can go
on Routes or on Services.

```bash
kubectl annotate -n faces service/color \
    timeout.linkerd.io/request=300ms
```

Immediately, we start seeing some cells with pink backgrounds,
because that's what happens when `face` gets a timeout from
`color`.

<!-- @wait_clear -->

We can continue this by adding a timeout to the `smiley-edge`
HTTPRoute:

```bash
kubectl annotate -n faces httproute/smiley-edge \
    timeout.linkerd.io/request=300ms
```

and now you'll start seeing sleeping faces, but only around the
edge of the grid.

<!-- @wait_clear -->
<!-- @show_terminal -->

# GRPCRoute

Let's continue by looking at GRPCRoute. For that, we'll install the
`emojivoto` demo app:

```bash
kubectl create ns emojivoto
kubectl annotate ns emojivoto linkerd.io/inject=enabled
curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/emojivoto.yml \
  | kubectl apply -f -
kubectl rollout status -n emojivoto deploy
```

We'll go ahead and patch the `web-svc` to be of type LoadBalancer to make it
easier to access from the browser. Unfortunately, we have to switch the
`faces-gui` Service back to a ClusterIP to let this work in k3d...

```bash
kubectl patch svc -n faces faces-gui \
    --type merge --patch '{"spec":{"type":"ClusterIP"}}'
kubectl patch svc -n emojivoto web-svc \
    --type merge --patch '{"spec":{"type":"LoadBalancer"}}'
kubectl get svc -n emojivoto
```

If we head to the browser now, we should see the `emojivoto` app running.

<!-- @browser_then_terminal -->

There are a group of gRPC route metrics, most immediately interestingly the
`outbound_grpc_route_backend_response_statuses_total` metrics. But if we look
for those right now, we'll get... nothing.

```bash
WEBPOD=$(kubectl get pods -n emojivoto -l 'app=web-svc' \
                -o jsonpath='{ .items[0].metadata.name }')
#@print "# Found web pod ${WEBPOD}"
linkerd diagnostics proxy-metrics -n emojivoto pod/${WEBPOD} \
    | grep outbound_grpc_route_backend_response_statuses
```

This is because we don't have any GRPCRoutes defined yet -- if you do HTTP
traffic with no HTTPRoutes, Linkerd will synthesize metrics for you anyway
(with a `route_name` of `http`), but that doesn't work so well for gRPC. So
let's get some GRPCRoutes going:

```bash
bat bel/emoji-route.yaml
kubectl apply -f bel/emoji-route.yaml
```

The `emojivoto` app is a little interesting in that it has separate gRPC calls
for each emoji you can vote for, rather than a single `vote` call that takes
an emoji name as a parameter... so we have a _lot_ of routes for that.

```bash
bat bel/vote-route.yaml
kubectl apply -f bel/vote-route.yaml
```

But now we should see some metrics!

```bash
linkerd diagnostics proxy-metrics -n emojivoto pod/${WEBPOD} \
    | grep outbound_grpc_route_backend_response_statuses
```

It's much more interesting to split this out by route, though:

```bash
linkerd diagnostics proxy-metrics -n emojivoto pod/${WEBPOD} \
    | grep outbound_grpc_route_backend_response_statuses \
    | sed -e 's/^.*route_name="\([^"][^"]*\)".* \([0-9][0-9]*\)$/\2 \1/'
```

and even more interesting to build a poor man's `linkerd viz top` from that:

```bash
linkerd diagnostics proxy-metrics -n emojivoto pod/${WEBPOD} \
    | grep outbound_grpc_route_backend_response_statuses \
    | sed -e 's/^.*route_name="\([^"][^"]*\)".* \([0-9][0-9]*\)$/\2 \1/' \
    | sort -rn | head
```

What's weird, of course, is how there are more votes for the doughnut emoji
than for any other emoji... hm. It's pretty annoying to use `sed` for this, so
let's just look at the raw metrics for the `vote-doughnut-route`:

```bash
linkerd diagnostics proxy-metrics -n emojivoto pod/${WEBPOD} \
    | grep outbound_grpc_route_backend_response_statuses \
    | grep 'route_name="vote-doughnut-route"' \
    | tr ',' '\n'
```

Huh. `grpc_status="UNKNOWN"` doesn't look good -- remember that that's
gRPC-speak for "we got an error but we don't know what it is", not
"everything's fine". Let's check another route:

```bash
linkerd diagnostics proxy-metrics -n emojivoto pod/${WEBPOD} \
    | grep outbound_grpc_route_backend_response_statuses \
    | grep 'route_name="vote-joy-route"' \
    | tr ',' '\n'
```

There we see `grpc_status="OK"`, which is much better... which is to say, gRPC
metrics let us see gRPC status codes, rather than HTTP status codes. This is a
good thing.

<!-- @wait_clear -->

There are a _lot_ more metrics we could look at here, but we're going to leave
that for later (with yet another plug for the "Metrics, Dashboards, and
Charts, Oh My!" workshop -- we really do go much deeper down the rabbit hole
there).

BUT. Two really important notes on metrics:

<!-- @wait -->

1. There is some exceptionally cool stuff in the wings for metrics, so stay tuned!

<!-- @wait -->

2. Everyone remembers that the `smiley` and `smiley2` workloads for Faces
   _aren't even running in Kubernetes_, right?

<!-- @wait -->

This is the _really_ cool bit about the rework that's happened for metrics,
retries, etc. in Linkerd recently: the logic for all the fancy stuff is
staying a layer above the logic for communicating with endpoints, so it
doesn't care where the endpoints actually are... which makes it _much_ more
powerful for multicluster and external-workload situations.

<!-- @wait_clear -->

# Authorization Policy Audit Mode

Another new feature in Linkerd 2.16: authorization policy audit mode. This is
a way to see what would happen if you set an authorization policy _before_
actually turning it on.

To see what happens with this, we'll switch the `emojivoto` `web-svc` back to
a ClusterIP:

```bash
kubectl patch svc -n emojivoto web-svc \
    --type merge --patch '{"spec":{"type":"ClusterIP"}}'
```

and then we'll bring Emissary in as an ingress controller, but we _won't_ mesh
it.

```bash
kubectl create ns emissary

helm install emissary-crds \
  oci://ghcr.io/emissary-ingress/emissary-crds-chart \
  -n emissary \
  --version 0.0.0-test \
  --wait

helm install emissary-ingress \
     oci://ghcr.io/emissary-ingress/emissary-chart \
     -n emissary \
     --version 0.0.0-test \
     --set replicaCount=1 \
     --set nameOverride=emissary \
     --set fullnameOverride=emissary

kubectl -n emissary wait --for condition=available --timeout=90s deploy -lproduct=aes
```

Finally, we'll tell Emissary to route to Faces for us:

```bash
kubectl apply -f emissary-yaml
```

At this point, we should happily see Faces in the browser:

<!-- @browser_then_terminal -->

Remember, though, we didn't mesh Emissary. If we look at its pods, we'll see
that there's only one container per pod -- there's no Linkerd sidecar there.

```bash
kubectl get pods -n emissary
```

<!-- @wait_clear -->

Let's go ahead and lock things down so that only meshed workloads get to talk
to Faces. Normally, we'd do this by setting the default inbound policy for the
`faces` namespace to `all-authenticated`:

```
kubectl annotate ns faces \
    config.linkerd.io/default-inbound-policy='all-authenticated'
```

but obviously, if we do that, our application will be unusable until we get
Emissary meshed.

<!-- @wait -->

Instead, we'll use the new `audit` policy, which is exactly the same, except
that we use `audit` instead of `all-authenticated`:

```
kubectl annotate ns faces \
    config.linkerd.io/default-inbound-policy=audit
```

Using audit mode makes the Linkerd proxies log when a connection _would_ be
rejected, rather than actually rejecting it.

<!-- @wait_clear -->

So let's go ahead and get that done:

```bash
kubectl annotate ns faces \
    config.linkerd.io/default-inbound-policy=audit
```

As always, we need to restart the workloads in the namespace when we change
its default inbound policy:

```bash
kubectl rollout restart -n faces deploy
kubectl rollout status -n faces deploy
```

If we go back to the browser, we'll see that everything still works:

<!-- @browser_then_terminal -->

...but if we look at the logs for the `face` workload's proxy, we'll see a
host of messages that include `authz.name=audit`, telling us which requests
would have failed if we applied the policy for real.

```bash
kubectl logs -n faces deploy/face -c linkerd-proxy | grep authz.name=audit
```

<!-- @wait -->

If we check the pod IP for Emissary, we'll see that yup, our scary
unauthenticated connections are coming from Emissary:

```bash
kubectl get pods -n emissary -o wide
```

<!-- @wait_clear -->

In addition to the logs, you'll also get metrics for these audit problems:

```bash
FACEPOD=$(kubectl get pods -n faces -l 'service=face' \
              -o jsonpath='{ .items[0].metadata.name }')
#@immed
echo "Found face pod ${FACEPOD}"
linkerd diagnostics proxy-metrics -n faces pod/${FACEPOD} \
    | grep inbound_http_authz_allow_total \
    | grep 'authz_name="audit"' \
    | sed -e 's/,/\n/g'
```

<!-- @wait_clear -->

Finally, the BEL policy generator has been updated to use audit mode by
default, too:

```bash
linkerd policy generate > generated.yaml
bat generated.yaml
```

<!-- @wait_clear -->

## Wrapping Up

So there you have it: a whirlwind tour of some of the new features in Linkerd
2.16, including

- IPv6
- external workload automation
- GRPCRoute itself
- metrics, retries, and timeouts for HTTPRoute and GRPCRoute
- and finally authorization policy audit mode!

Obviously there's a _lot_ more to Linkerd 2.16 than this -- we've barely
scratched the surface. We look forward to seeing what you come up with!

<!-- @wait -->

Finally, feedback is always welcome! You can reach me at flynn@buoyant.io or
as @flynn on the Linkerd Slack (https://slack.linkerd.io).

<!-- @wait -->
<!-- @show_slides -->
