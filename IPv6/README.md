<!--
SPDX-FileCopyrightText: 2024 Buoyant Inc.
SPDX-License-Identifier: Apache-2.0

SMA-Description: Using Linkerd in IPv6 and dualstack Kubernetes clusters
-->

# Linkerd and IPv6

This is the documentation - and executable code! - for the Service Mesh
Academy workshop about Linkerd and IPv6. The easiest way to use this file is
to execute it with [demosh].

Things in Markdown comments are safe to ignore when reading this later. When
executing this with [demosh], things after the horizontal rule below (which
is just before a commented `@SHOW` directive) will get displayed.

[demosh]: https://github.com/BuoyantIO/demosh

This workshop requires Kind, and will destroy any Kind clusters named
"sma-v4", "sma-v6", and "sma-dual".

<!-- @import demosh/check-requirements.sh -->
<!-- @start_livecast -->
---
<!-- @SHOW -->

# Linkerd and IPv6

This workshop will show you how to use Linkerd in an IPv6 or dualstack
Kubernetes cluster. We'll start by creating three Kind clusters: `sma-v4` will
be IPv4-only, `sma-v6` will be IPv6-only, and `sma-dual` will be dualstack.

These clusters will all have a single node, and will be on the same Docker
network. They'll differ in their network stack configurations.

```bash
#@immed
kind delete cluster --name sma-v4 >/dev/null 2>&1
#@immed
kind delete cluster --name sma-v6 >/dev/null 2>&1
#@immed
kind delete cluster --name sma-dual >/dev/null 2>&1
kind get clusters
bat sma-v4/kind.yaml
kind create cluster --config sma-v4/kind.yaml

bat sma-v6/kind.yaml
kind create cluster --config sma-v6/kind.yaml

bat sma-dual/kind.yaml
kind create cluster --config sma-dual/kind.yaml
```

OK! At this point all three clusters are up and running, attached to the same
Docker network, which is called `kind`. Next up we're going to rename our
Kubernetes contexts to match the cluster names.

```bash
#@immed
kubectl config delete-context sma-v4 >/dev/null 2>&1
kubectl config rename-context kind-sma-v4 sma-v4
#@immed
kubectl config delete-context sma-v6 >/dev/null 2>&1
kubectl config rename-context kind-sma-v6 sma-v6
#@immed
kubectl config delete-context sma-dual >/dev/null 2>&1
kubectl config rename-context kind-sma-dual sma-dual
```

<!-- @wait_clear -->

## Kind and MetalLB

Kind, it turns out, doesn't have built-in load balancer support. I really
don't like using port forwards when I have multiple clusters going on, so
let's get load balancer services working using MetalLB.

**Note:** if you're using Docker Desktop on a Macintosh, this section is
probably not going to work for you, since Docker Desktop doesn't really bridge
the Docker network to the host. Instead, use Orbstack, from
<https://orbstack.dev/>, which is much more graceful about networking.

<!-- @wait -->

MetalLB, at <https://metallb.io/>, is a bare-metal load balancer for
Kubernetes. We're going to use it in its simplest "Layer 2" mode, which
basically just allocates IP addresses out of a pool we configure it with and
trusts that the network around it already knows how to route to the addresses
it allocates -- so we need to look at our Docker network to figure out which
address ranges it already knows about, and use some of them.

```bash
docker network inspect kind | jq '.[0].IPAM.Config'
```

(`IPAM` stands for "IP Address Management".) We have two available ranges, one
for IPv4 and one for IPv6, and we need subranges from the appropriate sections
for our clusters to use for load balancers. This is annoying in the shell, so
we'll use a Python script to manage it instead.

```bash
bat choose-ipam.py
docker network inspect kind | python3 choose-ipam.py
bat sma-v4/metallb.yaml
bat sma-v6/metallb.yaml
bat sma-dual/metallb.yaml
```

<!-- @wait_clear -->

## Installing MetalLB

```bash
helm repo add --force-update metallb https://metallb.github.io/metallb

helm install --kube-context sma-v4 \
     -n metallb --create-namespace \
     metallb metallb/metallb

helm install --kube-context sma-v6 \
     -n metallb --create-namespace \
     metallb metallb/metallb

helm install --kube-context sma-dual \
     -n metallb --create-namespace \
     metallb metallb/metallb
```

Once that's done, we can wait for the MetalLB pods to be ready...

```bash
kubectl --context sma-v4 rollout status -n metallb deploy
kubectl --context sma-v6 rollout status -n metallb deploy
kubectl --context sma-dual rollout status -n metallb deploy
```

...and then we can configure MetalLB in all clusters.

```bash
kubectl --context sma-v4 apply -f sma-v4/metallb.yaml
kubectl --context sma-v6 apply -f sma-v6/metallb.yaml
kubectl --context sma-dual apply -f sma-dual/metallb.yaml
```

Now we should have working load balancers everywhere... so let's get Faces
installed!

<!-- @wait_clear -->

## Installing Faces

We're going to install Faces in all three clusters. We'll tell Faces to use a
LoadBalancer service for its GUI so that Faces can act like its own ingress
controller, and we're going to disable errors in the backend and face
services. We're also using a different background color for each cluster: red
for sma-v4, green for sma-v6, and the default blue for sma-dual.

**Note**: in practice, you really should use an ingress controller for this
kind of thing. We're cheating and using Faces to handle its own ingress
because the demo setup is complex enough as it is!

```bash
helm install --kube-context sma-v4 faces \
     -n faces --create-namespace \
     oci://ghcr.io/buoyantio/faces-chart --version 1.4.0 \
     --set gui.serviceType=LoadBalancer \
     --set face.errorFraction=0 \
     --set backend.errorFraction=0 \
     --set color.color=red

helm install --kube-context sma-v6 faces \
     -n faces --create-namespace \
     oci://ghcr.io/buoyantio/faces-chart --version 1.4.0 \
     --set gui.serviceType=LoadBalancer \
     --set face.errorFraction=0 \
     --set backend.errorFraction=0 \
     --set color.color=green

helm install --kube-context sma-dual faces \
     -n faces --create-namespace \
     oci://ghcr.io/buoyantio/faces-chart --version 1.4.0 \
     --set gui.serviceType=LoadBalancer \
     --set face.errorFraction=0 \
     --set backend.errorFraction=0
```

We're also going to patch in a custom ServiceAccount for the `face` workload
in the sma-dual cluster (spoiler alert: we're going to use this for
authentication later!). Sadly, we can't yet do this with the Faces Helm chart.

```bash
kubectl --context sma-dual create serviceaccount -n faces face-sma-dual
kubectl --context sma-dual patch deploy -n faces face \
        --type=merge \
        --patch 'spec: { template: { spec: { serviceAccountName: face-sma-dual } } }'
```

OK! Now we wait for all the Faces pods to be ready.

```bash
kubectl --context sma-v4 rollout status -n faces deploy
kubectl --context sma-v6 rollout status -n faces deploy
kubectl --context sma-dual rollout status -n faces deploy
```

<!-- @wait_clear -->

## Testing Faces

Let's grab the external IP addresses of our `faces-gui` Services for
testing...

```bash
V4_LB=$(kubectl --context sma-v4 get svc -n faces faces-gui -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
#@immed
echo "sma-v4 Faces IP: http://${V4_LB}/"
V6_LB=$(kubectl --context sma-v6 get svc -n faces faces-gui -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
#@immed
echo "sma-v6 Faces IP: http://[${V6_LB}]"
DUAL_LB=$(kubectl --context sma-dual get svc -n faces faces-gui -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
#@immed
echo "sma-dual Faces IP: http://[${DUAL_LB}]"
```

We can check those in the browser.

<!-- @browser_then_terminal -->

## Installing Linkerd

Let's install Linkerd in all three clusters... and let's do it in a way that
lets us do multicluster stuff later! This means we need to start by creating
some certificates. We're going to use `step` for this, but we're not going to
go into all the details -- check out the Multicluster SMA for more here.

```bash
#@immed
rm -rf certs
#@immed
mkdir certs

step certificate create \
  root.linkerd.cluster.local \
  certs/root.crt certs/root.key \
  --profile root-ca \
  --no-password --insecure

step certificate create \
  identity.linkerd.cluster.local \
  certs/v4-issuer.crt certs/v4-issuer.key \
  --profile intermediate-ca \
  --ca certs/root.crt \
  --ca-key certs/root.key \
  --not-after 8760h \
  --no-password --insecure

step certificate create \
  identity.linkerd.cluster.local \
  certs/v6-issuer.crt certs/v6-issuer.key \
  --profile intermediate-ca \
  --ca certs/root.crt \
  --ca-key certs/root.key \
  --not-after 8760h \
  --no-password --insecure

step certificate create \
  identity.linkerd.cluster.local \
  certs/dual-issuer.crt certs/dual-issuer.key \
  --profile intermediate-ca \
  --ca certs/root.crt \
  --ca-key certs/root.key \
  --not-after 8760h \
  --no-password --insecure
```

<!-- @wait_clear -->

## Installing Linkerd

OK, we have certs! Time to install Linkerd.

```bash
curl -sL https://run.linkerd.io/install-edge | sh
export PATH=$PATH:$HOME/.linkerd2/bin

linkerd install --context sma-v4 --crds | kubectl --context sma-v4 apply -f -
linkerd install --context sma-v4 \
    --identity-trust-anchors-file certs/root.crt \
    --identity-issuer-certificate-file certs/v4-issuer.crt \
    --identity-issuer-key-file certs/v4-issuer.key \
  | kubectl --context sma-v4 apply -f -
```

When we install Linkerd into our IPv6-capable clusters, we need to set
`disableIPv6` to `false` so that Linkerd's IPv6 support is enabled.

```bash
linkerd install --context sma-v6 --crds | kubectl --context sma-v6 apply -f -
linkerd install --context sma-v6 \
    --set disableIPv6=false  \
    --identity-trust-anchors-file certs/root.crt \
    --identity-issuer-certificate-file certs/v6-issuer.crt \
    --identity-issuer-key-file certs/v6-issuer.key \
  | kubectl --context sma-v6 apply -f -

linkerd install --context sma-dual --crds | kubectl --context sma-dual apply -f -
linkerd install --context sma-dual \
    --set disableIPv6=false  \
    --identity-trust-anchors-file certs/root.crt \
    --identity-issuer-certificate-file certs/dual-issuer.crt \
    --identity-issuer-key-file certs/dual-issuer.key \
  | kubectl --context sma-dual apply -f -
```

Once that's done, we can check that Linkerd is up and running in all three
clusters.

```bash
linkerd check --context sma-v4
linkerd check --context sma-v6
linkerd check --context sma-dual
```

<!-- @wait_clear -->

## Meshing Faces

Now that Linkerd is installed, let's get Faces meshed in all three clusters.
This won't produce any visible change from the GUI -- we'll have to check the
pods in the `faces` namespace to see that the proxies are injected at this
point.

```bash
kubectl --context sma-v4 annotate namespace faces linkerd.io/inject=enabled
kubectl --context sma-v4 rollout restart -n faces deploy

kubectl --context sma-v6 annotate namespace faces linkerd.io/inject=enabled
kubectl --context sma-v6 rollout restart -n faces deploy

kubectl --context sma-dual annotate namespace faces linkerd.io/inject=enabled
kubectl --context sma-dual rollout restart -n faces deploy

kubectl --context sma-v4 rollout status -n faces deploy
kubectl --context sma-v6 rollout status -n faces deploy
kubectl --context sma-dual rollout status -n faces deploy

kubectl --context sma-v4 get pods -n faces
kubectl --context sma-v6 get pods -n faces
kubectl --context sma-dual get pods -n faces
```

We'll flip back over to the browser just to make sure everything still looks
good.

<!-- @browser_then_terminal -->

## Switching to v4 `smiley`

If we look in the `sma-dual` cluster, we'll see that all its Services have
IPv6 addresses.

```bash
kubectl --context sma-dual get svc -n faces
```

Let's switch `smiley` to use an IPv4 address instead. You can't just `kubectl
edit` the Service for this, because it already has the IPv6 address
information in it. Instead, we'll delete the Service and recreate it with the
correct address family.

We'll start by getting the current `smiley` Service into a file and editing it
to switch it to IPv4.

```bash
kubectl --context sma-dual get svc -n faces -o yaml smiley > smiley.yaml
${EDITOR} smiley.yaml
```

Next up, we'll delete the `smiley` Service. This will break everything!

<!-- @show_5 -->

```bash
kubectl --context sma-dual delete svc -n faces smiley
```

When we recreate the `smiley` Service, it'll have an IPv4
address, but everything should start working again.

```bash
kubectl --context sma-dual apply -f smiley.yaml
kubectl --context sma-dual get svc -n faces smiley
```

<!-- @wait_clear -->

## Network Authentication

Next, let's do a minimal lockdown of the `faces` namespace in the `sma-dual`
cluster. We'll start by switching it to have a default policy of deny, which
will - again - break everything as soon as we restart the `faces` pods.

<!-- @show_5 -->

```bash
kubectl --context sma-dual annotate ns/faces \
        config.linkerd.io/default-inbound-policy=deny
kubectl --context sma-dual rollout restart -n faces deploy
kubectl --context sma-dual rollout status -n faces deploy
```

Now that we've so definitively broken everything, let's
fix it by adding a NetworkAuthentication to permit access
from within the `sma-dual` cluster.

```bash
bat k8s/network-auth-1.yaml
kubectl --context sma-dual apply -f k8s/network-auth-1.yaml
```

Talking to `color` is working now! but note that we still
can't talk to `smiley`! Looking back at the `smiley` Service
will show what's going on:

```bash
kubectl --context sma-dual get svc -n faces
```

The `smiley` Service has an IPv4 address, remember? We need
to explicitly authorize the IPv4 CIDR for `sma-dual` as well.

```bash
diff -u19 --color k8s/network-auth-1.yaml k8s/network-auth-2.yaml
kubectl --context sma-dual apply -f k8s/network-auth-2.yaml
```

That lets everything start working again!

<!-- @wait_clear -->
<!-- @show_terminal -->

## Multicluster setup

Next up, let's try dualstack multicluster. First things first: when Kind
creates a cluster, it sets up a port forward for its API server and gives you
a Kubernetes config that uses that port forward. This is great for a single
cluster, but it's not so great for multicluster -- so we're going to update
all our configurations to use the node IP addresses directly.

(When doing this, we have to use the full names like `kind-sma-v4` because
when we changed the _context_ name, we didn't change the _cluster_ name.)

```bash
V4_NODE=$(kubectl --context sma-v4 get nodes -ojsonpath='{.items[0].status.addresses[0].address}')
#@immed
echo "V4_NODE is ${V4_NODE}"
kubectl config set clusters.kind-sma-v4.server "https://${V4_NODE}:6443"

V6_NODE=$(kubectl --context sma-v6 get nodes -ojsonpath='{.items[0].status.addresses[0].address}')
#@immed
echo "V6_NODE is ${V6_NODE}"
kubectl config set clusters.kind-sma-v6.server "https://[${V6_NODE}]:6443"

DUAL_NODE=$(kubectl --context sma-dual get nodes -ojsonpath='{.items[0].status.addresses[0].address}')
#@immed
echo "DUAL_NODE is ${DUAL_NODE}"
kubectl config set clusters.kind-sma-dual.server "https://[${DUAL_NODE}]:6443"
```

We also need to set up routing between clusters. This is easy when routing
from `sma-dual` to `sma-v4` or from `sma-dual` to `sma-v6` - we just route to
the single CIDR that `sma-v4` or `sma-v6` have - but routing back _to_
`sma-dual` requires being more careful: in `sma-v4` we need to route to
`sma-dual`'s IPv4 CIDR, and in `sma-v6` we need to route to `sma-dual`'s IPv6
CIDR.

So, again, we'll use a Python script to sort things out.

```bash
bat get_info.py

V4_POD_CIDR=$(python3 get_info.py --cidr --v4 sma-v4)
#@immed
echo "V4_POD_CIDR is ${V4_POD_CIDR}"
V4_NODE_IP=$(python3 get_info.py --nodeip --v4 sma-v4)
#@immed
echo "V4_NODE_IP is ${V4_NODE_IP}"

V6_POD_CIDR=$(python3 get_info.py --cidr --v6 sma-v6)
#@immed
echo "V6_POD_CIDR is ${V6_POD_CIDR}"
V6_NODE_IP=$(python3 get_info.py --nodeip --v6 sma-v6)
#@immed
echo "V6_NODE_IP is ${V6_NODE_IP}"

DUAL_POD_CIDR_V4=$(python3 get_info.py --cidr --v4 sma-dual)
#@immed
echo "DUAL_POD_CIDR_V4 is ${DUAL_POD_CIDR_V4}"
DUAL_NODE_IP_V4=$(python3 get_info.py --nodeip --v4 sma-dual)
#@immed
echo "DUAL_NODE_IP_V4 is ${DUAL_NODE_IP_V4}"

DUAL_POD_CIDR_V6=$(python3 get_info.py --cidr --v6 sma-dual)
#@immed
echo "DUAL_POD_CIDR_V6 is ${DUAL_POD_CIDR_V6}"
DUAL_NODE_IP_V6=$(python3 get_info.py --nodeip --v6 sma-dual)
#@immed
echo "DUAL_NODE_IP_V6 is ${DUAL_NODE_IP_V6}"
```

Now we can set up routing.

```bash
docker exec sma-v4-control-plane \
  ip route add ${DUAL_POD_CIDR_V4} via ${DUAL_NODE_IP_V4}
docker exec sma-v6-control-plane \
  ip route add ${DUAL_POD_CIDR_V6} via ${DUAL_NODE_IP_V6}
docker exec sma-dual-control-plane \
  ip route add ${V4_POD_CIDR} via ${V4_NODE_IP}
docker exec sma-dual-control-plane \
  ip route add ${V6_POD_CIDR} via ${V6_NODE_IP}
```

<!-- @wait_clear -->

## Linking the Clusters

We're going to use `sma-dual` as our "main" cluster: it'll have the Faces GUI
and the `face` workload. We'll run `color` in `sma-v4` and `smiley` in
`sma-v6`. This will, of course, require Linkerd to pick the correct protocol
for whatever cluster it's talking to.

We'll start by installing multicluster Linkerd in all three clusters.

```bash
linkerd --context=sma-v4 multicluster install --gateway=false \
  | kubectl --context=sma-v4 apply -f -
linkerd --context=sma-v6 multicluster install --gateway=false \
  | kubectl --context=sma-v6 apply -f -
linkerd --context=sma-dual multicluster install --gateway=false \
  | kubectl --context=sma-dual apply -f -

linkerd --context=sma-v4 multicluster check
linkerd --context=sma-v6 multicluster check
linkerd --context=sma-dual multicluster check
```

Now we can link the clusters. We only need to link from `sma-dual` to the
other two, since we only need to mirror into `sma-dual`.

```bash
linkerd multicluster --context=sma-v4 link \
    --gateway=false \
    --cluster-name=sma-v4 \
    | kubectl --context sma-dual apply -f -

linkerd multicluster --context=sma-v6 link \
    --gateway=false \
    --cluster-name=sma-v6 \
    | kubectl --context sma-dual apply -f -
```

Let's make sure that the links are up.

```bash
linkerd --context=sma-dual multicluster check
```

<!-- @wait_clear -->

## Mirroring Services

Once our links are up, we can mirror the `smiley` service from `sma-v4` into
`sma-dual`, and the `color` service from `sma-v6` into `sma-dual`.

```bash
kubectl --context sma-v4 -n faces label svc/smiley \
        mirror.linkerd.io/exported=remote-discovery
kubectl --context sma-v6 -n faces label svc/color \
        mirror.linkerd.io/exported=remote-discovery
```

At this point, we should see the mirrored services in `sma-dual`.

```bash
kubectl --context sma-dual -n faces get svc
```

Note that the mirrored `smiley-sma-v4` actually has an IPv6 address! But check
this out:

```bash
linkerd --context sma-dual dg endpoints smiley-sma-v4.faces.svc.cluster.local
```

What's going on here is that the Linkerd proxy can notice the application
workload trying to talk to `smiley-sma-v4` using IPv6, and seamlessly
translate that into an IPv4 connection across to the `smiley` service in
`sma-v4`. This is a great example of how Linkerd's IPv6 support is pretty much
invisible in practice.

<!-- @wait_clear -->

## Testing Multicluster

Now that all THAT is done, suppose we just delete the `smiley` workload in
`sma-dual` and watch what happens!

<!-- @show_5 -->

```bash
kubectl --context sma-dual delete deploy -n faces smiley
```

As expected, with no `smiley` service, things break! So let's
use an HTTPRoute to send all the traffic from the Faces app in
`sma-dual` over to the `smiley` deployment in `sma-v4`.

```bash
bat k8s/smiley-route.yaml
kubectl --context sma-dual apply -f k8s/smiley-route.yaml
```

<!-- @wait_clear -->

## Multicluster Canarying

Of course, we don't have to shift traffic all at once. We can also do a canary
across clusters, whether or not they're the same address family. Let's show
that with the `color` workload.

```bash
bat k8s/color-route.yaml
kubectl --context sma-dual apply -f k8s/color-route.yaml
```

And, of course, we can edit the weights as usual.

```bash
kubectl --context sma-dual edit httproute -n faces color-route
kubectl --context sma-dual edit httproute -n faces color-route
kubectl --context sma-dual edit httproute -n faces color-route
```

<!-- @wait_clear -->

## Multicluster Authentication

Next, let's do a minimal lockdown of the `faces` namespace in the `sma-v6`
cluster, like we did for `sma-dual`. Once again, we'll start by switching it
to have a default policy of deny.

```bash
kubectl --context sma-v6 annotate ns/faces \
        config.linkerd.io/default-inbound-policy=deny
kubectl --context sma-v6 rollout restart -n faces deploy
kubectl --context sma-v6 rollout status -n faces deploy
```

Now that we've broken everything again, let's fix it. This time,
we'll use a MeshTLSAuthentication to permit access from the `face`
workload in `sma-dual`. If you remember, we created a special
ServiceAccount just for `face` -- this is why.

```bash
bat k8s/tls-auth.yaml
kubectl --context sma-v6 apply -f k8s/tls-auth.yaml
```

And now everything works again!

<!-- @wait_clear -->
<!-- @show_terminal -->

## Wrapping Up

So that's Linkerd running in IPv4-only, IPv6-only, and dualstack clusters,
with some basic multicluster, authentication policy, and Gateway API
functionality thrown in for good measure. As you've seen, Linkerd makes IPv6
pretty much invisible in practice, so you can use it in your clusters without
worrying too much about it.

<!-- @wait -->

Finally, feedback is always welcome! You can reach me at flynn@buoyant.io or
as @flynn on the Linkerd Slack (https://slack.linkerd.io).

<!-- @wait -->
<!-- @show_slides -->
