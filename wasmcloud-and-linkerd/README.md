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
using them both together: we'll install the world-famous Faces demo from
https://github.com/BuoyantIO/faces-demo, and then we'll replace one of its
workloads with a Wasm version!

## Installing Linkerd

We'll start our journey with wasmCloud and Linkerd by installing Linkerd
(shocking, I know). First, as usual, we need to install the Gateway API CRDs,
then the Linkerd CRDs:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/standard-install.yaml
linkerd install --crds | kubectl apply -f -
```

<!-- @wait_clear -->

Next up, we install the Linkerd control plane -- but there's one critical
difference here! wasmCloud currently leans heavily on the NATS messaging bus,
and NATS uses a server-speaks-first protocol which needs to be marked as
`opaque` for Linkerd. We could do this by judiciously marking certain ports in
Deployments and such, but for NATS-heavy applications like wasmCloud, it's
easier just to set `proxy.opaquePorts` when installing Linkerd, so _any_ use
of the NATS ports (4222, 6222, 8222, and 7422) will be treated as opaque.

**Note:** Setting `proxy.opaquePorts` _replaces_ Linkerd's defaults rather
than appending to them, so what you see here is Linkerd's normal list plus the
NATS ports.

```bash
linkerd install \
        --set proxy.opaquePorts="25\,587\,3306\,4444\,5432\,6379\,9300\,11211\,4222\,6222\,8222\,7422" \
    | kubectl apply -f -
```

<!-- @wait_clear -->

Once that's done, we can install Linkerd's Viz extension. This is the easy way
to make sure that we really have our Wasm workload meshed.

```bash
linkerd viz install | kubectl apply -f -
```

Finally, we'll check that everything is working:

```bash
linkerd check
```

<!-- @wait_clear -->

## Installing Faces

Now that we have Linkerd installed, let's install the Faces demo. This is a
normal, standard installation of Faces with Linkerd, using Faces' built-in
"ingress controller" for a quick deployment: first, make sure we have a
`faces` namespace set up for Linkerd auto-injection:

```bash
kubectl create ns faces
kubectl annotate ns/faces linkerd.io/inject=enabled
```

...then install Faces into that namespace:

```bash
helm install \
     faces -n faces \
     oci://ghcr.io/buoyantio/faces-chart --version 2.0.0 \
     --set gui.serviceType=LoadBalancer \
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

## Installing wasmCloud

At this point, Faces is running, but there's no Wasm involved -- it's just the
normal Faces demo. So let's get wasmCloud installed, so that we can use it to
get our Wasm "rusty" workload running.

First we get wasmCloud's CRDs and base controllers running:

```bash
helm upgrade --install \
    wasmcloud-platform \
    --values ./wasmcloud-platform/values.yaml \
    oci://ghcr.io/wasmcloud/charts/wasmcloud-platform \
    --dependency-update \
```

Wait for all components to install and wadm-nats communications to establish:

```bash
kubectl rollout status deploy,sts -l app.kubernetes.io/name=nats
kubectl wait --for=condition=available --timeout=600s deploy -l app.kubernetes.io/name=wadm
kubectl wait --for=condition=available --timeout=600s deploy -l app.kubernetes.io/name=wasmcloud-operator
```

Next we create a wasmCloud host. This is a Kubernetes pod that will run our
wasmCloud workloads:

Used to be:
    --values https://raw.githubusercontent.com/wasmCloud/wasmcloud/main/charts/wasmcloud-platform/values.yaml \


```bash
helm upgrade --install \
    wasmcloud-platform \
    --values ./values.yaml \
    oci://ghcr.io/wasmcloud/charts/wasmcloud-platform \
    --dependency-update \
    --set "hostConfig.enabled=true"

kubectl rollout status deploy,sts
```

## Exposing the wasmCloud host ports

For access to workloads that wasmCloud is running, we need access to port 8000
on the `wasmcloud-host` Service and Deployment. Unfortunately, at the moment that's not there by default! So we'll patch it in.

```bash
bat wasmcloud-host-deployment-patch.json
kubectl patch deployment wasmcloud-host -n default \
    --type='json' \
    --patch-file=wasmcloud-host-deployment-patch.json

bat wasmcloud-host-service-patch.json
kubectl patch service wasmcloud-host -n default \
    --type='json' \
    --patch-file=wasmcloud-host-service-patch.json

kubectl rollout status deploy,sts
```

Finally, we can deploy the `rusty` workload!

```bash
kubectl apply -f rusty.yaml
kubectl get application
```

## Switching Faces to use the Rusty workload

Now that `rusty` is running, let's Faces to use it instead of the `smiley` workload (this is OK because `rusty` implements the same interface as `smiley`).

```bash
kubectl set env -n faces deploy/face \
        SMILEY_SERVICE="wasmcloud-host.default:8000"

kubectl rollout status -n faces deploy
```

Let that run and then check `linkerd viz stat-outbound`. You'll see that Faces
is, indeed, now talking the wasmCloud host for the smiley workload.

```bash
linkerd viz stat-outbound -n faces deploy/face
```

<!-- @wait_clear -->

## Meshing wasmCloud with Linkerd

At this point, we have a wasmCloud host running, and Faces is using it to
display smileys. But we don't have Linkerd meshing the wasmCloud host, as we
can show with `linkerd viz dashboard`:

```bash
linkerd viz dashboard
```

Fixing this is easy at this point: we just need to annotate the `default`
namespace for Linkerd auto-injection, and then restart the workloads in that
namespace so that they get meshed.

```bash
kubectl annotate ns default linkerd.io/inject=enabled
kubectl rollout restart deploy,sts -n default
kubectl rollout status deploy,sts -n default
```

NOW we'll see everything meshed in the Viz dashboard:

```bash
linkerd viz dashboard
```
