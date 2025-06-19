<!--
SPDX-FileCopyrightText: 2024 Buoyant Inc.
SPDX-License-Identifier: Apache-2.0

SMA-Description: wasmCloud and Linkerd
-->

# wasmCloud and Linkerd

This is the documentation - and executable code! - for the wasmCloud and
Linkerd Service Mesh Academy workshop. The easiest way to use this file is to
execute it with [demosh].

Things in Markdown comments are safe to ignore when reading this later. When
executing this with [demosh], things after the horizontal rule below (which
is just before a commented `@SHOW` directive) will get displayed.

[demosh]: https://github.com/BuoyantIO/demosh

Before running this workshop, you'll need to run `setup-base.sh` to get things
set up. That requires kind, and will not work with Docker Desktop for Mac: if
you're on a Mac, check out Orbstack instead.

<!-- @import demosh/check-requirements.sh -->
<!-- @start_livecast -->
---
<!-- @SHOW -->

# wasmCloud and Linkerd

wasmCloud is a platform - and a hosted service - for running WebAssembly
workloads in Kubernetes. Linkerd is a service mesh. We're going to explore
using them both together.

1. We'll install wasmCloud on-prem on our very own Kubernetes cluster and get
   a Wasm workload - `rusty` - running with wasmCloud.

2. We'll install the world-famous Faces demo from
   https://github.com/BuoyantIO/faces-demo and switch it to use `rusty`
   instead of its native `smiley` workload.

3. We'll install Linkerd and mesh the whole thing!

4. Finally, we'll show dynamic routing between the `smiley` and `rusty`
   workloads, using Linkerd's HTTPRoute resources.

<!-- @wait_clear -->

## Installing wasmCloud

We'll start by installing wasmCloud. This isn't terribly difficult, it's just
a matter of some Helm work. First we get wasmCloud's CRDs and base controllers
running:

```bash
helm upgrade --install \
    wasmcloud-platform \
    oci://ghcr.io/wasmcloud/charts/wasmcloud-platform \
    --values https://raw.githubusercontent.com/wasmCloud/wasmcloud/main/charts/wasmcloud-platform/values.yaml \
    --dependency-update
```

We'll be polite and wait for everything to be ready before proceeding:

```bash
kubectl rollout status deploy,sts -l app.kubernetes.io/name=nats
kubectl wait --for=condition=available --timeout=600s deploy -l app.kubernetes.io/name=wadm
kubectl wait --for=condition=available --timeout=600s deploy -l app.kubernetes.io/name=wasmcloud-operator
```

<!-- @wait_clear -->

## Installing the wasmCloud host

Next, we need to create a wasmCloud host. This is a Kubernetes pod that will
run our wasmCloud workloads. We do this with the same Helm chart, but we add
`--set hostConfig.enabled=true` to the command line to tell it that we've set
up the base controllers and we now want a wasmCloud host.

```bash
helm upgrade --install \
    wasmcloud-platform \
    oci://ghcr.io/wasmcloud/charts/wasmcloud-platform \
    --values https://raw.githubusercontent.com/wasmCloud/wasmcloud/main/charts/wasmcloud-platform/values.yaml \
    --dependency-update \
    --set "hostConfig.enabled=true"

kubectl rollout status deploy,sts
```

<!-- @wait_clear -->

## Exposing the wasmCloud host ports

For access to workloads that wasmCloud is running, we need access to port 8000
on the `wasmcloud-host` Service and Deployment. Unfortunately, at the moment
that port isn't exposed by default! So we'll patch it in.

```bash
bat wasmcloud-host-deployment-patch.json
kubectl patch deployment wasmcloud-host -n default \
    --type='json' \
    --patch-file=wasmcloud-host-deployment-patch.json

bat wasmcloud-host-service-patch.json
kubectl patch service wasmcloud-host -n default \
    --type='json' \
    --patch-file=wasmcloud-host-service-patch.json
```

Since we just patched the Deployment, we'll wait for it to roll out:

```bash
kubectl rollout status deploy,sts
```

And, finally, we can now check to make sure that the `wasmcloud-host` Service
shows us port 8000:

```bash
kubectl get svc
```

<!-- @wait_clear -->

## Deploying the `rusty` workload

Finally, we can deploy the `rusty` workload! Now that wasmCloud is running,
this just involves applying a single YAML file.

```bash
bat rusty.yaml
kubectl apply -f rusty.yaml
```

This will create an Application resource letting us know how our workload is
doing, so let's read it back and make sure that it's been successfully
deployed:

```bash
kubectl get application
```

We'll make sure `rusty` is working using a simple `curl` Deployment:

```bash
bat curl.yaml
kubectl apply -f curl.yaml
kubectl rollout status deploy/curl
kubectl exec -it deploy/curl -- curl -s http://wasmcloud-host.default:8000/
```

So far, so good!

<!-- @wait_clear -->

## Installing Faces

Now that we have wasmCloud and `rusty` installed, let's install the Faces
demo. This is a normal, standard installation of Faces with Linkerd, using
Faces' built-in "ingress controller" for a quick deployment, and with Faces'
usual errors turned off (we're showing Wasm here, not resilience features!)

```bash
helm install \
     faces -n faces --create-namespace \
     oci://ghcr.io/buoyantio/faces-chart --version 2.0.0 \
     --set gui.serviceType=LoadBalancer \
     --set backend.errorFraction=0 --set backend.delayBuckets=0 \
     --set face.errorFraction=0 --set face.delayBuckets=0 \
     --wait

kubectl rollout status -n faces deploy
```

At this point, we should be able to open the Faces GUI in our browser. To find the external IP address, run:

```bash
GUI_SVC=$(kubectl get svc -n faces faces-gui -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
#@immed
echo "# Faces GUI is available at http://${GUI_SVC}"
```

If we go there in a browser, we should see the Faces GUI!

<!-- @browser_then_terminal -->
<!-- @show_5 -->

## Switching Faces to use the Rusty workload

So far so... well, normal. This is just the normal, standard Faces deployment,
with no Wasm goodness whatsoever. So let's switch Faces to use `rusty` instead
of the `smiley` workload! (This is OK because `rusty` implements the same
interface as `smiley`).

Again, we use the `wasmcloud-host` Service to connect to the `rusty`
workload... but the important bit is that as we do this, we should see
a rather visible change in our browser!

```bash
kubectl set env -n faces deploy/face \
        SMILEY_SERVICE="wasmcloud-host.default:8000"

kubectl rollout status -n faces deploy
```

<!-- @wait -->

Next up: Linkerd!

<!-- @slides_then_terminal -->

## Installing Linkerd

We'll start our journey with wasmCloud and Linkerd by installing Linkerd
(shocking, I know). First, as usual, we need to install the Gateway API CRDs,
then the Linkerd CRDs:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/standard-install.yaml
linkerd install --crds | kubectl apply -f -
```

OK, now we can install the Linkerd control plane itself.

<!-- @wait_clear -->

## Installing the Linkerd control plane

There's one critical thing that we need to pay attention to when installing
the Linkerd control plane. wasmCloud currently leans heavily on the NATS
messaging bus, and NATS uses a server-speaks-first protocol which needs to be
marked as `opaque` for Linkerd. We could do this by judiciously marking
certain ports in Deployments and such, but for NATS-heavy applications like
wasmCloud, it's easier just to set `proxy.opaquePorts` when installing
Linkerd, so _any_ use of the NATS ports (4222, 6222, 8222, and 7422) will be
treated as opaque.

**Note:** Setting `proxy.opaquePorts` _replaces_ Linkerd's defaults rather
than appending to them, so what you see here is Linkerd's normal list plus the
NATS ports.

```bash
linkerd install \
        --set proxy.opaquePorts="25\,587\,3306\,4444\,5432\,6379\,9300\,11211\,4222\,6222\,8222\,7422" \
    | kubectl apply -f -
```

Once that's done, we can install Linkerd's Viz extension. This is the easy way
to make sure that we really have our Wasm workload meshed.

```bash
linkerd viz install | kubectl apply -f -
```

Finally, we'll check that everything is working:

```bash
linkerd check
```

So far, so good!

<!-- @wait_clear -->

## What's meshed?

Now that we have Linkerd installed, we can check to see what workloads are
meshed. We can do this with the `linkerd viz dashboard` command, which will
open a browser window showing us the Linkerd Viz dashboard... and it will show
us that neither wasmCloud (in the `default` namespace) nor Faces (in the
`faces` namespace) is meshed yet. This is expected.

```bash
linkerd viz dashboard --show url
```

<!-- @clear -->
<!-- @show_terminal -->

## Meshing Faces

Let's start by meshing Faces! This is simple: we just annotate the `faces`
namespace with `linkerd.io/inject=enabled`...

```bash
kubectl annotate ns faces linkerd.io/inject=enabled
```

<!-- @show_5 -->

...and then restart the workloads in that namespace so that they get meshed.
(In theory, we won't see anything dramatic in the Faces GUI while this happens
-- in practice, since we're only running one replica of everything in Faces,
we might see some hiccups.)

```bash
kubectl rollout restart -n faces deploy
kubectl rollout status -n faces deploy
```

<!-- @wait -->
<!-- @show_terminal -->

If we now look at the Linkerd Viz dashboard, we'll see that Faces is meshed.

```bash
linkerd viz dashboard --show url
```

<!-- @clear -->
<!-- @show_terminal -->

Another fun check we can do is to try the shiny new `linkerd viz
stat-outbound` command to see what Linkerd Viz knows about the outbound
traffic from the `face` Deployment -- that's the one that should be talking to
`wasmcloud-host` to reach the `rusty` workload.

```bash
linkerd viz stat-outbound -n faces deploy/face
```

We can see that it is indeed talking to `wasmcloud-host` on port 8000, so
that's good... but let's go back to the Viz dashboard and doublecheck whether
or not that's actually meshed. We can do this by clicking through to the
`face` Deployment and scrolling down to look at its edges.

```bash
linkerd viz dashboard --show url
```

<!-- @clear -->
<!-- @show_terminal -->

Nope. Not meshed. So let's fix that!

<!-- @wait_clear -->

## Meshing wasmCloud with Linkerd

Meshing wasmCloud is easy: we do it exactly the same way we did for Faces,
annotating namespace for Linkerd auto-injection and then restarting its
workloads. We do have to remember to restart both Deployments and
StatefulSets, though, since wasmCloud uses a StatefulSet for its host -- and
as it happens, we _will_ see significant downtime while we do this, because
(again) we're only running one replica of the wasmCloud host.

<!-- @show_5 -->

```bash
kubectl annotate ns default linkerd.io/inject=enabled
kubectl rollout restart deploy,sts -n default
kubectl rollout status deploy,sts -n default
```

Now we'll see that everything is meshed in the Viz dashboard, and of course
that Faces is still happily running.

<!-- @show_terminal -->

```bash
linkerd viz dashboard --show url
```

<!-- @clear -->
<!-- @show_terminal -->

## Dynamic Routing

Now that we have both Faces and wasmCloud meshed, we can do something fun: we
can dynamically route traffic between the `smiley` and `rusty` workloads using
Linkerd's HTTPRoute support. Specifically, let's use an HTTPRoute to route
traffic to the center four cells of the GUI to the `smiley` workload, and the
rest of the GUI to the `rusty` workload.

We can use HTTPRoute path matching to do this, since the `face` workload uses
an HTTP path of `/center` on its requests for information to display in the
center four cells, and a path of `/edge` for the edge cells.

One minor complication, though, is that the `face` workload is in the `faces`
namespace, and the `wasmcloud-host` Service is in the `default` namespace. The
way Gateway API works, to do this kind of routing you'll need your Route
resource in the same namespace as the workload that _makes the request_ -- so
in our case, we'll use the `default` namespace for our HTTPRoute resource.

Here's our HTTPRoute resource:

```bash
bat rusty-route.yaml
```

<!-- @show_5 -->

and we'll see it take effect immediately when we apply it!

```bash
kubectl apply -f rusty-route.yaml
```

<!-- @wait_clear -->
<!-- @show_terminal -->

## Summary

So there you have it!  We have a wasmCloud host running the `rusty` workload,
and we have the Faces demo running in the `faces` namespace, and we have both
of them meshed with Linkerd. We can dynamically route traffic between the
`smiley` and `rusty` workloads using an HTTPRoute resource, and we can
visualize everything in the Linkerd Viz dashboard. Obviously this is just
scratching the surface, but hopefully it gives a good idea of how to get
started.

<!-- @wait -->

As always, feedback is welcome! You can reach me at flynn@buoyant.io or as
@flynn on the Linkerd Slack (https://slack.linkerd.io).

<!-- @wait -->
<!-- @show_slides -->
