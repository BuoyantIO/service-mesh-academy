<!--
SPDX-FileCopyrightText: 2024 Buoyant Inc.
SPDX-License-Identifier: Apache-2.0
-->

# Linkerd 2.15 Features

This is the documentation - and executable code! - for the Service Mesh
Academy workshop about new 2.15 features. The easiest way to use this file is
to execute it with [demosh].

Things in Markdown comments are safe to ignore when reading this later. When
executing this with [demosh], things after the horizontal rule below (which
is just before a commented `@SHOW` directive) will get displayed.

[demosh]: https://github.com/BuoyantIO/demosh

This workshop will create a multizone k3d cluster for you. Make sure you don't
already have a cluster named "features".

<!-- @import demosh/check-requirements.sh -->
<!-- @start_livecast -->
---
<!-- @SHOW -->

## Creating the Cluster

OK, let's get this show on the road by creating a multi-zone cluster. This
will be a four-node k3d cluster, with each Node in a different zone (in this
case, `east`, `west`, and `central`). We'll do our usual dance of setting up
the cluster to expose ports 80 & 443 on the host network, and of specifying a
named network so that we can hook other things up to it.

There's enough to this that we'll use a YAML file to specify the cluster
rather than doing it all on the command line.

```bash
bat k3d-multizone.yaml
k3d cluster create -c k3d-multizone.yaml --wait
kubectl cluster-info
```

<!-- @wait_clear -->

## Installing the Linkerd Operator

Next up, instead of installing the Linkerd CRDs and control plane by hand,
we're going to use the Linkerd Operator from Buoyant, which will do all the
heavy lifting for us. This is more involved than just running `linkerd
install`, but it's a lot more flexible and powerful.

_This does require you to sign up for a free account with Buoyant._ But
really, it's worth it, and we won't sell your information to anyone! To get
set up, go to https://enterprise.buoyant.io/ and sign up.

Once done, you'll get to a page that'll show you three environment variables:

- `API_CLIENT_ID`
- `API_CLIENT_SECRET`
- `BUOYANT_LICENSE`

You'll need all of those set in your environment as you continue!

<!-- @wait -->

Once you have all three of those, you can install the Linkerd Operator.

```bash
helm repo add linkerd-buoyant https://helm.buoyant.cloud
helm repo update

helm install linkerd-buoyant \
  --create-namespace \
  --namespace linkerd-buoyant \
  --set metadata.agentName=$CLUSTER_NAME \
  --set api.clientID=$API_CLIENT_ID \
  --set api.clientSecret=$API_CLIENT_SECRET \
  --set metrics.debugMetrics=true \
  --set agent.logLevel=debug \
  --set metrics.logLevel=debug \
linkerd-buoyant/linkerd-buoyant

kubectl rollout status daemonset/buoyant-cloud-metrics -n linkerd-buoyant
linkerd buoyant check
```

<!-- @wait_clear -->

## Creating Secrets

Now that we have the Linkerd Operator installed, we need to create secrets for
our control plane to use. We'll use `step` to create a trust anchor and an
identity issuer in the `certs` directory:

```bash
#@immed
rm -rf certs
mkdir certs

# The `root-ca` profile is correct for a Linkerd trust anchor. We
# don't need a password, and we acknowledge that this is insecure.
step certificate create root.linkerd.cluster.local \
     certs/ca.crt certs/ca.key \
     --profile root-ca \
     --no-password --insecure

# The `intermediate-ca` profile is correct for a Linkerd identity
# issuer. Drop its lifetime to 1 year (8760 hours) and use the trust
# anchor to sign it.
step certificate create identity.linkerd.cluster.local \
     certs/issuer.crt certs/issuer.key \
     --profile intermediate-ca --not-after 8760h \
     --no-password --insecure \
     --ca certs/ca.crt --ca-key certs/ca.key
```

Once we have these secrets, we need to store them in a Kubernetes Secret so
that the Linkerd control plane can use them later. Sadly, we can't use
`kubectl create secret` for this, because we need three keys in this secret...
so we're going to use a stupid Python script instead, to avoid copying and
pasting things everywhere.

```bash
bat make-identity-secret.py
python make-identity-secret.py | kubectl apply -f -
```

<!-- @wait_clear -->

## Creating the ControlPlane

Once we have our secrets, we need to create a ControlPlane CRD, which is what
the Linkerd Operator uses to manage the Linkerd control plane for us. We'll
use another stupid Python script to generate this CRD, but this time we're
going to dump it to a file to look at it before we apply it.

```bash
bat make-control-plane.py
python make-control-plane.py enterprise-2.15.1 > buoyant/control-plane.yaml
bat buoyant/control-plane.yaml
kubectl apply -f buoyant/control-plane.yaml
```

At this point the Operator is merrily getting Linkerd installed for us.

```bash
kubectl get controlplane
linkerd check
kubectl get controlplane
```

<!-- @wait_clear -->

## Installing the First DataPlane

We'll finish this part of our setup by installing a DataPlane CRD to tell the
Operator that it should manage the data plane in the `linkerd-buoyant`
namespace. No need for a Python script here!

```bash
bat buoyant/dataplane.yaml
kubectl apply -f buoyant/dataplane.yaml
```

At this point, the Operator is installing the data plane for the
`linkerd-buoyant` namespace. We're not going to wait for it, though -- let's
go ahead and get our app installed.

<!-- @wait_clear -->

## Installing the Application

For our application, we'll use the Faces demo behind Emissary, as usual.
However, we're going to install things differently:

- We'll install three replicas of Emissary, with anti-affinity rules to ensure
  that we have one on each Node. This is actually the recommended way to run
  Emissary, though it's not the way we typically do for SMA demos!

<!-- @wait -->

- We'll put the `face` and `smiley` workloads for Faces in the `east` zone.

<!-- @wait -->

- Finally, we'll install different `color` Deployments so that we can put one
  in each zone. All three deployments will be behind the same Service, though.

  (The reason we're using multiple Deployments like this is so we can
  independently scale them for the demo.)

<!-- @wait -->

We'll also tell Faces NOT to fail all the time; this isn't a resilience demo!

<!-- @wait_clear -->

### Installing Emissary

Emissary is pretty easy, we can just use Helm with a custom values file to set
up anti-affinity rules:

```bash
bat emissary/values.yaml

# Create our namespace and annotate it for Linkerd
kubectl create ns emissary
kubectl annotate ns emissary linkerd.io/inject=enabled

# Install Emissary CRDs
helm install emissary-crds -n emissary \
  oci://ghcr.io/emissary-ingress/emissary-crds-chart \
  --version 0.0.0-test \
  --wait

# Install Emissary itself
helm install emissary-ingress \
  oci://ghcr.io/emissary-ingress/emissary-chart \
  -n emissary \
  --version 0.0.0-test \
  -f emissary/values.yaml

# Wait for everything to be running
kubectl rollout status -n emissary deploy

# Verify that our Pods are running on different Nodes
kubectl get pods -n emissary -o wide

# Finally, install the bootstrap configuration.
kubectl apply -f emissary/bootstrap
```

In addition to the usual Emissary setup to listen on ports 80 & 443, the
bootstrap configuration also includes a DataPlane for the Emissary namespace,
so that the Operator can manage that for us later. (You still need the
injection annotation, though, or the DataPlane resource will have no effect.)

<!-- @wait_clear -->

## Installing Faces

Faces is a bit weirder, since we want to explicitly control the zones. I just
used `helm template` to dump out the YAML from the Helm chart, then edited
things by hand, so let's take a look:

```bash
# faces/faces.yaml contains most of what Faces needs
bat faces/faces.yaml

# faces/colors.yaml contains the three `color` Deployments
bat faces/colors.yaml

# faces/bootstrap contains the bootstrap configuration
bat faces/bootstrap/*
```

Given all that, let's get this show on the road:

```bash
kubectl create ns faces
kubectl annotate ns faces linkerd.io/inject=enabled

kubectl apply -f faces/faces.yaml
kubectl apply -f faces/colors.yaml
kubectl apply -f faces/bootstrap

kubectl rollout status -n faces deploy
```

Once again, let's doublecheck to make sure that our Pods are really running in
the correct zones.

```bash
kubectl get pods -n faces -o wide
```

OK! At this point everything should be running for us -- let's make sure of
that in the browser.

<!-- @browser_then_terminal -->

### Side Quest: Native Sidecar Support

One of the really cool things that Kubernetes 1.29 brings us is native support
for sidecars. (This was present in 1.28, but it was alpha and not recommended.
In 1.29, it's officially good to go.)

Let's try a quick test using a Job to run `curl` to our `face` workload.

```bash
bat job.yaml
kubectl apply -f job.yaml
```

We can watch the Job run...

```bash
watch "kubectl get -n faces pods | grep curl"
```

...and, hmmm, that's not good. It's never finishing, even though it ran.

```bash
kubectl get jobs -n faces
kubectl logs -n faces job/curl -c curl | bat
```

This is _the_ problem with sidecars and Jobs pre-native-sidecars: since the
sidecar is still running, the Job never finishes. So that's not good.

<!-- @wait_clear -->

### Side Quest: Native Sidecar Support

Let's clean up the dead job and try again with native sidecar support.

```bash
kubectl delete job -n faces curl
```

To enable native sidecar support, we just need set `proxy.nativeSidecar=true`
in the ControlPlane configuration.

```bash
${EDITOR} buoyant/control-plane.yaml
kubectl apply -f buoyant/control-plane.yaml
```

Applying that, we'll see that the Operator immediately starts updating
everything.

```bash
watch "kubectl get controlplane; kubectl get pods -n linkerd"
```

Once it's done, we can try our Job again.

```bash
kubectl apply -f job.yaml
watch "kubectl get -n faces pods | grep curl"
```

This time it finishes! and we can make sure it actually ran by checking its
logs.

```bash
kubectl logs -n faces job/curl -c curl
```

So that's that. Let's clean up the job before continuing.

```bash
kubectl delete job -n faces curl
```

<!-- @wait_clear -->

## Main Quest: Testing the Application

If we go to the browser, we'll see a mix of background colors:
- blue for east
- green for west
- yellow for central

<!-- @browser_then_terminal -->

In fact, we see mostly not blue, because `color-east` is actually a little
slower (by design) than the other two.

We can also see this in stats:

```bash
linkerd dg proxy-metrics -n faces deploy/face | python crunch-metrics.py
```

<!-- @wait_clear -->

## HAZL

The problem here is that the `face` Deployment is running in the `east` zone,
and really, routing a ton of its traffic out to other zones isn't ideal. We
can use HAZL, the High Availability Zone-aware Load Balancer, to fix this.

We enable HAZL by modifying the ControlPlane resource to contain this rather
messy stanza under `linkerd.controlPlaneConfig`:

```
  destinationController:
    additionalArgs:
      - -ext-endpoint-zone-weights
```

So let's go ahead and do that.

```bash
${EDITOR} buoyant/control-plane.yaml
kubectl apply -f buoyant/control-plane.yaml
```

This will cause updates:

```bash
watch "kubectl get controlplane; kubectl get pods -n linkerd"
```

If we head back to the browser, we should see all blue now!

<!-- @browser_then_terminal -->

## Side Quest: Uh... what's going on?

So that didn't work.

<!-- @wait -->

We could look at a ton of stuff here, but the actual cause is pretty simple:
way back at the beginning, I installed enterprise-2.15.1, rather than
enterprise-2.15.2. Sigh.

Fortunately, this is really easy to fix with the ControlPlane.

```bash
${EDITOR} buoyant/control-plane.yaml
kubectl apply -f buoyant/control-plane.yaml
watch "kubectl get controlplane; kubectl get dataplane -A; kubectl get pods -n linkerd"
watch "kubectl get controlplane; kubectl get dataplane -A; kubectl get pods -n faces; kubectl get pods -n emissary"
```

...and NOW if we go back to the browser, we'll see all blue!

<!-- @browser_then_terminal -->

## HAZL

This, of course, we could probably get with Kubernetes own topology-aware
routing. What topology-aware routing doesn't give us is resilience. Suppose
our `color-east` workload crashes?

<!-- @show_composite -->

```bash
kubectl scale -n faces deploy/color-east --replicas=0
```

Over in the browser, we'll see that we've just seamlessly switched
to a different zone.

<!-- @wait_clear -->

## HAZL

If `color-east` comes back up, we'll see it start taking traffic
again.

```bash
kubectl scale -n faces deploy/color-east --replicas=1
```

<!-- @wait_clear -->
<!-- @show_terminal -->

## HAZL and Load

HAZL is also smart enough to know that if we overwhelm `color-east`, it should
bring in workloads from the other zones to help out. Let's fire up a traffic
generator to see this in action.

```bash
bat faces/load.yaml
kubectl apply -f faces/load.yaml
```

At 10RPS of additional load, nothing much will happen in the browser, though
we can see the request rate change in Buoyant Cloud.

<!-- @browser_then_terminal -->

So let's just escalate things here.

```bash
kubectl set env -n faces deploy/load LOAD_RPS=50
```

<!-- @browser_then_terminal -->

There we go. And, once again, if we drop the load back down, we expect to see
only blue faces.

```bash
kubectl scale -n faces deploy/load --replicas=0
```

<!-- @browser_then_terminal -->

## One More Thing: Mesh Expansion

We've done a couple of Service Mesh Academy sessions on Linkerd's newfound
ability to run workloads that aren't in Kubernetes at all, but to date we
haven't done one using BEL yet. So let's do that now!

We don't have time to dive deep into exactly how the mesh-expansion setup is
built (you can find that in the `2-15-mesh-expansion` directory of Service
Mesh Academy!), but let's see it in action at minimum.

First up, let's break everything by completely removing the `smiley` workload.

```bash
kubectl delete -n faces deploy,service smiley
```

If we head over to the browser now, we'll see all cursing faces.

<!-- @browser_then_terminal -->

## Mesh Expansion

Let's fire up the `smiley` workload in a Docker container, _outside_ of our
cluster. We're running this using _exactly_ the same setup as we did for the
2.15 Mesh Expansion SMA earlier, **including the horrible hackery of running
both a SPIRE server and a SPIRE agent in our Docker container**. Don't do that
in the real world.

1. Our external workload needs to route to the cluster's Pod CIDR range via the
   one of the Nodes. We'll use the `server-0` Node for that (why not?) so let's grab its IP address.

```bash
NODE_IP=$(kubectl get node k3d-features-server-0 -ojsonpath='{.status.addresses[0].address}')
#@immed
echo "NODE_IP is ${NODE_IP}"
POD_CIDR=$(kubectl get nodes -ojsonpath='{.items[0].spec.podCIDR}')
#@immed
echo "POD_CIDR is ${POD_CIDR}"
```

<!-- @wait_clear -->

## Mesh Expansion

2. We need to set up DNS to allow references to things like
   `face.faces.svc.cluster.local` need to actually resolve to addresses inside
   the cluster! We're going to tackle this by first editing the `kube-dns`
   Service to make it a NodePort on UDP port 30000, so we can talk to it from
   our Node, then running `dnsmasq` as a separate Docker container to forward
   DNS requests for cluster Services to the `kube-dns` Service.

   This isn't really the best way to tackle this in production, but it's not
   completely awful: we probably don't want to completely expose the cluster's
   DNS to the outside world. So, first we'll switch `kube-dns` to a NodePort:

```bash
kubectl edit -n kube-system svc kube-dns
kubectl get -n kube-system svc kube-dns
```

   Next, we need the `dnsmasq` container. This is a little weird: we're going to
   use the `drpsychick/dnsmasq` image, but we'll volume mount our own entrypoint
   script:

```bash
bat expansion/dns-forwarder.sh
#@immed
docker kill dnsmasq >/dev/null 2>&1
#@immed
docker rm dnsmasq >/dev/null 2>&1

docker run --detach --rm --cap-add NET_ADMIN --net=features \
       -v $(pwd)/expansion/dns-forwarder.sh:/usr/local/bin/dns-forwarder.sh \
       --entrypoint sh \
       -e DNS_HOST=${NODE_IP} \
       --name dnsmasq drpsychick/dnsmasq \
       -c /usr/local/bin/dns-forwarder.sh
```

   Once that's done, we can get the IP address of the `dnsmasq` container to
   use later.

```bash
DNS_IP=$(docker inspect dnsmasq | jq -r '.[].NetworkSettings.Networks["features"].IPAddress')
#@immed
echo "DNS_IP is ${DNS_IP}"
```

<!-- @wait_clear -->

## Starting the External Workloads

So let's actually get our `smiley` container running! We're using our
`ghcr.io/buoyantio/faces-external-workload:1.0.0` image from the Mesh
Expansion SMA here.

```bash
#@immed
docker kill smiley >/dev/null 2>&1
#@immed
docker rm smiley >/dev/null 2>&1
docker run --rm --detach \
       --cap-add=NET_ADMIN \
       --network=features \
       --dns=${DNS_IP} \
       --name=smiley \
       -v "$(pwd)/certs:/opt/spire/certs" \
       -e WORKLOAD_NAME=smiley \
       -e WORKLOAD_NAMESPACE=faces \
       -e NODE_NAME='$(hostname)' \
       -e FACES_SERVICE=smiley \
       -e DELAY_BUCKETS=0,50,100,200,500,1000 \
       ghcr.io/buoyantio/faces-external-workload:1.0.0 \
  && docker exec smiley ip route add ${POD_CIDR} via ${NODE_IP}
```

OK, let's make sure that that's running.

```bash
docker ps -a
```

<!-- @wait_clear -->

## Creating the ExternalWorkload

Next, we need to create an ExternalWorkload resource so that Linkerd knows how
to use our `smiley` workload. This is kind of analogous to a Kubernetes Pod:
it's a way of associating a name and an IP address with our workload.

```bash
SMILEY_ADDR=$(docker inspect smiley | jq -r '.[].NetworkSettings.Networks["features"].IPAddress')
#@immed
echo "SMILEY_ADDR is ${SMILEY_ADDR}"

sed -e "s/%%NAME%%/smiley/" -e "s/%%IP%%/${SMILEY_ADDR}/g" \
    < ./expansion/external-workload.yaml.tmpl \
    > /tmp/smiley.yaml

bat /tmp/smiley.yaml

kubectl apply -f /tmp/smiley.yaml
```

<!-- @wait_clear -->

## Testing the External Workload

At this point we should see our new `smiley` Service, and we should see that
it has EndpointSlices, too:

```bash
kubectl get svc -n faces
kubectl get endpointslices -n faces
```

And if we go back to the browser, we should see grinning faces again!

<!-- @browser_then_terminal -->

## Summary

So there we have it: a tour of HAZL, native sidecar support, the Linkerd
Operator, and mesh expansion with BEL! This is a lot of stuff, but it's all
pretty cool stuff, and we look forward to digging more into it with everyone!

<!-- @wait -->
<!-- @show_slides -->
