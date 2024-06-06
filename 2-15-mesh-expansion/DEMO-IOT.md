# Edge Computing with OpenSUSE and Linkerd

This is the documentation - and executable code! - for edge computing with
OpenSUSE and Linkerd 2.15. The easiest way to use this file is to execute it
with [demosh].

Things in Markdown comments are safe to ignore when reading this later. When
executing this with [demosh], things after the horizontal rule below (which
is just before a commented `@SHOW` directive) will get displayed.

[demosh]: https://github.com/BuoyantIO/demosh

When you use `demosh` to run this file, requirements will be checked for
you.

<!-- set -e >
<!-- @import demosh/check-requirements.sh -->

<!-- @start_livecast -->
<!-- #@hook show_6 SCENE_6 -->

```bash
BAT_STYLE="grid,numbers"
```

---
<!-- @SHOW -->

# Edge Computing with OpenSUSE and Linkerd

What we're going to show today is how we can run a Kubernetes cluster and some
_non_-Kubernetes workloads on OpenSUSE, using Linkerd to provide security,
reliability, and observability across the whole thing, spanning the Kubernetes
and non-Kubernetes workloads.

For this demo, we have a single-node cluster running, with two other machines
on the same network where we'll run our edge workloads. The cluster is running
on a machine called `cluster-3`, with edge machines `cluster-1` and
`cluster-2` (I know, not the best names on the planet, sorry).

All of these machines are running OpenSUSE (specifically, Leap 15.5 JeOS). Our
Kubernetes cluster is running k3s on the metal of `cluster-3`. And, at the
moment, not much is running anywhere.

```bash
kubectl get ns
ssh cluster-1 ps -f
ssh cluster-1 sudo podman ps -a
ssh cluster-2 ps -f
ssh cluster-2 sudo podman ps -a
```

<!-- @wait_clear -->

## Installing Linkerd

Let's start by getting Linkerd up and running... but, first, let's make sure
we have the correct version installed. The minimum version is `edge-24.2.5`,
but ideally you'll have Linkerd 2.15.1.

```bash
linkerd version --proxy --client --short
```

OK, let's install Linkerd's CRDs...

```bash
linkerd install --crds | kubectl apply -f -
```

...then Linkerd itself. Note that we're explicitly specifying the trust anchor
and identity issuer certificate -- these are certs that I generated earlier
and have stored locally, which is important because we'll need to use those
certificates for identity in our external workloads.

```bash
linkerd install \
    --identity-trust-anchors-file ./certs/ca.crt \
    --identity-issuer-certificate-file ./certs/issuer.crt \
    --identity-issuer-key-file ./certs/issuer.key \
  | kubectl apply -f -
linkerd check
```

<!-- @wait_clear -->

OK! Now that we have Linkerd running in our cluster, let's get a workload
running there too. We're going to use our usual Faces demo for this, so let's
start by just installing it using its Helm chart.

First, we'll set up the `faces` namespace, with Linkerd injection for the
whole namespace...

```bash
bat k8s/faces-namespace.yaml
kubectl apply -f k8s/faces-namespace.yaml
```

...and then we'll install the Faces demo itself. We'll tell the chart to make
the GUI service a LoadBalancer, to make it easy to talk to, and we'll also
tell it to make the workloads error-free -- this is about edge computing, not
debugging the Faces demo!

```bash
helm install faces -n faces \
     oci://ghcr.io/buoyantio/faces-chart --version 1.0.0 \
     --set gui.serviceType=LoadBalancer \
     --set face.errorFraction=0 \
     --set backend.errorFraction=0
```

We'll wait for our Pods to be running before we move on.

```bash
kubectl rollout status -n faces deploy
kubectl get pods -n faces
```

OK! If we flip over to look at the GUI right now, we should see grinning faces
on green backgrounds.

<!-- @browser_then_terminal -->

## On to the Edge

So this is all well and good, but it's also not very interesting because it's
just running a Kubernetes application. Let's change that. We'll run the
`smiley` and `color` workloads outside the cluster, but still using Linkerd
for secure communications.

Let's start by ditching those workloads in Kubernetes.

```bash
kubectl delete -n faces deploy,service smiley
kubectl delete -n faces deploy,service color
```

If we flip over to look now, we'll see endless cursing faces on grey
backgrounds, since the `face` workload is answering, but it can't fetch
smileys or colors since those workloads are no longer running.

<!-- @browser_then_terminal -->
<!-- @SHOW -->

## Starting the External Workloads

OK. Let's start the `smiley` and `color` workloads running outside the
cluster. In this demo, we're going to basically do everything the hard way, so
we can talk about it.

1. The first thing to realize is that, in addition to just running our
   workload, we also need to run the Linkerd proxy next to it, just like we do
   in Kubernetes. That means we need to do the same kind of networking magic
   that Kubernetes does, so instead of just running everything on the bare
   metal, we'll actually run everything inside a container using `podman`.
   This isn't _necessary_, strictly speaking, but it makes it a _lot_ easier
   to know that we're not messing up the base Linux installation by accident.

<!-- @wait_clear -->

2. We'll also need to get a SPIFFE identity for the proxy, which means that we
   need a SPIRE agent running in our container as well. In the real world,
   you'd configure the SPIRE agent to talk to a SPIRE server... but for this
   demo, we're going to run a server in our container too, and we're just
   going to mount the Linkerd trust anchor into our container as well.

   **This is a terrible idea in the real world. Don't do this.** Again,
   though, this is an edge computing demo, _not_ a SPIRE attestation demo!

<!-- @wait_clear -->

3. We need to allow our external workload container to route to the cluster's
   Pod CIDR range via the Node's IP, which in turn means our edge devices need
   direct IP connectivity to the Node (future releases of Linkerd should relax
   this requirement).

   This is the only bit of setup we'll be doing on the host itself, rather
   than inside the container. It's easy to do - we'll just run `ip route add`
   on our host - but of course we need the Pod CIDR range from the cluster to
   do so.

```bash
NODE_IP=$(kubectl get nodes  -ojsonpath='{.items[0].status.addresses[0].address}')
#@immed
echo "NODE_IP is ${NODE_IP}"
POD_CIDR=$(kubectl get nodes  -ojsonpath='{.items[0].spec.podCIDR}')
#@immed
echo "POD_CIDR is ${POD_CIDR}"
```

<!-- @wait_clear -->

4. DNS is a little tricky, because references to things like
   `face.faces.svc.cluster.local` need to actually resolve to addresses inside
   the cluster! We're going to tackle this by first editing the `kube-dns`
   Service to make it a NodePort on UDP port 30000, so we can talk to it from
   our Node, then running `dnsmasq` on the Node to forward DNS requests for
   cluster Services to the `kube-dns` Service:

```bash
kubectl edit -n kube-system svc kube-dns
kubectl get -n kube-system svc kube-dns
ssh cluster-3 sudo dnsmasq --server "/svc.cluster.local/127.0.0.1#30000"
dig @cluster-3 face.faces.svc.cluster.local
```

   This isn't really the best way to tackle this in production, but it's
   likely the simplest, and it's not completely awful: we probably don't want
   to completely expose the cluster's DNS to the outside world.

<!-- @wait_clear -->

Taking all that into account, we need a Docker image that contains the Linkerd
proxy, the SPIRE agent, the SPIRE server (remember, this is a hack!), and of
course our actual workload. We also need a bootstrap script that sets up the
world for us.

`ghcr.io/buoyantio/faces-external-workload:1.0.0` is such an image.
Actually building it isn't that complex: the magic is in the bootstrap.

<!-- @wait_clear -->

### Bootstrap Magic

That bootstrap script is deceptively short for the amount of magic it
contains:

1. First it runs the SPIRE server, then the SPIRE agent. Again, this is
   cheating a bit for the demo.

<!-- @wait -->

2. Next, it uses `spire-server entry create` to create the identity that the
   Linkerd proxy will use.

<!-- @wait -->

3. Given that, it starts the workload running.

<!-- @wait -->

4. After that, it configures `iptables` and starts the proxy running.

<!-- @wait -->

It's short enough that we can go ahead and look through it here -- though,
again, **remember that this is not a production example**.

```bash
bat -l bash bin/bootstrap
```

(The `run-proxy` script we're not going to look much into -- it sets a lot of
static environment variables and then executes `linkerd proxy`.)

<!-- @wait_clear -->

## Starting the External Workloads

So let's actually get these things running...

<!-- @wait -->

...but first, a confession.

I'm not going to use the `faces-external-workload` image I just described,
because we're talking about edge computing... and much of the time that we
talk about edge computing, we're talking about interacting with instruments on
real hardware, right?

<!-- @wait_clear -->

So here's the confession: all three of the machines we're talking about here
are Raspberry Pi 4s sitting on my desk. This includes `cluster-3`, which is
running our cluster: my Macintosh isn't doing anything except running
`kubectl` and `ssh`.

<!-- @show_4 -->

You can see the three machines here: `cluster-1` is on the bottom with the
black knob and two lights connected to it, `cluster-2` is in the middle with
the gold knob and lights, and `cluster-3` is on top, with an external SSD
attached to it (running a Kubernetes cluster off an SD card is horribly slow).

I also have `ghcr.io/buoyantio/faces-pi-workload:1.0.0`, which is just
like `faces-external-workload` except that it knows how to talk to the extra
hardware on `cluster-1` and `cluster-2`. We'll use that instead.

<!-- @wait_clear -->

We'll start the `smiley` workload running on `cluster-1`. First things first:
we'll make sure that the trust anchor is present on `cluster-1`.

**WARNING WARNING WARNING**: We're copying the trust anchor's private key over
the network here. This is a **terrible** idea. Don't **ever** do this outside
of demos.

```bash
rsync -av certs/{ca.crt,ca.key} cluster-1:certs/
```

Next, set up the IP routing we discussed:

```bash
ssh cluster-1 sudo ip route add ${POD_CIDR} via ${NODE_IP}
```

Finally, start our workload running!

```bash
ssh cluster-1 \
    sudo podman run --rm --detach --name smiley \
             --cap-add=NET_ADMIN \
             --dns ${NODE_IP} \
             -v '$(pwd)/certs:/opt/spire/certs' \
             -e WORKLOAD_NAME=smiley \
             -e WORKLOAD_NAMESPACE=faces \
             -e NODE_NAME='$(hostname)' \
             -e FACES_SERVICE=smiley \
             -e DELAY_BUCKETS=0,50,100,200,500,1000 \
             --device /dev/gpiochip0 \
             -p 8000:8000 \
             ghcr.io/buoyantio/faces-pi-workload:1.0.0
```

We'll repeat all that - including the horrible bits like copying certs around
- for the `color` workload running on `cluster-2`.

```bash
rsync -av certs/{ca.crt,ca.key} cluster-2:certs/
ssh cluster-2 sudo ip route add ${POD_CIDR} via ${NODE_IP}

ssh cluster-2 \
    sudo podman run --rm --detach --name color \
             --cap-add=NET_ADMIN \
             --dns ${NODE_IP} \
             -v '$(pwd)/certs:/opt/spire/certs' \
             -e WORKLOAD_NAME=color \
             -e WORKLOAD_NAMESPACE=faces \
             -e NODE_NAME='$(hostname)' \
             -e FACES_SERVICE=color \
             -e DELAY_BUCKETS=0,50,100,200,500,1000 \
             --device /dev/gpiochip0 \
             -p 8000:8000 \
             ghcr.io/buoyantio/faces-pi-workload:1.0.0
```

So far so good. Let's make sure that the containers are running.

```bash
ssh cluster-1 sudo podman logs -f smiley
ssh cluster-2 sudo podman logs -f color
```

<!-- @wait_clear -->

## Creating ExternalWorkload Resources

To tell Linkerd about these external workloads, we'll create ExternalWorkload
resources. These are kind of analogous to Kubernetes Deployment resources, in
that they're a way of telling Linkerd about a workload that it doesn't manage
directly.

First we'll do `smiley`, as before, which is running on `cluster-1`.

```bash
dig +short cluster-1
bat k8s/external-pi-smiley.yaml
kubectl apply -f k8s/external-pi-smiley.yaml
```

Then we'll do the same for `color`, running on `cluster-2`.

```bash
dig +short cluster-2
bat k8s/external-pi-color.yaml
kubectl apply -f k8s/external-pi-color.yaml
```

<!-- @wait_clear -->

## Testing the External Workloads

Now that we have the ExternalWorkload resources created, we can test them out.

First let's look at the Services we have defined:

```bash
kubectl get svc -n faces
```

We see the `smiley` and `color` Services now, which refer to the
ExternalWorkloads we create, so they're a way to talk to our external
containers.

<!-- @wait_clear -->

ExternalWorkloads end up defining EndpointSlices, too:

```bash
kubectl get endpointslices -n faces
```

You can see that there's a "normal" slice created by the usual Kubernetes
EndpointSlice controller, with no Endpoints -- this is because the Kubernetes
EndpointSlice controller doesn't know about our ExternalWorkloads. But there's
also a slice created by the Linkerd EndpointSlice controller, which _does_
know about our ExternalWorkloads, so it has the correct external workload IP
address.

If we go to the browser at this point, we should see things working!

<!-- @wait -->
<!-- @show_6 -->
<!-- @wait -->
<!-- @show_4 -->
<!-- @clear -->

## Level Up

Where things get interesting, of course, is with higher-level functionality.
For example, we can use Linkerd's routing capabilities to control how traffic
flows, even when ExternalWorkloads are involved. Let's start `smiley2` (which
return heart-eyes smileys) and `color2` (which returns blue) running in our
cluster...

```bash
bat k8s/smiley2.yaml
kubectl apply -f k8s/smiley2.yaml
bat k8s/color2.yaml
kubectl apply -f k8s/color2.yaml
kubectl rollout status -n faces deploy
```

...and then we can canary between the two `smiley` workloads, even though
one of them isn't even running in the cluster.

```bash
bat k8s/smiley-route.yaml
kubectl apply -f k8s/smiley-route.yaml
```

If we bring up the browser now, we should see a mix of heart-eyes and
grinning faces.

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
with them.

<!-- @wait_clear -->

<!-- @SHOW -->

A fun trick we can do with real hardware is to snoop the network and make sure
that mTLS is happening.

```bash
ssh cluster-3 sudo tcpdump -w ffs.pcap -s 512 -c 10 -n -A -i eth0 port 8000
ssh cluster-3 sudo tcpdump -r ffs.pcap -n -X | less
```

We can see that the traffic is encrypted, even though it's going to a Pod. We
can also stop traffic from the browser...

<!-- @wait -->
<!-- @show_6 -->
<!-- @wait -->
<!-- @show_2 -->

...then just run a `curl` command directly from a shell on `cluster-3`, and
we'll see that it _won't_ be encrypted:

```bash
ssh cluster-3 sudo tcpdump -w ffs.pcap -s 512 -c 10 -n -A -i eth0 port 8000 &
ssh cluster-3 curl http://cluster-1:8000/
ssh cluster-3 curl http://cluster-1:8000/
ssh cluster-3 curl http://cluster-1:8000/
ssh cluster-3 sudo tcpdump -r ffs.pcap -n -X | less
```

<!-- @wait_clear -->

There's a _lot_ more we could do here -- for example, we can use Linkerd's
authorization mechanisms to prevent that unencrypted `curl`, or use Linkerd's
observability features to watch what happens throughout the application. But
those are topics for another day!

<!-- @wait -->

## Wrapping Up

So there you have it: we've seen how to use ExternalWorkloads to bring
external workloads into the mesh, and seen some examples of how to use
Linkerd's routing can control access to those workloads. We've barely
scratched the surface of what you can do with a service mesh extending
beyond the cluster, but we've seen enough to know that it's a powerful
tool.

<!-- @wait -->

Also remember: in this demo, we did everything the hard way. In an
upcoming BEL release, it will be dramatically easier to get all this
done, so keep your eyes open for that.

Finally, feedback is always welcome! You can reach me at
flynn@buoyant.io or as @flynn on the Linkerd Slack
(https://slack.linkerd.io).

<!-- @wait -->
<!-- @show_4 -->
<!-- @wait -->
<!-- @show_slides -->

## Authorization Policy

Right now, we can talk directly to our smiley workload (running on
`cluster-1`) from our host.

```bash
curl -s -w "%{http_code}\n" -o /dev/null http://cluster-1/
```

Let's use a Linkerd AuthorizationPolicy to lock that down. We'll create a
Linkerd Server resource that covers our external workloads, and give it a
default-deny stance.

```bash
bat k8s/external-server.yaml
kubectl apply -f k8s/external-server.yaml
```

Now we should _not_ be able to access the external workloads from our unmeshed
client.

```bash
kubectl exec -it -n mixed-env -c curl curl-not-meshed -- \
        curl -s -w "%{http_code}\n" -o /dev/null http://external-workload-1/
```

So far so good!

<!-- @wait_clear -->

## Allowing Some Access

It turns out, though, that there's a bit of a problem: we also can't access
the external workload from a meshed client.

```bash
kubectl exec -it -n mixed-env -c curl curl-meshed -- \
        curl -s -w "%{http_code}\n" -o /dev/null http://external-workload-1/
```

We also can't access one external workload from another external workload:

```bash
docker exec -it external-workload-1-ep-1 \
       curl -s -w "%{http_code}\n" -o /dev/null \
            http://external-workload-2.mixed-env.svc.cluster.local/
```

Let's start with the meshed client in the cluster. Allowing access there, of
course, requires a Linkerd AuthorizationPolicy.

```bash
bat demo-k8s/cluster-auth.yaml
kubectl apply -f demo-k8s/cluster-auth.yaml
```

Now we can access the external workload from our meshed `curl` Pod:

```bash
kubectl exec -it -n mixed-env -c curl curl-meshed -- \
        curl -s -w "%{http_code}\n" -o /dev/null http://external-workload-1/
```

<!-- @wait_clear -->

## Allowing External-External Access

At this point, we can access the external workloads from our meshed `curl` Pod
in the cluster, but access from one external workload to another is still
blocked:

```bash
docker exec -it external-workload-1-ep-1 \
       curl -s -w "%{http_code}\n" -o /dev/null \
            http://external-workload-2.mixed-env.svc.cluster.local/
```

We can fix that with another Linkerd AuthorizationPolicy. (We could also edit
the existing MeshTLSAuthentication, but it might be a touch more clear this
way.)

```bash
bat demo-k8s/external-auth.yaml
kubectl apply -f demo-k8s/external-auth.yaml
```

Now we should be able to access an external workload from a different external
workload:

```bash
docker exec -it external-workload-1-ep-1 \
       curl -s -w "%{http_code}\n" -o /dev/null \
            http://external-workload-2.mixed-env.svc.cluster.local/
```

Access from the meshed `curl` Pod in the cluster is still allowed, of course.

```bash
kubectl exec -it -n mixed-env -c curl curl-meshed -- \
        curl -s -w "%{http_code}\n" -o /dev/null http://external-workload-1/
```

And access from the unmeshed `curl` Pod in the cluster is still not allowed.

```bash
kubectl exec -it -n mixed-env -c curl curl-not-meshed -- \
        curl -s -w "%{http_code}\n" -o /dev/null http://external-workload-1/
```

<!-- @wait_clear -->

## Wrapping Up

So that's mesh expansion! We've seen how to use ExternalWorkloads to bring
external workloads into the mesh, and seen some examples of how to use
Linkerd's routing and authorization policies can control access to those
workloads. We'll be taking a deeper dive into all this at the next Service Mesh Academy on February 15th, so please join us for that!

Finally, feedback is always welcome! You can reach me at flynn@buoyant.io or
as @flynn on the Linkerd Slack (https://slack.linkerd.io).

<!-- @wait -->
<!-- @show_browser -->

<!-- @wait_clear -->

## Locking Down Access

So let's start by preventing that. We'll create a Linkerd Server resource that
covers our external workloads, and give it a default-deny stance.

```bash
bat demo-k8s/external-server.yaml
kubectl apply -f demo-k8s/external-server.yaml
```

Now we should _not_ be able to access the external workloads from our unmeshed
client.

```bash
kubectl exec -it -n mixed-env -c curl curl-not-meshed -- \
        curl -s -w "%{http_code}\n" -o /dev/null http://external-workload-1/
```

So far so good!

<!-- @wait_clear -->

## Allowing Some Access

It turns out, though, that there's a bit of a problem: we also can't access
the external workload from a meshed client.

```bash
kubectl exec -it -n mixed-env -c curl curl-meshed -- \
        curl -s -w "%{http_code}\n" -o /dev/null http://external-workload-1/
```

We also can't access one external workload from another external workload:

```bash
docker exec -it external-workload-1-ep-1 \
       curl -s -w "%{http_code}\n" -o /dev/null \
            http://external-workload-2.mixed-env.svc.cluster.local/
```

Let's start with the meshed client in the cluster. Allowing access there, of
course, requires a Linkerd AuthorizationPolicy.

```bash
bat demo-k8s/cluster-auth.yaml
kubectl apply -f demo-k8s/cluster-auth.yaml
```

Now we can access the external workload from our meshed `curl` Pod:

```bash
kubectl exec -it -n mixed-env -c curl curl-meshed -- \
        curl -s -w "%{http_code}\n" -o /dev/null http://external-workload-1/
```

<!-- @wait_clear -->

## Allowing External-External Access

At this point, we can access the external workloads from our meshed `curl` Pod
in the cluster, but access from one external workload to another is still
blocked:

```bash
docker exec -it external-workload-1-ep-1 \
       curl -s -w "%{http_code}\n" -o /dev/null \
            http://external-workload-2.mixed-env.svc.cluster.local/
```

We can fix that with another Linkerd AuthorizationPolicy. (We could also edit
the existing MeshTLSAuthentication, but it might be a touch more clear this
way.)

```bash
bat demo-k8s/external-auth.yaml
kubectl apply -f demo-k8s/external-auth.yaml
```

Now we should be able to access an external workload from a different external
workload:

```bash
docker exec -it external-workload-1-ep-1 \
       curl -s -w "%{http_code}\n" -o /dev/null \
            http://external-workload-2.mixed-env.svc.cluster.local/
```

Access from the meshed `curl` Pod in the cluster is still allowed, of course.

```bash
kubectl exec -it -n mixed-env -c curl curl-meshed -- \
        curl -s -w "%{http_code}\n" -o /dev/null http://external-workload-1/
```

And access from the unmeshed `curl` Pod in the cluster is still not allowed.

```bash
kubectl exec -it -n mixed-env -c curl curl-not-meshed -- \
        curl -s -w "%{http_code}\n" -o /dev/null http://external-workload-1/
```

<!-- @wait_clear -->

## Wrapping Up

So that's mesh expansion! We've seen how to use ExternalWorkloads to bring
external workloads into the mesh, and seen some examples of how to use
Linkerd's routing and authorization policies can control access to those
workloads. We'll be taking a deeper dive into all this at the next Service Mesh Academy on February 15th, so please join us for that!

Finally, feedback is always welcome! You can reach me at flynn@buoyant.io or
as @flynn on the Linkerd Slack (https://slack.linkerd.io).

<!-- @wait -->
<!-- @show_browser -->
