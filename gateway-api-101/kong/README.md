# Configuring your service mesh with Gateway API

This file installs Linkerd and Linkerd Viz for the Gateway API service mesh
workshop at KubeCon NA 2024 in Salt Lake City, Utah, USA.

<!--
SPDX-FileCopyrightText: 2022-2024 Buoyant Inc.
SPDX-License-Identifier: Apache-2.0

Things in Markdown comments are safe to ignore when reading this later. When
executing this with [demosh], things after the horizontal rule below (which
is just before a commented `@SHOW` directive) will get displayed.
-->

<!-- @SHOW -->

Start by installing the Gateway API CRDs (v1.1.1 experimental).

```bash
kubectl apply -f experimental-install.yaml
```

Next, install Linkerd and Linkerd Viz. We'll use the latest edge release for
this, and we'll explicitly tell Linkerd _not_ to install Gateway API CRDs
(that's those "--set ...=false" flags).

```bash
linkerd check --pre

linkerd install --crds \
    --set enableHttpRoutes=false \
    --set enableTcpRoutes=false \
    --set enableTlsRoutes=false \
  | kubectl apply -f -

linkerd install \
    --set enableHttpRoutes=false \
    --set enableTcpRoutes=false \
    --set enableTlsRoutes=false \
  | kubectl apply -f -

linkerd viz install | kubectl apply -f -

linkerd check
```

Next, install the Kong Gateway Operator.

```bash
kubectl create ns kong-system

kubectl annotate ns kong-system \
    linkerd.io/inject=ingress \
    config.alpha.linkerd.io/proxy-enable-native-sidecar=true

helm upgrade --install kgo kong/gateway-operator -n kong-system  \
    --set image.tag=1.4

kubectl -n kong-system wait \
    --for=condition=Available=true --timeout=120s \
    deployment/kgo-gateway-operator-controller-manager
```

Then it's time to install Faces.

```bash
k3d image load --cluster ffs \
    ghcr.io/buoyantio/faces-color:latest-arm64 \
    ghcr.io/buoyantio/faces-gui:latest-arm64 \
    ghcr.io/buoyantio/faces-face:latest-arm64 \
    ghcr.io/buoyantio/faces-smiley:latest-arm64

kubectl create ns faces
kubectl annotate ns faces \
    linkerd.io/inject=ingress \
    config.alpha.linkerd.io/proxy-enable-native-sidecar=true

#     --set gui.serviceType=LoadBalancer \

helm install faces -n faces \
     $HOME/buoyant/faces-demo/faces-chart-2.0.0-rc.3.tgz \
     --set defaultImageTag=latest-arm64 \
     --set face.errorFraction=0 \
     --set backend.errorFraction=0 \
     --set smiley2.enabled=true \
     --set smiley3.enabled=true \
     --set color2.enabled=true \
     --set color3.enabled=true

kubectl rollout status -n faces deploy
```

