<!--
SPDX-FileCopyrightText: 2022-2024 Buoyant Inc.
SPDX-License-Identifier: Apache-2.0
-->

# Gateway API 101: Ian's stuff

This file has the documentation - and executable code! - for Ian's role in the
Gateway API 101 Service Mesh Academy. The easiest way to use this file is to
execute it with [demosh].

Things in Markdown comments are safe to ignore when reading this later. When
executing this with [demosh], things after the horizontal rule below (which
is just before a commented `@SHOW` directive) will get displayed.

[demosh]: https://github.com/BuoyantIO/demosh

---
<!-- @clear -->
<!-- @show_terminal -->
<!-- @SHOW -->

# Gateway API 101: Ian's stuff

Ian is our _infrastructure provider_: it's his job to deliver a cluster with
the basics set up for Chihiro and Ana to use. In our case, we're going to show
how Ian might do things for a fully-managed cluster: he's going to set up
Linkerd and a Gateway controller before handing off to Chihiro.

(For demo purposes, we assume that you've already set up an empty cluster
here. In the real world, that would be part of Ian's job too.)

Start by installing the Gateway API CRDs (v1.1.1 experimental).

```bash
kubectl apply -f ian/experimental-install.yaml
```

Next, install Linkerd and Linkerd Viz. We'll use the latest edge release for
this, and we'll explicitly tell Linkerd _not_ to install Gateway API CRDs
(that's the "--set installGatewayAPI=false" flag).

```bash
linkerd check --pre

linkerd install --crds --set installGatewayAPI=false \
  | kubectl apply -f -

linkerd install | kubectl apply -f -
linkerd viz install | kubectl apply -f -

linkerd check
```

Next up! Let's get a Gateway controller going. Set up the namespace...

```bash
kubectl create ns envoy-gateway-system
kubectl annotate ns envoy-gateway-system \
    linkerd.io/inject=enabled \
    config.alpha.linkerd.io/proxy-enable-native-sidecar=true
```

...then install Envoy Gateway using Helm!

```bash
helm install envoy-gateway \
     -n envoy-gateway-system \
     oci://docker.io/envoyproxy/gateway-helm \
     --version v1.1.2
```

After that, we'll wait for Envoy Gateway to be ready.

```bash
kubectl rollout status -n envoy-gateway-system deploy
```

Then, finally, let's get the GatewayClass set up.

```bash
bat ian/gatewayclass.yaml
kubectl apply -f ian/gatewayclass.yaml
```

...and we're done! We have a working cluster with Gateway API and Linkerd.
Over to Chihiro!

<!-- @wait -->
