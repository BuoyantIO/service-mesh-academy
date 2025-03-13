<!--
SPDX-FileCopyrightText: 2022-2024 Buoyant Inc.
SPDX-License-Identifier: Apache-2.0
-->

# Gateway API 101: Ana's stuff

This file has the documentation - and executable code! - for Ana's role in
the Gateway API 101 Service Mesh Academy. The easiest way to use this file is
to execute it with [demosh].

Things in Markdown comments are safe to ignore when reading this later. When
executing this with [demosh], things after the horizontal rule below (which
is just before a commented `@SHOW` directive) will get displayed.

[demosh]: https://github.com/BuoyantIO/demosh

---
<!-- @clear -->
<!-- @show_terminal -->
<!-- @SHOW -->

# Gateway API 101: Ana's stuff

```bash
#@immed
GATEWAYADDR=$1
```

So Chihiro says we have a Gateway at ${GATEWAYADDR}! That means we can
install Faces.

```bash
kubectl create ns faces
kubectl annotate ns faces \
    linkerd.io/inject=ingress \
    config.alpha.linkerd.io/proxy-enable-native-sidecar=true

helm install faces -n faces \
    oci://ghcr.io/buoyantio/faces-chart --version 2.0.0-rc.3 \
     --set face.errorFraction=0 \
     --set backend.errorFraction=0 \
     --set smiley2.enabled=true \
     --set smiley3.enabled=true \
     --set color2.enabled=true \
     --set color3.enabled=true

kubectl rollout status -n faces deploy
```

And NOW we can see Faces at ${GATEWAYADDR}!

<!-- @browser_then_terminal -->

Well that didn't work. Uhoh.

<!-- @wait_clear -->

Ah yes. It's because we haven't actually installed any HTTP routes for
Faces! There are two that we need.

```bash
bat ana/gui-route.yaml
bat ana/face-route.yaml
```

Let's apply those one at a time.

```bash
kubectl apply -f ana/gui-route.yaml
kubectl get -n faces httproute faces-gui-route
```

Unfortunately, we can't see if our HTTPRoute was actually accepted! So
we'll define a shell function to help.

```bash
function route_status () {
    kubectl get -n "$2" httproute "$1" -o json \
        | jq -r '.status.parents[0].conditions[] | "\(.type): \(.status)"'
}
```

Now we can check the status of our HTTPRoute.

```bash
route_status faces-gui-route faces
```

So that looks much better. `Accepted: True` means that the HTTPRoute was
matched with a Gateway, and `ResolvedRefs: True` means that all the
`backendRefs` were matched with real resources. Let's do the same for the
other route.

```bash
kubectl apply -f ana/face-route.yaml
route_status face-route faces
```

And now we can see Faces at `http://${GATEWAYADDR}/gui/`!

<!-- @wait -->
