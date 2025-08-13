<!--
SPDX-FileCopyrightText: 2024 Buoyant Inc.
SPDX-License-Identifier: Apache-2.0

SMA-Description: Reduce Cross-Zone Costs with HAZL
-->

# Reduce Cross-Zone Costs with HAZL

This is the documentation - and executable code! - for the Service Mesh
Academy workshop about using HAZL to reduce cross-zone costs. The easiest way
to use this file is to execute it with [demosh].

Things in Markdown comments are safe to ignore when reading this later. When
executing this with [demosh], things after the horizontal rule below (which
is just before a commented `@SHOW` directive) will get displayed.

[demosh]: https://github.com/BuoyantIO/demosh

This workshop will create a multizone k3d cluster for you. Make sure you don't
already have a cluster named "hazl".

<!-- @import demosh/check-requirements.sh -->
<!-- @start_livecast -->
---
<!-- @SKIP -->

## Creating the Cluster

OK, let's get this show on the road by creating a multi-zone cluster. This
will be a k3d cluster with one server Node and three agent Nodes; each agent
Node will be in a different zone (in this case, Zone A, Zone B, and Zone C).
We'll do our usual dance of setting up the cluster to expose ports 80 & 443 on
the host network, and of specifying a named network so that we can hook other
things up to it.

There's enough to this that we'll use a YAML file to specify the cluster
rather than doing it all on the command line.

```bash
bat k3d-multizone.yaml
k3d cluster create -c k3d-multizone.yaml --wait
kubectl cluster-info
kubectl get nodes
```

<!-- @wait_clear -->

## Installing Linkerd

Next up, we're going to install Buoyant Enterprise for Linkerd -- we need this
for HAZL to work! _This does require you to sign up for a free account with
Buoyant._ But really, it's worth it, and we won't sell your information to
anyone! To get set up, go to https://enterprise.buoyant.io/ and sign up.

Once done, you'll get to a page that'll show you three environment variables:

- `API_CLIENT_ID`
- `API_CLIENT_SECRET`
- `BUOYANT_LICENSE`

but for this workshop all you really need is `BUOYANT_LICENSE`.

<!-- @wait -->

Once you have your license key, it's time to install Linkerd!

For simplicity, we're just going to use the Linkerd CLI for this. **This is
not a production-ready installation** but it's OK for this workshop. In the
real world, you should really check out the Buoyant Lifecycle Operator.

With the CLI, though, we'll start by installing the Gateway API and Linkerd
CRDs:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/standard-install.yaml
linkerd install --crds | kubectl apply -f -
```

Then we can install Linkerd itself, and make sure all's well!

```bash
linkerd install | kubectl apply -f -
linkerd check
```

So far so good!

<!-- @wait_clear -->

## Installing Faces

Now that we have Linkerd installed, we need a test application. We'll use the
Faces demo, as usual, but remember that we have a multi-zone cluster! So we're
going to change things a bit from our usual installation:

- We'll put the `face` and `faces-gui` workloads for Faces in Zone A.
- We'll be using `faces-gui` as our "ingress" rather than installing a
  dedicated ingress controller.

<!-- @wait -->

- We'll install different `smiley` and `color` Deployments so that we can put
  one in each zone. All three `smiley` Deployments will be behind one `smiley`
  Service; all three `color` Deployments will be behind one `color` Service.

  (The reason we're using multiple Deployments like this is so we can
  independently scale them for the demo.)

<!-- @wait -->

We'll also tell Faces NOT to fail all the time; this isn't a resilience demo!

<!-- @wait_clear -->

## Installing Faces

As it happens, the Helm chart for Faces doesn't _really_ support everything
that we need to configure the multizone stuff using Helm values. Instead, I've
used `helm template` to dump out the YAML from the Helm chart, then edited
things by hand. Let's take a look.

`faces/faces.yaml` contains Services and Deployments for `face` and
`faces-gui`:

```bash
bat faces/faces.yaml
```

`faces/smilies.yaml` contains the Service and Deployments for all the `smiley`
workloads:

```bash
bat faces/smilies.yaml
```

Finally, `faces/colors.yaml` contains the Service and Deployments for all the
`color` workloads:

```bash
bat faces/colors.yaml
```

Given all that, let's get this show on the road:

```bash
kubectl create ns faces
kubectl annotate ns faces \
        linkerd.io/inject=enabled \
        config.alpha.linkerd.io/proxy-enable-native-sidecar=true

kubectl apply -f faces/faces.yaml
kubectl apply -f faces/smilies.yaml
kubectl apply -f faces/colors.yaml

kubectl rollout status -n faces deploy
```

Once again, let's doublecheck to make sure that our Pods are really running in
the correct zones.

```bash
kubectl get pods -n faces -o wide
```

OK! At this point everything should be running for us -- let's make sure of
that in the browser.

<!-- @browser_then_terminal -->
<!-- @SHOW -->

## Testing the Application

In the browser at the moment, we see a mix of lots of things:

- We see a grinning smiley from Zone A, a heart-eyed smiley from Zone B, and a
  rolling-eyes smiley from Zone C.

- We see a blue background for Zone A, a green background for Zone B, and a
  yellow background for Zone C.

While we'll see smilies and backgrounds mixing and matching, you'll note that
we _don't_ see many grinning smilies or blue backgrounds. That's because we
made the Zone A `smiley` and `color` workloads a little slower than the ones
in Zones B and C, and Linkerd tries really really hard to minimize latency.

We can also see this in stats -- and while we could look at stats with
Grafana, we'll cheat and run a quick script that reads `linkerd diagnostics
proxy-metrics` instead. (Just ignore the "raw" and "scaled" numbers for now.)

```bash
python zone-metrics.py
```

<!-- @clear -->
<!-- @show_5 -->

## HAZL

So we can see that the `face` Deployment - which is in Zone A - is mostly
sending its `smiley` and `color` traffic to Zone B and Zone C. That's
potentially a problem -- many cluster providers will charge extra for
cross-zone traffic, so routing a lot of traffic out to other zones isn't
ideal.

Enter HAZL, the High Availability Zonal Load Balancer. HAZL can fix this by
keeping traffic in-zone whenever it can.

Since we installed Linkerd using the CLI, we enable HAZL using the CLI:

```bash
linkerd upgrade \
    --set "destinationController.additionalArgs[0]=-ext-endpoint-zone-weights" \
    | kubectl apply -f -
```

<!-- @wait_clear -->

## HAZL

We can also see goodness with our metrics script:

```bash
python zone-metrics.py
```

<!-- @clear -->

## HAZL

This, of course, we could probably get with Kubernetes own topology-aware
routing. What topology-aware routing doesn't give us is resilience. Suppose
our `color-zone-a` workload crashes?

```bash
kubectl scale -n faces deploy/color-zone-a --replicas=0
```

Over in the browser, we'll see that we've just seamlessly switched
to a different zone.

<!-- @wait_clear -->

## HAZL

If `color-zone-a` comes back up, we'll see it start taking traffic
again.

```bash
kubectl scale -n faces deploy/color-zone-a --replicas=1
```

<!-- @wait_clear -->

## HAZL

Of course we can show this with `smiley-zone-a` as well... in fact,
let's drop `smiley-zone-a` and `smiley-zone-b` at the same time.

```bash
kubectl scale -n faces deploy/smiley-zone-a --replicas=0
kubectl scale -n faces deploy/smiley-zone-b --replicas=0
```

At this point we _only_ see the rolling-eyed smilies from Zone C.
Suppose we bring Zone B back?

```bash
kubectl scale -n faces deploy/smiley-zone-b --replicas=1
```

Of course, bringing Zone A back will immediately bring us all
the way back to just grinning smilies.

```bash
kubectl scale -n faces deploy/smiley-zone-a --replicas=1
```

<!-- @wait_clear -->
<!-- @show_terminal -->

## HAZL and Load

HAZL is also smart enough to know that if we overwhelm a workload, it should
bring in workloads from the other zones to help out. It makes decisions about
when to take action based on the _load_ for the workload, which is calculated
by multiplying the _latency_ (in seconds) and _throughput_ (in requests per
second) for each active endpoint, then adding the products together.

<!-- @wait -->

For each workload, HAZL defines a _low_ load value and a _high_ load value:

- When the measured load exceeds the _high_ value, HAZL brings in endpoints
  from other zones to help out.

- When the measured load falls below the _low_ value, HAZL starts removing
  endpoints from other zones.

These low- and high-water marks together define the _load band_, which is the
range of load values where HAZL will let the system stay in the steady state
without taking action.

<!-- @wait_clear -->

## HAZL and Load

We can see load information in the metrics that we get from `linkerd
diagnostics proxy-metrics`:

```bash
linkerd diagnostics proxy-metrics -n faces deploy/face \
    | grep -v '#' \
    | grep http_balancer_adaptive_load
```

<!-- @wait_clear -->

## HAZL and Load

There are three main metrics for load:

- `outbound_http_balancer_adaptive_load_average` is the current average load
- `outbound_http_balancer_adaptive_load_band_low` is the low load value
- `outbound_http_balancer_adaptive_load_band_high` is the high load value

Where this gets weird is that all of these values are _scaled_ by the number
of endpoints that are currently active: basically, Linkerd calculates the load
metric for each endpoint and adds them together. This means that the more
endpoints there are, the higher the total load will be, which in turn requires
adjusting the `low` and `high` values as well, so that everything is
consistent.

<!-- @wait -->

Unfortunately, this means that as HAZL is operating, you'll see the low-water
and high-water marks _changing their values_ over time, even if you don't
change them yourself. For this reason, our `zone-metrics.py` script shows both
the raw load numbers _and_ a scaled version, which is the raw numbers divided
by the number of active endpoints... which will be important when we talk
about configuring HAZL.

<!-- @wait_clear -->

## HAZL and Load

To watch how the load changes, we can use a simple shell script to change the
latency for each of our `color` and `smiley` Deployments:

```bash
bat set-latency.sh
```

<!-- @show_composite -->

```bash
bash set-latency.sh 500
```

We can watch the load numbers go up, and we can see HAZL become willing to
pull endpoints from extra zones when it crosses the high-water mark.

<!-- @wait -->

If we scale it further, it'll cross the high-water mark again, which will
trigger HAZL to pull in more endpoints, if there are any. (If there aren't any
more endpoints to pull in, there's nothing HAZL can do about that, of course.)

```bash
bash set-latency.sh 750
```

<!-- @wait_clear -->

## HAZL and Load

If we lower the latency, nothing happens until the load drops below the
low-water mark, at which point HAZL will start shedding out-of-zone endpoints.
Eventually, the in-zone endpoints are all that are left.

```bash
bash set-latency.sh 500
bash set-latency.sh 250
bash set-latency.sh 0
```

<!-- @wait_clear -->
<!-- @show_terminal -->

## Tuning HAZL

We can tune HAZL's behavior by changing the `low` and `high` load values,
either by adding environment variables at Linkerd install time or by
annotating individual Pods. We'll show the second approach.

The default load band values are:

- `low`: 0.8
- `high`: 2.0

but **the critical thing to remember is that these are per-endpoint values**,
so the low-water and high-water marks reported in the metrics will be the
configured values multiplied by the number of active endpoints. In turn, that
means that when you examine the load numbers to decide how to tune HAZL, **you
will need to divide the load numbers shown by the number of active endpoints**
as shown by the `scaled` numbers from `zone-metrics.py`.

<!-- @wait_clear -->

## Tuning HAZL

Actually tuning HAZL takes a bit of practice, but here's a way to approach it:

- Start with real-world load that matches your expected steady state, when all
  traffic should stay in zone. Set the load band to `low`: .5, `high`: 1000 (or some other number that's ridiculously higher than your expected load).

<!-- @wait -->

- Ramp the load up to a point that you think out-of-zone endpoints _should_ be
  pulled in. Set the high-water mark to something below this value.

<!-- @wait -->

- Ramp the load back down to a point that you think is safe to start dropping
  out-of-zone endpoints. Set the low-water mark to about this value.

<!-- @wait -->

- It should go without saying, but make sure that the low-water mark is below
  the high-water mark!

<!-- @wait_clear -->

## Tuning HAZL

Let's go ahead and do this for Faces.

In most real tuning scenarios, you would adjust traffic to modify the load.
We're going to simulate that by adding latency -- the overall effect is the
same.

<!-- @wait -->

Right now, we're running at 0ms added latency and the load is quite low. Let's
go ahead and set the load band to something absurd, by adding the annotation

```
balancer.buoyant.io/load-band: "0.5,1000"
```

to the Pod template for the `face` Deployment. We'll do this with `kubectl
edit` but of course you could do it with `kubectl patch` too.

```bash
kubectl edit deployment -n faces face
```

<!-- @show_composite -->

Now we can go ahead and add some latency to simulate a higher traffic level.
Let's pretend that 200ms latency is OK for our purposes.

```bash
bash set-latency.sh 200
```

Now we watch for a bit...

<!-- @wait -->

The load seems to have increased to about 1.5 or so, implying that we'll need
to set the high-water mark higher than that. Let's try 500ms.

```bash
bash set-latency.sh 500
```

Again, we watch for a bit...

<!-- @wait -->

That's _much_ higher. Let's try 300ms instead.

```bash
bash set-latency.sh 300
```

...and, again, watch for a bit.

<!-- @wait -->

That implies that perhaps we should set the high-water mark to about 2.0.
Let's try that.

```bash
kubectl edit deployment -n faces face
```

Watching for a bit now...

<!-- @wait -->

...we see that the load did indeed cross 2.0, and HAZL brought in another
endpoint! Let's try ramping the latency higher.

```bash
bash set-latency.sh 500
```

Again, we watch for a bit...

<!-- @wait -->

...and again, it crosses 2.0 and our third endpoint comes in. But it took
awhile, so maybe 2.0 is too high. Maybe 1.75 is better.

Let's ramp the load down to start over...

```bash
bash set-latency.sh 0
```

While we wait for HAZL to remove the extra endpoints, let's go ahead and
change the load band to 0.5,1.75.

```bash
kubectl edit deployment -n faces face
```

Once everything is quiet, let's ramp the load back up again.

```bash
bash set-latency.sh 200
bash set-latency.sh 300
bash set-latency.sh 500
```

We can see that HAZL is now a bit quicker to bring in endpoints, which seems
pretty reasonable. Now, how about on the way back down?

```bash
bash set-latency.sh 300
```

Give it a moment...

<!-- @wait -->

This seems like getting all the way back down to 0.5 isn't really reasonable.
Maybe 1.0 is a better target.

```bash
kubectl edit deployment -n faces face
bash set-latency.sh 500
bash set-latency.sh 300
bash set-latency.sh 200
bash set-latency.sh 125
```

End result: with properly tuned load bands, things can respond pretty quickly
in either direction. Tuning can take time, but it's a big win for the user
experience.

## HAZL and Retries

HAZL, of course, keeps working with other Linkerd features. As a really quick
example, let's make our `smiley` workloads less reliable:

```bash
kubectl set env -n faces deploy/smiley-zone-a ERROR_FRACTION=25
kubectl set env -n faces deploy/smiley-zone-b ERROR_FRACTION=25
kubectl set env -n faces deploy/smiley-zone-c ERROR_FRACTION=25
```

Things look worse now, right? So let's enable retries to make things happier.
Keep an eye on the load when we do this.

```bash
kubectl annotate -n faces service/smiley \
    retry.linkerd.io/http=5xx \
    retry.linkerd.io/limit=3
```

You can see both that the retries make the cursing faces go away... and that
the load goes up! If we bump the latency now...

```bash
bash set-latency.sh 200
```

...then after a bit we'll see HAZL pull in new endpoints for `smiley` but not
for `color`, because the load on `color` is still too low.

## Summary

And that's HAZL! It's a powerful tool for managing traffic in a service mesh,
providing features like adaptive load balancing and zone-aware routing, and it can save a ton of money in cloud infrastructure costs.

<!-- @wait -->
<!-- @show_slides -->
