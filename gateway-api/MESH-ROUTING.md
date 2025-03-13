<!--
SPDX-FileCopyrightText: 2022-2024 Buoyant Inc.
SPDX-License-Identifier: Apache-2.0
-->

# Gateway API 101: Mesh routing

This file has the documentation - and executable code! - for a mesh routing
demo in the Gateway API 101 Service Mesh Academy. The easiest way to use this
file is to execute it with [demosh].

Things in Markdown comments are safe to ignore when reading this later. When
executing this with [demosh], things after the horizontal rule below (which
is just before a commented `@SHOW` directive) will get displayed.

[demosh]: https://github.com/BuoyantIO/demosh

```bash
function route_status () {
    kubectl get -n "$2" httproute "$1" -o json \
        | jq -r '.status.parents[0].conditions[] | "\(.type): \(.status)"'
}
```

---
<!-- @clear -->
<!-- @show_terminal -->
<!-- @SHOW -->

# Gateway API 101: Mesh routing

So we have a running application with a Gateway controller routing to it! To
prove that we really have a working mesh with Gateway API, let's route the
`smiley` calls somewhere else. We'll start by routing everything to the
`smiley2` Service, which returns a heart-eyed smiley.

```bash
bat mesh/smiley-route.yaml
kubectl apply -f mesh/smiley-route.yaml
```

We can immediately see the effect in the browser.

<!-- @show_5 -->
<!-- @wait_clear -->

Of course, we can use `route_status` to verify that all is well.

```bash
route_status smiley-route faces
```

What's interesting about this kind of thing is that it can
help Ana in developing -- but it can also help, say, Chihiro
down in the NOC. Suppose that it's 10PM on Friday night and
suddenly the `smiley2` service starts returning 500s...

```bash
kubectl set env -n faces deploy/smiley2 ERROR_FRACTION=75
```

This is hardly ideal... but Chihiro can quickly route all
traffic back to `smiley`, which is still working fine.

```bash
kubectl edit -n faces httproute smiley-route
```

<!-- @wait_clear -->

## Canary routing

Let's now do a canary with the `color` workload, starting
with 10% of the traffic going to `color2`. We use a GRPCRoute
for this, but it's the same idea as we've seen with our
HTTPRoutes above.

```bash
bat mesh/color-canary-10.yaml
kubectl apply -f mesh/color-canary-10.yaml
```

<!-- @wait -->

We can edit the weights live, too.

```bash
kubectl edit -n faces grpcroute color-canary
kubectl edit -n faces grpcroute color-canary
kubectl edit -n faces grpcroute color-canary
```

<!-- @wait_clear -->
<!-- @show_terminal -->

Finally, we can do an A/B test. If we switch back to the full browser, we can
see a username, and we can switch the smiley depending on that username.

<!-- @browser_then_terminal -->

```bash
bat mesh/smiley-ab.yaml
kubectl apply -f mesh/smiley-ab.yaml
```

If we switch back to the terminal, nothing will happen immediately -- but if
we log in as "flynn", we'll see an immediate difference.

<!-- @browser_then_terminal -->

## Dynamic request routing

Finally, we can also route a request based on the nature of the request -- for
example, the `PATH` of an HTTP route or the `method` of a GRPC route. In this
demo, the edge cells and the center cells use different requests to `smiley`
and `color`, so we can route them differently.

We'll start by using the `PATH` of the `smiley` requests to route just the
edge requests to `smiley3` (the rolling-eyes smiley).

```bash
bat mesh/smiley-path.yaml
kubectl apply -f mesh/smiley-path.yaml
```

<!-- @show_5 -->

We'll see an immediate effect in the browser.

<!-- @wait_clear -->

## Dynamic request routing

We can do exactly the same thing using the `method` of the gRPC
requests to `color` to route only the center requests to `color3`
(which returns dark blue) and route the edges back to `color`
(which returns light blue).

```bash
bat mesh/color-method.yaml
kubectl apply -f mesh/color-method.yaml
```

<!-- @wait -->

So wait, that didn't work. Why not?

<!-- @wait -->

It's because we forgot to delete the old canary route. Both routes
have the `color` Service as a parent, so Gateway API conflict
resolution comes into play. The `method` match for the central cells
is the most specific route, so it wins over everything -- but for
the edge cells, the _oldest_ route wins because both routes are
equally specific.

(The reason the oldest route wins is to avoid nasty surprises if
you mistakenly create a conflicting route!)

So if we delete the older `color-canary` GRPCRoute, we'll get light
blue edge cells like we want.

```bash
kubectl delete -n faces grpcroute color-canary
```

<!-- @wait_clear -->
<!-- @show_terminal -->

## Wrapping up

There's obviously a _lot_ more we can do, this is just the whirlwind tour. In
particular, remember that we can use Gateway API to control both the ingress
and the mesh, which gives us enormous flexibility and control.

<!-- @wait -->
