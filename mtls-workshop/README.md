# mTLS workshop

This is the documentation - and executable code! - for the Service Mesh
Academy mTLS workshop. The easiest way to use this file is to execute it with
[demosh].

Things in Markdown comments are safe to ignore when reading this later. When
executing this with [demosh], things after the horizontal rule below (which is
just before a commented `@SHOW` directive) will get displayed.

[demosh]: https://github.com/BuoyantIO/demosh

This workshop requires that you have a running Kubernetes cluster. If you want
to create a `k3d` cluster for this, [CREATE.md](CREATE.md) has what you need!
Otherwise, make sure your cluster is called `mtls` – if you named it something
else, you can either substitute its name for `mtls` in the commands below, or
use `kubectl config rename-context` to rename your cluster's context to match.

<!-- @import demo-tools.sh -->
<!-- @import check-requirements.sh -->
<!-- @start_livecast -->
---
<!-- @SHOW -->

In this workshop, we will deploy Linkerd to a cluster, inject some example
workloads and then verify that mTLS between two parties (i.e a client and a
server) works correctly.

All manifests used in the demo are in the `/manifests` directory, for some
additional work after the workshop, check out the homework assignment in
HOMEWORK.md.

First things first: make sure that everything is set up for the workshop.

```bash
#@$SHELL CREATE.md
#@$SHELL INSTALL-LINKERD.md
```

OK, everything should be ready to go!

<!-- @wait_clear -->

## Verifying TLS

Now that everything is running, we'll use `tshark` to watch network traffic in
the cluster and be certain that mTLS is happening. The easiest way to get this
up and running is through Linkerd's debug sidecar, which you can read more
about at https://linkerd.io/2.12/tasks/using-the-debug-container/.

You can enable the debug sidecar with the
```
config.linkerd.io/enable-debug-sidecar
```
annotation, placed onto the Pod template of a Deployment, for example.

We'll verify the security of a connection using two example workloads: our
client will be a `curl` Deployment (see `manifests/curl.yaml`), and our server
will be an `NGINX` deployment (see `manifests/nginx-deploy.yaml`).

<!-- @wait_clear -->

### 1. Deploy and inject `curl`

First up, let's look at the `curl` Deployment:

```bash
less manifests/curl.yaml
```

This is pretty straightforward, and we'll inject it into the mesh from the
start:

```bash
linkerd inject manifests/curl.yaml | kubectl apply -f -

kubectl wait pod --for=condition=ready -l app=curl
```

### 2. Deploy, but do not inject, `NGINX`

Once our `curl` pod is ready, we can deploy `NGINX`. Note we've included the
Linkerd debug sidecar in here by hand:

```bash
less manifests/nginx-deploy.yaml
```

The reason we're not using the annotation is that we're going to deploy this
_without_ injecting it at first, so Linkerd wouldn't ever read the annotation!

```bash
kubectl apply -f manifests/nginx-deploy.yaml

kubectl wait pod --for=condition=ready -l app=nginx-deploy
```

<!-- @wait_clear -->

### 3. Spoiler alert: look at `linkerd viz`

At this point, we've installed NGINX, but it's not participating in the mesh.
Let's see how that looks in the `linkerd viz` dashboard. (You might remember
from other workshops that I typically do this using the ingress controller...
but of course, reaching `linkerd viz` from an unmeshed ingress controller
isn't going to work!)

```bash
linkerd viz dashboard
```

<!-- @show_terminal -->

As you might imagine, it's _very_ easy to see that NGINX isn't meshed yet, but
let's go ahead and look deeper anyway.

### 4. Start `tshark` running

In order to use `tshark` to look at the details of what's going on in the
cluster, we'll start it running in the `NGINX` pod's debug sidecar. Since
we'll need to leave it running while we do some requests, we'll do this in a
separate window.

```bash
NGINX=$(kubectl get pods -l 'app=nginx-deploy' -o jsonpath='{ .items[0].metadata.name }')
#@print "# Found NGINX pod ${NGINX}"
```

Given the pod's name, we can start `tshark` in our second window like so:

```bash
#@print \
kubectl exec -it ${NGINX} -c linkerd-debug -- tshark -i any -d tcp.port==80,ssl
```

This will start `tshark` running watching for traffic on any interface (`-i
any`), interpreting anything on TCP port 80 as SSL (`-d tcp.port=80,ssl`).
Remember that we haven't injected NGINX yet, so it is _not_ participating in
the mesh!

Get that running in a separate window, then come back here.

<!-- @wait_clear -->

### 5. Make a request!

From our `curl` Pod, we can make a request and see what happens!

```bash
CURL=$(kubectl get pods -l 'app=curl' -o jsonpath='{ .items[0].metadata.name }')
#@print "# Found curl pod ${CURL}"

kubectl exec -it ${CURL} -c curl -- curl http://nginx-deploy.default.svc.cluster.local:80
## This should show the output of curl...
```

If we flip back to the `tshark` window, we should be able to see that this
communication happened in plaintext. We'll be able to actually see the HTTP
request being sent.

```bash
##     1 0.000000000 8e:06:33:0a:72:b2 ?              ARP 44 Who has 10.42.0.17? Tell 10.42.0.15
##    2 0.000068083 fe:36:ba:c9:14:18 ?              ARP 44 10.42.0.17 is at fe:36:ba:c9:14:18
##    3 0.000124333   10.42.0.15 ? 10.42.0.17   TCP 76 56384 ? 80 [SYN] Seq=0 Win=64860 Len=0 MSS=1410 SACK_PERM=1 TSval=3602376240 TSecr=0 WS=128
##    4 0.000131458   10.42.0.17 ? 10.42.0.15   TCP 76 80 ? 56384 [SYN, ACK] Seq=0 Ack=1 Win=64308 Len=0 MSS=1410 SACK_PERM=1 TSval=148213048 TSecr=3602376240 WS=128
##    5 0.000142791   10.42.0.15 ? 10.42.0.17   TCP 68 56384 ? 80 [ACK] Seq=1 Ack=1 Win=64896 Len=0 TSval=3602376240 TSecr=148213048
##    6 0.000300208   10.42.0.15 ? 10.42.0.17   HTTP 236 GET / HTTP/1.1
##    7 0.000304625   10.42.0.17 ? 10.42.0.15   TCP 68 80 ? 56384 [ACK] Seq=1 Ack=169 Win=64256 Len=0 TSval=148213048 TSecr=3602376240
##    8 0.001178916   10.42.0.17 ? 10.42.0.15   TCP 306 HTTP/1.1 200 OK  [TCP segment of a reassembled PDU]
##    9 0.001215375   10.42.0.15 ? 10.42.0.17   TCP 68 56384 ? 80 [ACK] Seq=169 Ack=239 Win=64768 Len=0 TSval=3602376241 TSecr=148213049
##   10 0.001227541   10.42.0.17 ? 10.42.0.15   HTTP 683 HTTP/1.1 200 OK  (text/html)
##   11 0.001240666   10.42.0.15 ? 10.42.0.17   TCP 68 56384 ? 80 [ACK] Seq=169 Ack=854 Win=64256 Len=0 TSval=3602376241 TSecr=148213049
##   12 5.002454419   10.42.0.15 ? 10.42.0.17   TCP 68 56384 ? 80 [FIN, ACK] Seq=169 Ack=854 Win=64256 Len=0 TSval=3602381242 TSecr=148213049
##   13 5.002663294   10.42.0.17 ? 10.42.0.15   TCP 68 80 ? 56384 [FIN, ACK] Seq=854 Ack=170 Win=64256 Len=0 TSval=148218050 TSecr=3602381242
##   14 5.002714419   10.42.0.15 ? 10.42.0.17   TCP 68 56384 ? 80 [ACK] Seq=170 Ack=855 Win=64256 Len=0 TSval=3602381242 TSecr=148218050
```

<!-- @wait_clear -->

### 6. Inject NGINX

Next up: let's inject NGINX so that it gets to participate in the mesh.

```bash
kubectl get deploy nginx-deploy -o yaml \
    | linkerd inject - \
    | kubectl apply -f -

kubectl get pods -w
```

Let's also restart our `tshark` session, adding a `grep -v 127.0.0.1` to
filter out packets sent over the loopback interface. (Why? Once injected, the
`linkerd-proxy` will be talking to the NGINX container over this interface,
and that's not what we're trying to see.)

Note that the NGINX Pod's name changed when we injected Linkerd, so we'll need
to look it up again.

```bash
NGINX=$(kubectl get pods -l 'app=nginx-deploy' -o jsonpath='{ .items[0].metadata.name }')
#@print "# Found NGINX pod ${NGINX}"
```

Given that, flip back to your other terminal, kill `tshark`, and restart it as so:

```bash
#@print \
kubectl exec -it ${NGINX} -c linkerd-debug -- tshark -i any -d tcp.port==80,ssl | grep -v 127.0.0.1
```

<!-- @wait -->

### 7. Send another request!

Let's repeat that `curl` request:

```bash
kubectl exec -it ${CURL} -c curl -- curl http://nginx-deploy.default.svc.cluster.local:80
```

and then head back to look at `tshark` again. This time, you won't see
anything that looks like HTTP -- only encrypted randomness.

```bash
##
```

<!-- @wait_clear -->

### 8. `linkerd viz` revisited

Suppose we take another look at `linkerd viz`?

At this point, NGINX _is_ meshed, so we should see that in the `viz`
dashboard. We should also be able to drill into its deployments and see
traffic with `linkerd viz top`.

So. Kill `tshark` in the second window and run `linkerd viz dashboard`
instead. You'll be able to see that NGINX is meshed, and drill down to where
you can see traffic coming through to it.

<!-- @browser_then_terminal -->

Now that you have `linkerd viz` waiting for traffic, let's send another
request from the `curl` Pod.

```bash
kubectl exec -it ${CURL} -c curl -- curl http://nginx-deploy.default.svc.cluster.local:80
```

<!-- @browser_then_terminal -->

You'll see the request appear, but we need to switch to the `tap` view to drill into the individual requests.

<!-- @browser_then_terminal -->
<!-- @clear -->

Now that you have the `tap` view set up, let's send yet another request from
the `curl` Pod.

```bash
CURL=$(kubectl get pods -l 'app=curl' -o jsonpath='{ .items[0].metadata.name }')
#@print "# Found curl pod ${CURL}"

kubectl exec -it ${CURL} -c curl -- curl http://nginx-deploy.default.svc.cluster.local:80
```

<!-- @browser_then_terminal -->

So after all that, we still don't get to actually see that this is TLS'd!
although the presence of `l5d-dst-canonical` is a good proxy. However, it's
still annoying that we don't see a direct "yes, TLS is happening in this
view."

As it happens, we _can_ see that with `linkerd viz tap` if we select JSON
output. So flip back to your second terminal, kill `linkerd viz dashboard`,
and instead run

```bash
#@print \
linkerd viz tap deployment/curl --to deployment/nginx-deploy -o json
```

Then come back here.

<!-- @wait -->

OK, let's send yet another `curl` request.

```bash
kubectl exec -it ${CURL} -c curl -- curl http://nginx-deploy.default.svc.cluster.local:80
```

If you flip to your second terminal, you should see that the `tap` has
captured a very expanded view of the request and the response -- and, in the
request, you should see `tls: true`.

```bash
## {
##   "source": {
##     ...
##   },
##   "destination": {
##     "ip": "10.42.0.25",
##     "port": 80,
##     "metadata": {
##       "control_plane_ns": "linkerd",
##       "deployment": "nginx-deploy",
##       "namespace": "default",
##       ...
##       "tls": "true"
##     }
##   },
##   "routeMeta": null,
##   "proxyDirection": "OUTBOUND",
##   "requestInitEvent": {
##     ...
##   }
## }
```

<!-- @wait_clear -->

## One More Thing

If we take a quick look back over the whole problem... we find that this was
pretty messy all around, really.

<!-- @wait -->

### Verifying uninjected traffic

We started by verifying traffic from an _un_injected workload. Your options
here are honestly rather limited.

- You can use tools such as ksniff (https://github.com/eldadru/ksniff). This
  adds the overhead of learning and running more tools, and it usually
  requires an account with elevated privileges in your cluster.

<!-- @wait -->

- You can use Kubernetes primitives such as ephemeral containers... but this
  requires these primitives to be enabled and accessible, which may require
  work on the part of the cluster provider _before_ the cluster is
  provisioned.

  (See https://kubernetes.io/docs/concepts/workloads/pods/ephemeral-containers/
  for more on ephemeral containers.)

<!-- @wait -->

- You can inject a debug/network tool sidecar, which we did in this workshop.
  Again, there's a potential privilege issue here.

<!-- @wait_clear -->

### Verifying injected traffic

We then moved on to injected workloads, starting with the debug sidecar. The
debug sidecar is effective at a low level, but it's clumsy, especially because
adding and removing the debug sidecar when your workload is already running
requires restarts.

We showed `linkerd viz top`, too, which can be simpler to deal with, except
for the headaches of its voluminuous JSON output.

<!-- @wait_clear -->

### A simpler way.

Just use Buoyant Cloud (https://buoyant.cloud/). It can show you directly with a few clicks.

<!-- @browser_then_terminal -->
<!-- @clear -->
<!-- @show_slides -->

## Summary

And that's the mTLS workshop! If you have questions, the `#workshops` channel
on the Linkerd Slack (https://slack.linkerd.io/) is the easiest way to reach
us, or opening issues against
https://github.com/BuoyantIO/service-mesh-academy will work too. Thanks!

