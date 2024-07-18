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
any Docker containers named `smiley` and `color` stuff. Be careful!

When you use `demosh` to run this file, requirements will be checked for
you.

<!-- set -e >
<!-- @import demosh/check-requirements.sh -->

<!-- @start_livecast -->

```bash
BAT_STYLE="grid,numbers"
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

Once that's done, let's get Linkerd up and running... but, first, let's make
sure we have the correct version installed (you need `edge-24.2.5` or later
for this).

```bash
curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install-edge | sh
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

OK! If we flip over to look at the GUI right now (at http://localhost/), we
should see grinning faces on green backgrounds.

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

   Once that's done, we can get the IP address of the `dnsmasq` container to
   use later.

```bash
DNS_IP=$(docker inspect dnsmasq | jq -r '.[].NetworkSettings.Networks["mesh-exp"].IPAddress')
#@immed
echo "DNS_IP is ${DNS_IP}"
```

<!-- @wait_clear -->

Taking all that into account, we need a Docker image that contains the Linkerd
proxy, the SPIRE agent, the SPIRE server (remember, this is a hack!), and of
course our actual workload. We also need a bootstrap script that sets up the
world for us.

`ghcr.io/buoyantio/faces-external-workload:1.0.0` is such an image. Actually
building it isn't that complex: the magic is in the bootstrap.

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

So let's actually get some containers running, starting with the `smiley`
workload in a container called `smiley`.

```bash
#@immed
docker kill smiley >/dev/null 2>&1
#@immed
docker rm smiley >/dev/null 2>&1
docker run --rm --detach \
       --cap-add=NET_ADMIN \
       --network=mesh-exp \
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

We'll repeat exactly that for the `color` workload.

```bash
#@immed
docker kill color >/dev/null 2>&1
#@immed
docker rm color >/dev/null 2>&1
docker run --rm --detach \
       --cap-add=NET_ADMIN \
       --network=mesh-exp \
       --dns=${DNS_IP} \
       --name=color \
       -v "$(pwd)/certs:/opt/spire/certs" \
       -e WORKLOAD_NAME=color \
       -e WORKLOAD_NAMESPACE=faces \
       -e NODE_NAME='$(hostname)' \
       -e FACES_SERVICE=color \
       -e DELAY_BUCKETS=0,50,100,200,500,1000 \
       ghcr.io/buoyantio/faces-external-workload:1.0.0 \
  && docker exec color ip route add ${POD_CIDR} via ${NODE_IP}
```

So far so good. Let's make sure that the containers are running.

```bash
docker ps -a
```

<!-- @wait_clear -->

## Creating ExternalWorkload Resources

To tell Linkerd about these external workloads, we'll create ExternalWorkload
resources. These are kind of analogous to Kubernetes Deployment resources, in
that they're a way of telling Linkerd about a workload that it doesn't manage
directly.

First we'll do `smiley`, as before. We start by finding the
IP address of the container...

```bash
SMILEY_ADDR=$(docker inspect smiley | jq -r '.[].NetworkSettings.Networks["mesh-exp"].IPAddress')
#@immed
echo "SMILEY_ADDR is ${SMILEY_ADDR}"

sed -e "s/%%NAME%%/smiley/g" -e "s/%%IP%%/${SMILEY_ADDR}/g" \
    < ./k8s/external-workload.yaml.tmpl \
    > /tmp/smiley.yaml

bat /tmp/smiley.yaml

kubectl apply -f /tmp/smiley.yaml
```

Then we'll do the same for `color`.

```bash
COLOR_ADDR=$(docker inspect color | jq -r '.[].NetworkSettings.Networks["mesh-exp"].IPAddress')
#@immed
echo "COLOR_ADDR is ${COLOR_ADDR}"

sed -e "s/%%NAME%%/color/g" -e "s/%%IP%%/${COLOR_ADDR}/g" \
    < ./k8s/external-workload.yaml.tmpl \
    > /tmp/color.yaml

bat /tmp/color.yaml

kubectl apply -f /tmp/color.yaml
```

We also need to set the `status` on the ExternalWorkload so that Linkerd will
consider them ready to use:

```bash
kubectl patch externalworkloads -n faces smiley \
        --type=merge --subresource status \
        --patch 'status: { conditions: [ { type: Ready, status: "True" } ] }'
kubectl patch externalworkloads -n faces color \
        --type=merge --subresource status \
        --patch 'status: { conditions: [ { type: Ready, status: "True" } ] }'
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

<!-- @browser_then_terminal -->

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
with them. As such, there's a _lot_ more we could do here -- for example, we
haven't looked at Linkerd's authorization and observability features at all.
Those are topics for another day!

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
<!-- @show_slides -->
