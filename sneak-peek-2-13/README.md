<!--
SPDX-FileCopyrightText: 2024 Buoyant Inc.
SPDX-License-Identifier: Apache-2.0

SMA-Description: New features coming in Linkerd 2.13
-->

# Sneak Peek: Linkerd 2.13

This is the documentation - and executable code! - for the Service Mesh
Academy workshop about what's coming in Linkerd 2.13. The easiest way to use
this file is to execute it with [demosh].

Things in Markdown comments are safe to ignore when reading this later. When
executing this with [demosh], things after the horizontal rule below (which
is just before a commented `@SHOW` directive) will get displayed.

[demosh]: https://github.com/BuoyantIO/demosh

For this workshop, you'll need a running, empty, Kubernetes cluster that can
support `LoadBalancer` services. You can use `create-cluster.sh` to create an
appropriate `k3d` cluster.

<!-- set -e >
<!-- @import demosh/demo-tools.sh -->
<!-- @import demosh/check-requirements.sh -->

<!-- @start_livecast -->

```bash
BAT_STYLE="grid,numbers"
```

---
<!-- @SHOW -->

# Sneak Peek: Linkerd 2.13

Welcome to the Service Mesh Academy Sneak Peek for Linkerd 2.13!

We're going to start by installing the most recent edge release of Linkerd,
since stable-2.13.0 isn't out yet:

```bash
curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install-edge | sh
```

Once that's done, we can proceed to install Linkerd into our cluster.

```bash
linkerd check --pre
linkerd install --crds | kubectl apply -f -
linkerd install | kubectl apply -f -
linkerd check
```

<!-- @wait_clear -->

We're already running the Faces demo (https://github.com/BuoyantIO/faces-demo)
with Emissary-ingress for an ingress controller. Let's get them into the mesh.
In both cases, we'll annotate the namespace for autoinjection:

```bash
kubectl annotate ns emissary linkerd.io/inject=enabled
kubectl annotate ns faces linkerd.io/inject=enabled
```

Then we'll do a rollout restart so that Linkerd can inject its proxy sidecar
into all the Pods.

```bash
kubectl rollout restart -n emissary deployment
kubectl rollout restart -n faces deployment
```

Finally, we'll wait for the new Pods to all be ready:

```bash
kubectl rollout status -n emissary deployment
kubectl rollout status -n faces deployment
```

<!-- @wait_clear -->

OK! At this point, everything should be happily meshed, so let's point a
couple of web browsers to `http://localhost/faces/`, to make sure that the
Faces demo is running.

One browser should be completely normal; the other should use an extension
like `ModHeader` to add the header `X-Faces-User: testuser` to its requests.
Both should show the same thing right now: a bunch of smiley faces on green
backgrounds. The one using `ModHeader` should also say "User: testuser" at the
top.

<!-- @wait -->
<!-- @show_3 -->
<!-- @wait -->
<!-- @show_4 -->
<!-- @wait -->
<!-- @clear -->
<!-- @show_composite -->

## Canary routing

The simplest sort of dynamic request routing we can do is the _canary_:
route a small fraction of traffic destined for a workload to a new
version of the workload, so you can make sure the new version works
without destroying the user experience if it doesn't. Here's a simple
way to do that using an HTTPRoute:

```bash
bat k8s/02-canary/color-canary.yaml
```

<!-- @wait_clear -->

If we apply this, we'll see 10% of the `color` traffic go to `color2`,
which will return blue, instead of green.

```bash
kubectl apply -f k8s/02-canary/color-canary.yaml
```

<!-- @wait -->
<!-- @show_slides -->
<!-- @wait -->
<!-- @clear -->
<!-- @show_composite -->

We can edit the weights to change the distribution of traffic: for
example, if we edit the weights so that both are `weight: 50`, we'll
get an even split between green and blue.

```bash
kubectl edit -n faces httproute/color-canary
```

<!-- @wait_clear -->

If we edit one of the backends to have `weight: 0`, that backend will
get no traffic. (We could also delete the `backendRef` entry entirely.)
So it's easy for us to make all the backgrounds blue with another
`kubectl edit`.

```bash
kubectl edit -n faces httproute/color-canary
```

<!-- @wait_clear -->

## A/B Tests

Another straightforward type of dynamic request routing we can do is
A/B testing. Here, rather than the random distribution of requests we
saw with the canary, we instead use some characteristic of the request
to choose where to route the request.

We'll do an A/B test with the `X-Faces-User` header and the `smiley`
service: any request with `X-Faces-User: testuser` will see the
heart-eyes smiley (😍) instead of the "normal" smiley face (😃). Our
browser windows show the value they're sending for `X-Faces-User`
above the grid of smilies ("unknown" means no header is being sent).
Both browsers currently show the same smiley.

<!-- @wait_clear -->

Here's the HTTPRoute that causes the A/B test to happen:

```bash
bat k8s/03-abtest/smiley-ab.yaml
```

<!-- @wait_clear -->

When we apply this, we'll continue to see "normal" smilies from our
first browser, but our second will show the heart-eyes smiley:

```bash
kubectl apply -f k8s/03-abtest/smiley-ab.yaml
```

<!-- @wait_clear -->

When the A/B test is done, if we want, we can easily edit the HTTPRoute
to give everyone heart eyes:

```bash
kubectl edit -n faces httproute/smiley-a-b
```

<!-- @wait_clear -->

# Sneak Peek: Linkerd 2.13

And there you have it! You can find the source for this workshop at

https://github.com/BuoyantIO/service-mesh-academy

in the `sneak-peek-2-13` directory.

As always, we welcome feedback! Join us at https://slack.linkerd.io/
for more.

<!-- @wait -->
<!-- @show_slides -->
