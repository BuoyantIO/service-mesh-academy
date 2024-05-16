# Mesh Expansion

This is the documentation - and executable code! - for mesh expansion with
Linkerd 2.15. A version of this was presented on 15 February 2024 at Buoyant's
Service Mesh Academy, but this version has been considerably updated! The
easiest way to use this file is to execute it with [demosh].

Things in Markdown comments are safe to ignore when reading this later. When
executing this with [demosh], things after the horizontal rule below (which
is just before a commented `@SHOW` directive) will get displayed.

[demosh]: https://github.com/BuoyantIO/demosh

This workshop WILL DESTROY any running k3d cluster named `faces`, and
any Docker containers named `smiley` and `color` as well. Be careful!

When you use `demosh` to run this file, requirements will be checked for
you.

<!-- set -e >
<!-- @import demosh/check-requirements.sh -->

<!-- @start_livecast -->

```bash
BAT_STYLE="grid,numbers"
WORKLOAD_IMAGE_TAG=1.3.0
```

---
<!-- @SHOW -->

# Mesh Expansion with Linkerd

Mesh expansion is all about being able to have workloads in a Kubernetes
cluster communicating with workloads outside the cluster -- in our case, using
Linkerd for security, reliability, and observability! We're going to have a
k3d cluster running the Linkerd control plane and an in-cluster workload, then
we'll have multiple VMs running _outside_ the cluster (but connected to the
same Docker network).

Let's start by getting our cluster running, connected to the `mesh-exp` Docker
network.

```bash
#@immed
k3d cluster delete mesh-exp >/dev/null 2>&1

k3d cluster create mesh-exp \
    --network=mesh-exp \
    --port 80:80@loadbalancer \
    --port 443:443@loadbalancer \
    --k3s-arg '--disable=traefik,metrics-server@server:0'
```

Once that's done, let's get Linkerd up and running. You'll need BEL
`preview-24.5.3` or later for this -- and, yes, you'll need a free Buoyant
account for this, since we're showing off the external workload
autoregistration feature. If you don't already have an account, hit up
https://enterprise.buoyant.io to get one.

Once that's done and you've set the environment variables it'll tell you
about, it's time to make sure we have the right version of Linkerd installed!

```bash
# curl --proto '=https' --tlsv1.2 -sSfL https://enterprise.buoyant.io/install-preview | sh
linkerd version --proxy --client --short
```

Once that's done, we install Linkerd's CRDs...

```bash
linkerd install --crds | kubectl apply -f -
```

...then we install Linkerd itself. Note that we're explicitly specifying the
trust anchor and identity issuer certificate -- these are certs that I
generated earlier and have stored locally, which is important because we'll
need to use those certificates for identity in our external workloads.

```bash
linkerd install \
    --identity-trust-anchors-file ./certs/ca.crt \
    --identity-issuer-certificate-file ./certs/issuer.crt \
    --identity-issuer-key-file ./certs/issuer.key \
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
tell it to make the workloads error-free -- this is about edge computing, not
debugging the Faces demo!

```bash
helm install faces -n faces \
     oci://ghcr.io/buoyantio/faces-chart --version 1.2.4 \
     --set gui.serviceType=LoadBalancer \
     --set face.errorFraction=0 \
     --set backend.errorFraction=0
```

We'll wait for our Pods to be running before we move on.

```bash
kubectl rollout status -n faces deploy
kubectl get pods -n faces
```

OK! If we flip over to look at the GUI right now (at http://localhost/), we
should see grinning faces on blue backgrounds.

<!-- @browser_then_terminal -->

## On to the Edge

So this is all well and good, but it's also not very interesting because it's
just running a Kubernetes application. Let's change that. We'll run the `face`
and `smiley` workloads outside the cluster, but still using Linkerd for secure
communications.

Let's start by ditching those workloads in Kubernetes.

```bash
kubectl delete -n faces deploy face smiley
```

If we flip over to look now, we'll see endless frowning faces on purple
backgrounds, since the `face` workload is no longer answering. Let's fix that.

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

So let's actually get some external workloads running, starting with the `face`
workload. First things first: we need an ExternalGroup resource for it!

```bash
bat bel/face-group.yaml
kubectl apply -f bel/face-group.yaml
```

This won't do anything yet, because we don't have any external workloads
registering. So. Onward!

<!-- @wait_clear -->

## Starting the `face-1` Workload

Now that we have an ExternalGroup, we'll fire up the `face` workload in a
container called `face-1`. We're going to deliberately set its hostname, too,
so that the GUI can show it more gracefully. (Also, for this we have to
explicitly set the DNS names for the `smiley` and `color` workloads, since the
`face` workload normally just talks to `smiley` and `color`, which won't work
-- we need the FQDNs.)

```bash
#@immed
docker kill face-1 >/dev/null 2>&1
#@immed
docker rm face-1 >/dev/null 2>&1
docker run --rm --detach \
       --cap-add=NET_ADMIN \
       --network=mesh-exp \
       --dns=${DNS_IP} \
       --name=face-1 \
       --hostname=face-docker-ext1 \
       -v "$(pwd)/certs:/opt/spire/certs" \
       -e WORKLOAD_NAME=face \
       -e WORKLOAD_NAMESPACE=faces \
       -e POD_CIDR=${POD_CIDR} \
       -e SVC_CIDR=${SVC_CIDR} \
       -e NODE_IP=${NODE_IP} \
       -e FACES_SERVICE=face \
       -e SMILEY_SERVICE=smiley.faces.svc.cluster.local \
       -e COLOR_SERVICE=color.faces.svc.cluster.local \
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
watch 'sh -c "kubectl get externalworkloads -n faces; linkerd dg endpoints face.faces.svc.cluster.local"'
```

<!-- @show_terminal -->
<!-- @clear -->

## The Smiley Workload

At this point we have cursing faces on blue backgrounds, because `face` is now
responding -- but of course, it still no `smiley` workload. So let's fix that,
by doing exactly the same thing for `smiley` workload as we just did for
`face`. First, let's get its ExternalGroup set up:

```bash
bat bel/smiley-group.yaml
kubectl apply -f bel/smiley-group.yaml
```

...and then we'll start the `smiley` workload in a container called `smiley-1`.

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

Once again, we should see things happen here!

<!-- @show_5 -->

```bash
watch 'sh -c "kubectl get externalworkloads -n faces; linkerd dg endpoints smiley.faces.svc.cluster.local"'
```

<!-- @clear -->
<!-- @show_terminal -->

## ExternalWorkloads and EndpointSlices

ExternalWorkloads end up defining EndpointSlices, too:

```bash
kubectl get endpointslices -n faces
```

You can see that there are a "normal" slices for both `face` and `smiley`,
created by the usual Kubernetes EndpointSlice controller, with no Endpoints --
this is because the Kubernetes EndpointSlice controller doesn't know about our
ExternalWorkloads. But there are also slices created by the Linkerd
EndpointSlice controller, which _does_ know about our ExternalWorkloads, so it
has the correct external workload IP addresses.

<!-- @wait_clear -->

## Level Up

So! this is well and good. Suppose we want to do more?

<!-- @wait -->

Well, for starters, suppose we fire up a second external workload for `face`?
This is _exactly_ the same `docker run` as before, except that we change the
name and the hostname -- so we should end up with `face-2` running alongside
`face-1`, both running `face` workloads.

```bash
#@immed
docker kill face-2 >/dev/null 2>&1
#@immed
docker rm face-2 >/dev/null 2>&1
docker run --rm --detach \
       --cap-add=NET_ADMIN \
       --network=mesh-exp \
       --dns=${DNS_IP} \
       --name=face-2 \
       --hostname=face-docker-ext2 \
       -v "$(pwd)/certs:/opt/spire/certs" \
       -e WORKLOAD_NAME=face \
       -e WORKLOAD_NAMESPACE=faces \
       -e POD_CIDR=${POD_CIDR} \
       -e SVC_CIDR=${SVC_CIDR} \
       -e NODE_IP=${NODE_IP} \
       -e FACES_SERVICE=face \
       -e SMILEY_SERVICE=smiley.faces.svc.cluster.local \
       -e COLOR_SERVICE=color.faces.svc.cluster.local \
       -e DELAY_BUCKETS=0,50,100,200,500,1000 \
       ghcr.io/buoyantio/faces-bel-external-workload:${WORKLOAD_IMAGE_TAG}

watch 'sh -c "kubectl get externalworkloads -n faces; linkerd dg endpoints face.faces.svc.cluster.local"'
```

Look! it's a second endpoint! And if we hit the "Show Pods" button in the GUI,
we should see two distinct Pods returning information to us.

<!-- @browser_then_terminal -->

So this is pretty cool -- Linkerd is just transparently load balancing between
our two external `face` workloads.

<!-- @wait_clear -->

## More Load Balancing Tricks

If you look closely, you'll realize that we're actually just slotting
ExternalWorkloads into the existing Service/Deployment/Pod paradigm:

- ExternalGroups are like Deployments; where Deployments cause Pods to be
  created, ExternalGroups cause ExternalWorkloads to be created.

- Services effectively select across Pods and ExternalWorkloads, because the
  Linkerd ExternalWorkload EndpointSlice controller creates EndpointSlices
  that Services can use.

<!-- @wait -->

So let's take a look at what happens if we create an ExternalGroup for the
`color` workload _without_ shredding its existing Deployment. Here's the
ExternalGroup:

```bash
bat bel/color-group.yaml
kubectl apply -f bel/color-group.yaml
```

...and here's the `color` workload running in a container called `color-1`.
This is parallel to how we started `smiley-1`, but here we're telling our
`color-1` workload to return green rather than blue.

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
       -e COLOR=green \
       -e DELAY_BUCKETS=0,50,100,200,500,1000 \
       ghcr.io/buoyantio/faces-bel-external-workload:${WORKLOAD_IMAGE_TAG}
```

Doing that, we'll immediately see the existing `color` endpoint -- but then
we'll see a new one appear!

```bash
watch 'sh -c "kubectl get externalworkloads -n faces; linkerd dg endpoints color.faces.svc.cluster.local"'
```

If we _then_ toss the existing deployment, then things should continue to work
just fine, because the ExternalWorkload is still there.

<!-- @show_5 -->

```bash
kubectl scale -n faces deploy color --replicas=0
watch 'sh -c "kubectl get externalworkloads -n faces; linkerd dg endpoints color.faces.svc.cluster.local"'
```

<!-- @clear -->
<!-- @show_terminal -->

## HTTPRoutes

Where things get more interesting, of course, is with higher-level
functionality. For example, we can use Linkerd's routing capabilities to
control how traffic flows, even when ExternalWorkloads are involved. Let's
start `smiley2` (which return heart-eyes smileys) as yet another external
workload. Note that this time we're _also_ setting up a new Service,
`smiley2`, rather than just using the labels from the `smiley` Service.

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
       -e DELAY_BUCKETS=0,50,100,200,500,1000 \
       ghcr.io/buoyantio/faces-bel-external-workload:${WORKLOAD_IMAGE_TAG}

watch 'sh -c "kubectl get externalworkloads -n faces; linkerd dg endpoints smiley2.faces.svc.cluster.local"'
```

If we bring up the browser now, we'll see the usual grinning faces, with no
heart-eyed smileys yet...

<!-- @browser_then_terminal -->

...but we can change that with an HTTPRoute!

```bash
bat bel/smiley-route.yaml
kubectl apply -f bel/smiley-route.yaml
```

<!-- @show_5 -->
<!-- @wait -->


Of course, we can change the canary weight as usual...

```bash
kubectl edit httproute -n faces smiley-route
```

...and we'll see the effects in realtime.

```bash
kubectl edit httproute -n faces smiley-route
```

The fact that the workloads are external doesn't affect how Linkerd can work
with them. As such, there's a _lot_ more we could do here -- for example, we
haven't looked at Linkerd's authorization and observability features at all.
Those are topics for another day!

<!-- @wait -->
<!-- @show_terminal -->
<!-- @clear -->

## Wrapping Up

So there you have it: we've seen how to use BEL's autoregistration harness to
bring external workloads into the mesh the easy way, and we've seen some
examples of how to use Linkerd's routing can control access to those
workloads. We've barely scratched the surface of what you can do with a
service mesh extending beyond the cluster, but we've seen enough to know that
it's a powerful tool.

<!-- @wait -->

Finally, feedback is always welcome! You can reach me at flynn@buoyant.io or
as @flynn on the Linkerd Slack (https://slack.linkerd.io).

<!-- @wait -->
<!-- @show_slides -->
