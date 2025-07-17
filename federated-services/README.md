<!--
SPDX-FileCopyrightText: 2024 Buoyant Inc.
SPDX-License-Identifier: Apache-2.0

SMA-Description: Exploring federated Services
-->

# Federated Services

This is the documentation - and executable code! - for the Linkerd 2.18
Service Mesh Academy workshop. The easiest way to use this file is to execute
it with [demosh].

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

# Federated Services

We're going to show how Linkerd's federated Services work. To that end, we
have two clusters - `east` and `west` - already running.

```bash
kind get clusters
```

The fact that we're using Kind is mostly irrelevant: the big things we need
are good support for Services of type LoadBalancer (so we've set up MetalLB
with our Kind clusters) and a flat network between the two clusters so that
Pods in one cluster can talk directly to Pods in the other cluster.

One big caveat: **this demo will not work with Docker Desktop for Mac.** Sorry
about that, but unfortunately Docker Desktop doesn't meaningfully bridge the
Docker network to the host network. If you're on a Mac, try Orbstack instead
(www.orbstack.dev).

<!-- @wait_clear -->

# Starting Out: Running Clusters

Both our clusters already have Linkerd installed, so let's make sure that
we're already starting with Linkerd in a good state:

```bash
linkerd --context east check
linkerd --context west check
```

So far so good!

<!-- @wait_clear -->

## Installing Faces

OK, so we have two clusters, and we have Linkerd installed on both of them.
Let's go ahead and install Faces on both clusters. We'll use Helm for this,
using a values file that turns off Faces' default massive error rate and
delays.

```bash
kubectl --context east create ns faces
kubectl --context east annotate ns/faces linkerd.io/inject=enabled

helm install --kube-context east \
     faces -n faces \
     oci://ghcr.io/buoyantio/faces-chart --version 2.0.0 \
     --values clusters/east/faces-values.yaml \
     --wait

kubectl --context east rollout status -n faces deploy

kubectl --context west create ns faces
kubectl --context west annotate ns/faces linkerd.io/inject=enabled

helm install --kube-context west \
     faces -n faces \
     oci://ghcr.io/buoyantio/faces-chart --version 2.0.0 \
     --values clusters/west/faces-values.yaml \
     --wait

kubectl --context west rollout status -n faces deploy
```

As a quick check, we can grab the LoadBalancer IP address of the `faces-gui`
Services in each cluster and check them out in the browser:

```bash
EAST_IP=$(kubectl --context east get svc -n faces faces-gui -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
#@immed
echo "East Faces: http://${EAST_IP}/"
WEST_IP=$(kubectl --context west get svc -n faces faces-gui -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
#@immed
echo "West Faces: http://${WEST_IP}/"
```

<!-- @browser_then_terminal -->

We can see that the east cluster shows us grinning smileys on blue
backgrounds, while the west cluster shows us heart-eyed smileys on green
backgrounds. So far so good.

<!-- @wait_clear -->

## Routing with Gateway API

Let's also quickly show that both clusters have working Gateway API
installations. We'll do this by installing a simple HTTPRoute in each cluster
that routes `smiley` traffic to `smiley2`, which returns a different smiley.

<!-- @show_5 -->

First, the `east` cluster. When we apply the Route, we'll see a switch from
grinning smileys to meh-face smileys:

```bash
bat clusters/east/smiley-route.yaml
kubectl --context east apply -f clusters/east/smiley-route.yaml
```

When we remove the Route, we'll see the grinning smileys come back:

```bash
kubectl --context east delete -f clusters/east/smiley-route.yaml
```

<!-- @wait_clear -->

Then we'll do the same in the `west` cluster. Here, our heart-eyed smileys
will be replaced with rolling-eyed smileys:

```bash
bat clusters/west/smiley-route.yaml
kubectl --context west apply -f clusters/west/smiley-route.yaml
```

And, again, when we remove the Route, we'll see the heart-eyed smileys come
back:

```bash
kubectl --context west delete -f clusters/west/smiley-route.yaml
```

<!-- @wait_clear -->
<!-- @show_terminal -->

## Multicluster with Federated Services

So far so good, but honestly also not all that interesting. We have two
independent clusters running two independent instances of Faces, and they
don't know about each other at all. What we want to do is set up multicluster
so that the `faces` workloads in the `east` and `west` clusters can talk to
each other.

We're going to do this in a way that might seem a little odd at first:

- We'll install the multicluster extension in both clusters, which will
  set up the controllers that will mirror Services between clusters.

<!-- @wait -->

- We'll then generate the Link resources that will actually link the clusters
  together, but we will _not_ apply them. Our clusters will remain unlinked at
  this point.

<!-- @wait -->

- Instead, we'll next enable federated Services in both clusters. Then we'll
  set up Faces so that it's using the newly-federated Services.

<!-- @wait -->

- Finally, we'll apply the generated Link resources, which will link the
  clusters together and let traffic flow between them.

<!-- @wait -->

Doing things in this order lets us use the single-cluster setup to verify that
the application is already working, _exactly_ as it will with multiple
clusters, before you start messing with linking the clusters at all. This is a
failsafe: if everything is working with the single-cluster federated Service
setup, then if the linking fails, no big deal, everything will still be
running.

<!-- @wait_clear -->

## Installing the Multicluster Extension

So! Let's start by installing the multicluster extension in both clusters.
Starting with Linkerd 2.18, things look a little different than they did in
previous versions:

- First, we'll need to provide values to each `linkerd multicluster install`
  to tell Linkerd which clusters we'll be linking to, so that it can set up
  the right controllers to mirror Services. (This is likely to get simpler in
  later releases.)

- We then use the new `linkerd multicluster link-gen` command to generate the
  resources that we need in order to link the clusters together.

Crucially, the output from `linkerd multicluster link-gen` is
_GitOps-compatible_: you can check it into a Git repository, and then use a
GitOps tool like ArgoCD or Flux to deploy it. (The old `linkerd multicluster
link` command is now deprecated: the resources it produced don't work with
GitOps.)

<!-- @wait_clear -->

So let's go ahead and get multicluster set up between our two clusters! First,
make sure they have the same trust anchor (this looks worse than it is, I
promise):

```bash
kubectl --context east \
        get configmap -n linkerd linkerd-identity-trust-roots \
        -o jsonpath='{.data.ca-bundle\.crt}' \
    | step certificate inspect --format json \
    | jq -r '.extensions.subject_key_id'

kubectl --context west \
        get configmap -n linkerd linkerd-identity-trust-roots \
        -o jsonpath='{.data.ca-bundle\.crt}' \
    | step certificate inspect --format json \
    | jq -r '.extensions.subject_key_id'
```

As long as those are the same, we're good to go. Let's get the multicluster
extension installed, remembering that we need to provide values that specify
the links we'll be creating _and_ that we need to specify `--gateway=false`
so that we can use federated Services!

```bash
bat clusters/east/mc-values.yaml

linkerd --context east multicluster install \
          --gateway=false \
          --values clusters/east/mc-values.yaml \
        | kubectl --context east apply -f -

bat clusters/west/mc-values.yaml

linkerd --context west multicluster install \
          --gateway=false\
          --values clusters/west/mc-values.yaml \
        | kubectl --context west apply -f -

linkerd --context east multicluster check
linkerd --context west multicluster check
```

<!-- @wait_clear -->

## Generating Links

So far so good! Next up, we need to generate link resources. This is pretty
simple -- but pay attention to the output! We're not just passing it to
`kubectl apply`; instead, we're just saving the link YAML. (And, again, using
`--gateway=false` is important here.)

```bash
linkerd --context east multicluster link-gen \
          --cluster-name=east \
          --gateway=false > east-link.yaml
linkerd --context west multicluster link-gen \
          --cluster-name=west \
          --gateway=false > west-link.yaml
```

Just for the fun of it, let's compare the output of `linkerd multicluster
link-gen` with the output of the old `linkerd multicluster link`:

```bash
linkerd --context east multicluster link \
          --cluster-name=east \
          --gateway=false > east-old-link.yaml

bat east-link.yaml
bat east-old-link.yaml
```

Pretty awful, huh? The new `link-gen` command is much cleaner, and the output
is GitOps-compatible. You can check it into a Git repository, and then use a
GitOps tool like ArgoCD or Flux to deploy it, though we sadly don't have time
to do that right now.

<!-- @wait_clear -->

## Setting up Federated Services

Next up, we'll turn the `smiley` and `color` Service in the `east` cluster
into federated Services. This is just a matter of labeling the Services in the
`east` cluster with the `mirror.linkerd.io/federated=member` label. This tells
Linkerd that these Services should be mirrored to other clusters, when other
clusters appear.

```bash
kubectl --context east -n faces label svc/smiley mirror.linkerd.io/federated=member
kubectl --context east -n faces label svc/color mirror.linkerd.io/federated=member
```

Then we'll repeat that for the `west` cluster:

```bash
kubectl --context west -n faces label svc/smiley mirror.linkerd.io/federated=member
kubectl --context west -n faces label svc/color mirror.linkerd.io/federated=member
```

If we check the Services in each cluster, we'll see new `smiley-federated` and
`color-federated` Services:

```bash
kubectl --context east -n faces get svc
kubectl --context west -n faces get svc
```

Remember: we haven't actually linked our clusters yet! so at the moment, our
federated Services will have totally disjoint endpoints. For example, let's
use `linkerd diagnostics endpoints` to look at the actual endpoints registered
to the `smiley-federated` Service (this command will take several seconds for
each cluster):

```bash
linkerd --context east diagnostics endpoints \
        smiley-federated.faces.svc.cluster.local
linkerd --context west diagnostics endpoints \
        smiley-federated.faces.svc.cluster.local
```

You can see that each has a single endpoint, which is the `smiley` Service in
that cluster. We can verify this by looking at the Pods in each cluster:

```bash
kubectl --context east -n faces get pods -l faces.buoyant.io/component=smiley -o wide
kubectl --context west -n faces get pods -l faces.buoyant.io/component=smiley -o wide
```

Looking at the Pod IP addresses, we can see that the single endpoint of the
`smiley-federated` Service in the `east` cluster is the single `smiley` Pod in
the `east` cluster, and the single endpoint of the `smiley-federated` Service
in the `west` cluster is the single `smiley` Pod in the `west` cluster.

In other words, until we link the clusters, our federated Services are
just like any other Service: they have a single endpoint, which is the
`smiley` Service in the cluster where the federated Service is running.

<!-- @wait_clear -->

## Metrics and Federated Services

Right now, of course, our Faces app is using the ordinary `smiley` and `color`
Services. We can't prove that with Linkerd Viz, unfortunately -- it looks at
which endpoints are in play, rather than which Services are being used. But we
_can_ prove it by looking directly into the proxy metrics!

The `linkerd diagnostics proxy-metrics` command lets us look at the metrics
that the proxy is collecting, and two specific metrics are particularly useful
for us here:

- `outbound_http_route_backend_requests_total` is a gauge of how many
  requests the proxy is sending to HTTP backends, and
- `outbound_grpc_route_backend_requests_total` is a gauge of how many
  requests the proxy is sending to gRPC backends.

So if we look at those two metrics for the `face` workload, we can see which
Services it's using by looking at the labels for each metric:

```bash
linkerd --context east diagnostics proxy-metrics -n faces deploy/face \
          | egrep "outbound_http_route_backend_requests_total|outbound_grpc_route_backend_requests_total" \
          | egrep "smiley|color" \
          | sed -e 's/,/\n    /g'
```

Even that's awful, but we can see that it shows us

- `parent_name` and `parent_port` for the Service to which the request is
  being sent;
- `backend_name` and `backend_port` for the Service to which Linkerd actually
  delivered the request; and
- `route_kind` and `route_name` for the HTTPRoute or GRPCRoute that
  matched the request.

<!-- @wait_clear -->

### Using the Proxy Metrics Less Painfully

Trying to manage those metrics is enough of a pain that it's worth writing
some code to deal with it. The `crunch_service_metrics.py` script does exactly
that: it reads the proxy metrics and prints out a summary of the requests that
the proxy is sending to each backend Service, grouped by the protocol and
backend Service. If we run it, we can see that the `face` workload is talking
only to `color` and `smiley`:

```bash
python3 crunch_service_metrics.py
```

<!-- @clear -->

### Making the Proxy Metrics More Useful

What's weird is that `color` traffic is showing up as HTTP, even though it's
gRPC traffic. This is a gotcha: to get really good metrics for gRPC, you need
a GRPCRoute (that's currently the only way to let Linkerd know that gRPC
traffic is really gRPC). So let's go ahead and set up a GRPCRoute for `color`
-- we'll just use a no-op route right now, since all we want are metrics.

```bash
bat clusters/east/color-metrics-route.yaml
kubectl --context east apply -f clusters/east/color-metrics-route.yaml
bat clusters/west/color-metrics-route.yaml
kubectl --context west apply -f clusters/west/color-metrics-route.yaml
```

Now if we run the `crunch_service_metrics.py` script again, we can see that
the `color` traffic is now showing up as gRPC, which is what we want.

```bash
python3 crunch_service_metrics.py
```

<!-- @clear -->

### Switching to Federated Services

Finally, let's switch our Faces app to use the federated Services instead of
the `smiley` and `color` Services. (We could also do this bit with HTTPRoutes,
but let's not: we'll just go directly to the federated Services and save
Gateway API for later.)

<!-- @show_5 -->

```bash
kubectl --context east set env -n faces deploy/face \
          SMILEY_SERVICE=smiley-federated \
          COLOR_SERVICE=color-federated
kubectl --context east rollout status -n faces deploy/face
```

All throughout, we saw that Faces was running OK. Let's  do that for the
`west` cluster too:

```bash
kubectl --context west set env -n faces deploy/face \
          SMILEY_SERVICE=smiley-federated \
          COLOR_SERVICE=color-federated
kubectl --context west rollout status -n faces deploy/face
```

<!-- @wait -->

And _now_ if we run the `crunch_service_metrics.py` script, we'll see that the
`face` workload is now using the `smiley-federated` and `color-federated`
Services instead of the `smiley` and `color` Services:

```bash
python3 crunch_service_metrics.py
```

<!-- @clear -->

### Making the Proxy Metrics More Useful (Again)

Oops. Note that `color-federated` is showing up as HTTP again. This is exactly
the same problem as before: we need a GRPCRoute to let Linkerd know that this
is gRPC traffic. So let's go ahead and set up a GRPCRoute for
`color-federated` in both clusters, then rerun the script.

```bash
bat clusters/east/color-federated-metrics-route.yaml
kubectl --context east apply -f clusters/east/color-federated-metrics-route.yaml
bat clusters/west/color-federated-metrics-route.yaml
kubectl --context west apply -f clusters/west/color-federated-metrics-route.yaml

python3 crunch_service_metrics.py
```

<!-- @clear -->

## Linking the Clusters

At this point, both clusters are using federated Services for `color`
and for `smiley`, but the clusters are still not linked together. The
`smiley-federated` Service in the `east` cluster doesn't know about the
`smiley` Service in the `west` cluster, and vice versa.

<!-- @show_5 -->

Suppose we go ahead and actually apply those generated link resources?
(Pay careful attention to contexts here! We want to apply the `east`
link to the `west` cluster and vice versa.)

```bash
kubectl --context west apply -f east-link.yaml
kubectl --context east apply -f west-link.yaml
```

And poof! The federated Services just picked up their new endpoints
from the other cluster. We can see this by looking at the endpoints,
and of course we'll see the GUIs change over the next few seconds too:

```bash
linkerd --context east diagnostics endpoints \
          smiley-federated.faces.svc.cluster.local
linkerd --context west diagnostics endpoints \
          smiley-federated.faces.svc.cluster.local

linkerd --context east diagnostics endpoints \
          color-federated.faces.svc.cluster.local
linkerd --context west diagnostics endpoints \
          color-federated.faces.svc.cluster.local
```

This is the real power of federated Services: _they just act
like Services_, including the way routing just does the right
thing as endpoints appear and disappear. For example, suppose we
scale the `east` cluster's `color` workload down to zero:

```bash
kubectl --context east -n faces scale deploy/color --replicas=0
```

The Faces application keeps running just fine, but of course now
all the cells have the green background from the `west` cluster's
`color` workload, because there are no available `color` endpoints
to appear in the `east` cluster:

```bash
linkerd --context east diagnostics endpoints \
          color-federated.faces.svc.cluster.local
linkerd --context west diagnostics endpoints \
          color-federated.faces.svc.cluster.local
```

We can do the same thing with `smiley`: if we scale the `west`
cluster's `smiley` workload down to zero, then we'll be back to
seeing grinning smileys from the `east` cluster's `smiley`
workload everywhere:

```bash
kubectl --context west -n faces scale deploy/smiley --replicas=0

linkerd --context east diagnostics endpoints \
          smiley-federated.faces.svc.cluster.local
linkerd --context west diagnostics endpoints \
          smiley-federated.faces.svc.cluster.local
```

<!-- @wait_clear -->

## Back to the Metrics

One interesting gotcha here: the metrics we're looking at show us
_Services_, not _endpoints_. That means that if we run our
`crunch_service_metrics.py` script right now, we'll still just see
`smiley-federated` and `color-federated` Services -- it won't show
us the individual endpoints that are backing those Services.

There's an older `request_total` metric that does show us the
individual endpoints, but it doesn't show us route information or
protocol. Unfortunately, the metrics story is slightly less ideal
than we'd like it to be! We're working on it.

<!-- @wait_clear -->

## Gateway API and Cross-Cluster Routing

Now that we have our clusters linked together, let's look at some complex
stuff. Let's use Gateway API to make our GUI do different things for the
center cells and the edge cells, starting with the `east` cluster.

We'll start by routing the `color-federated` traffic for the center cells
to `color2`, which returns yellow. We'll do this with a GRPCRoute that
matches on the gRPC method, which is "Center" for the center cells and
"Edge" for the edge cells, and routes the "Center" method to `color2`.

```bash
bat clusters/east/color-method.yaml
```

When we apply that, we'll instantly see the center cells change to
yellow in the GUI.

```bash
kubectl --context east apply -f clusters/east/color-method.yaml
```

So far so good! But suppose we flip over and take a look at the
`west` cluster?

<!-- @wait_clear -->

## The Routing Gotcha

This is the main gotcha of Gateway API with any cross-cluster
routing: _routing decisions only happen where the request originates_.
So if our `east` cluster `face` workload sends a request, _all the
routing happens in the `east` cluster_ and the request goes directly
to whichever pod is chosen.

That means that if we want this to work in the `west` cluster too, we
have to set up the same GRPCRoute in the `west` cluster. So let's do
that.

```bash
bat clusters/west/color-method.yaml
kubectl --context west apply -f clusters/west/color-method.yaml
```

Uhhhhh wait. Those center cells aren't yellow, they're red. Why??

<!-- @wait -->
<!-- @show_terminal -->

Let's look back at our metrics again.

```bash
python3 crunch_service_metrics.py
```

<!-- @clear -->

## The Routing Gotcha

What's going here is that `color2` is _not_ a federated Service: it's
independent in each cluster. So when the `east` cluster `face` workload sends
a request, it goes to the `color2` Service in the `east` cluster, which
returns yellow. But when the `west` cluster `face` workload sends a request,
it goes to the `color2` Service in the `west` cluster, which returns red.

<!-- @wait -->

Sometimes this may be exactly what you want, which is why this capability
exists in Linkerd! But of course, sometimes it's _not_ what you want -- and in
that case, since a federated Service is just a Service, you can simply create
a federated Service for `color2` in both clusters, and then use that as the
`backendRef` in the GRPCRoute.

So let's do that. We'll start by labeling the `color2` Service in both
clusters with the `mirror.linkerd.io/federated=member` label, which will
cause Linkerd to mirror the `color2` Service to the other cluster:

```bash
kubectl --context east -n faces label svc/color2 mirror.linkerd.io/federated=member
kubectl --context west -n faces label svc/color2 mirror.linkerd.io/federated=member
```

We'll see the `color2-federated` Service appear in both clusters:

```bash
kubectl --context east -n faces get svc
kubectl --context west -n faces get svc
```

Now we can go back to our GRPCRoute in both clusters and change the
`backendRef` to point to `color2-federated` instead of `color2`.

<!-- @show_5 -->

```bash
bat clusters/east/color-method-federated.yaml
kubectl --context east apply -f clusters/east/color-method-federated.yaml
bat clusters/west/color-method-federated.yaml
kubectl --context west apply -f clusters/west/color-method-federated.yaml
```

Now we'll see a mix of yellow and red in the center cells. If we scale
down the `color2` workload in the `east` cluster, we'll see the center
cells turn red.

```bash
kubectl --context east -n faces scale deploy/color2 --replicas=0
```

And if we scale `color2` in the `east` cluster back up, then scale down the
`color2` workload in the `west` cluster, we'll see the center cells turn
yellow.


```bash
kubectl --context east -n faces scale deploy/color2 --replicas=1
```

We don't really _have_ to wait for the rollout to finish, but it does save us
any errors for when all our endpoints are missing:

```bash
kubectl --context east -n faces rollout status deploy/color2
kubectl --context west -n faces scale deploy/color2 --replicas=0
```

<!-- @wait_clear -->

Again: the `color2-federated` Service acts like a Service. As endpoints become
available or unavailable, the right thing happens no matter where the
endpoints are.

<!-- @wait_clear -->

## Retries and Federated Services

Of course, unhappy workloads won't always be so polite as to simply vanish
entirely. Let's tell the `smiley` workload in the `east` cluster to return a
500 error 30% of the time, by setting the environment variable that it so
politely provides for us:

```bash
kubectl --context east -n faces \
    set env deployment/smiley ERROR_FRACTION=30
```

(Note that there is no `smiley` workload in the `west` cluster.)

If we wait a moment, we'll start to see cursing faces in
our GUI.

<!-- @wait -->

The natural way to want to manage this with Linkerd is with
retries! and... well, wait a minute. We would normally annotate
our Service with some `retry.linkerd.io` annotations to get
Linkerd to retry requests that fail with a 5xx error code.

But! `smiley-federated` is a federated Service, and as such, it
_mirrors_ annotations from its member Services onto the federated
Service. So we need to annotate the `smiley` Service, not the
`smiley-federated` Service:

```bash
kubectl --context east annotate -n faces \
    service smiley \
        retry.linkerd.io/http=5xx \
        retry.linkerd.io/limit=3
```

If we watch the GUI in the `east` cluster, we'll see that the
cursing faces go away! But what about the `west` cluster?

<!-- @wait -->

Much like with routing, there's a gotcha here: _retries only
happen where the request originates_, and the annotation
mirroring doesn't cross cluster boundaries (at least for the
moment). So we need to annotate the `smiley` Service in the
`west` cluster too:

```bash
kubectl --context west annotate -n faces \
    service smiley \
        retry.linkerd.io/http=5xx \
        retry.linkerd.io/limit=3
```

<!-- @wait_clear -->
<!-- @show_terminal -->

## Federated Services and Auth

One other thing to remember about federated Services is that even though they
act like Services, you really do have to remember that they're in different
clusters when it comes to authorization (at least, for the moment). So, for
example, here's a policy that will deny traffic to the `smiley` workload
unless it comes from the `face` ServiceAccount in the `faces` namespace:

```bash
bat clusters/east/smiley-auth.yaml
```

Right now, the `face` workload is using the `default` ServiceAccount:

```bash
linkerd identity --context east -n faces -l faces.buoyant.io/component=face \
    | grep 'Subject: CN'
```

<!-- @show_5 -->

So, if we create the ServiceAccount...

```bash
kubectl --context east apply -f clusters/east/smiley-sa.yaml
```

...and then apply the policy, we should no longer be able to fetch
smilies!

```bash
kubectl --context east apply -f clusters/east/smiley-auth.yaml
```

<!-- @wait_clear -->

## Federated Services and Auth

As you can see, this correctly shut down access from _both_ clusters:
where routing happens where the request originates, authorization happens
where the request is received (that's the only way things make sense). So
it doesn't matter where the request comes from, the policy is enforced
correctly.

Let's go ahead and switch the `face` workload to use the correct
ServiceAccount.

```bash
kubectl --context east -n faces \
    set serviceaccount deployment/face face
kubectl --context east -n faces rollout status deploy
```

There we go, we have working smilies again... at least from the `east`
cluster.

<!-- @wait -->

Of course, the `west` cluster is still using the `default`
ServiceAccount, so it still can't access the `smiley` Service. If we
switch it as well, then we'll have working smilies in both clusters:

```bash
kubectl --context west apply -f clusters/west/smiley-sa.yaml
kubectl --context west -n faces \
    set serviceaccount deployment/face face
kubectl --context west -n faces rollout status deploy
```

<!-- @wait_clear -->
<!-- @show_terminal -->

## Summary

So there's the whirlwind tour of federated Services! There's more to this, of
course: these are just some of the highlights.

<!-- @wait -->

As always, feedback is welcome! You can reach me at flynn@buoyant.io or as
@flynn on the Linkerd Slack (https://slack.linkerd.io).

<!-- @wait -->
<!-- @show_slides -->
