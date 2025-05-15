<!--
SPDX-FileCopyrightText: 2024 Buoyant Inc.
SPDX-License-Identifier: Apache-2.0

SMA-Description: Exploring Linkerd 2.18 features
-->

# Linkerd 2.18 Features

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

# Linkerd 2.18 Features

We're going to quickly demo a few things about Linkerd 2.18, including:

- Gateway API decoupling
- Protocol declarations
- GitOps-compatible multicluster

These will be _quick_ looks, not deep dives: don't panic, we'll do deep dives
over time! We'll hit a couple of other things along the way, too. One big
caveat: **this demo will not work with Docker Desktop for Mac.** Sorry about
that, but unfortunately Docker Desktop doesn't meaningfully bridge the Docker
network to the host network. If you're on a Mac, try Orbstack instead
(www.orbstack.dev).

<!-- @wait_clear -->

## Starting Out: Gateway API Decoupling

...or, more accurately, "hey, you have to install the Gateway API CRDs
yourself now". We currently have two clusters running: `east` and `west`:

```bash
kind get clusters
```

The `east` cluster is already running Linkerd, but the `west` cluster is not:

```bash
linkerd --context east check
linkerd --context west check
```

<!-- @wait_clear -->

So let's go ahead and get the `west` cluster running! If we just try `linkerd
install`, we'll see that it won't work:

```bash
linkerd --context west install --crds | kubectl --context west apply -f -
```

We _could_ use `--set installGatewayAPI=true`, but we'll follow current best
practices instead and install the Gateway API CRDs ourselves. The error output
mentions Gateway API 1.2.1, but the latest Gateway API right now is actually
1.3.0:

```bash
kubectl --context west apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/standard-install.yaml
```

Now we can install Linkerd. First, we install the Linkerd CRDs:

```bash
linkerd --context west install --crds | kubectl --context west apply -f -
```

Next, we install the control plane, making sure to use the same certificates
that we used for the `east` cluster!

```bash
linkerd --context west install \
          --set disableIPv6=true \
          --identity-trust-anchors-file certs/root.crt \
          --identity-issuer-certificate-file clusters/west/issuer.crt \
          --identity-issuer-key-file clusters/west/issuer.key \
        | kubectl --context west apply -f -
linkerd --context west check
```

<!-- @wait_clear -->

Let's go ahead and install Faces, too, to make sure things are really working.
(The values file we're using here turns off Faces' default massive error rate
and delays.)

```bash
kubectl --context west create ns faces
kubectl --context west annotate ns/faces linkerd.io/inject=enabled

helm install --kube-context west \
     faces -n faces \
     oci://ghcr.io/buoyantio/faces-chart --version 2.0.0-rc.7 \
     --values clusters/west/faces-values.yaml \
     --wait

kubectl --context west rollout status -n faces deploy
```

As a quick check, we can grab the LoadBalancer IP address of the `faces-gui`
Service and check it out in the browser:

```bash
IP=$(kubectl --context west get svc -n faces faces-gui -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
#@immed
echo "Faces: http://${IP}/"
```

<!-- @browser_then_terminal -->

And we can prove that the `west` cluster has working Gateway API by installing
a couple of Routes. First, we'll use an HTTPRoute to route `smiley` traffic to
`smiley2`, which returns a heart-eyed smiley instead of a grinning smiley:

<!-- @show_5 -->

```bash
bat clusters/west/smiley-route.yaml
kubectl --context west apply -f clusters/west/smiley-route.yaml
```

Then we'll use a GRPCRoute to route `color` for just the center
cells to `color2`, which returns green instead of blue:

```bash
bat clusters/west/color-method.yaml
kubectl --context west apply -f clusters/west/color-method.yaml
```

That's about it for Gateway API decoupling!

<!-- @wait -->
<!-- @show_slides -->
<!-- @wait_clear -->
<!-- @show_terminal -->

## Protocol Declarations

Next up, let's take a look at protocol declarations. This is a new feature
that allows you to specify the protocol for a Service using the Service's
`appProtocol` field.

Demoing this is a little tricky! but there's a way to do it. First up, let's
get a deployment running (in the `west` cluster again) that has some network
tools like `curl` and `telnet` in it.

```bash
bat clusters/tools.yaml
kubectl --context west apply -f clusters/tools.yaml
```

Since our `tools` deployment is in the `faces` namespace, it's part of the
mesh, which is what we want. Next up, we'll use `kubectl exec` to `curl` the
`smiley` service from the `tools` deployment.

```bash
kubectl --context west exec -n faces -it deploy/tools -c tools -- \
        curl -v http://smiley/
```


Check out the `x-faces-pod` header: its value is the name of the pod that
actually handled this request (this isn't Linkerd magic, the `smiley` workload
always supplies that header). We can see that it's a `smiley2` pod, which
makes sense because there's an HTTPRoute redirecting `smiley` traffic to
`smiley2`.

<!-- @wait -->

That rerouting works because Linkerd successfully detected that this was HTTP
traffic, so it knew to honor HTTPRoutes. But what if the client took too long
to send the request, and protocol detection timed out? In that case, Linkerd
would assume this was raw TCP traffic, and would not honor the HTTPRoute.

<!-- @wait_clear -->

We can test that by using `telnet` to speak HTTP by hand... but waiting ten
seconds before sending our HTTP request. This will break protocol detection
and cause Linkerd to not honor the HTTPRoute.

To mimic the `curl` request above with `telnet`, we run `telnet smiley 80` and
then send

```
GET / HTTP/1.1
Host: smiley
```

followed by a blank line. But don't forget to wait ten seconds before sending
the request!

```bash
kubectl --context west exec -n faces -it deploy/tools -c tools -- \
        telnet smiley 80
```

This time, you'll see that the `x-faces-pod` header says the request was
handled by a `smiley` pod, not a `smiley2` pod. This is because Linkerd
assumed this was raw TCP traffic, and didn't honor the HTTPRoute.

<!-- @wait_clear -->

For completeness' sake, we can repeat that but send the request right away.
If we do that, we'll see that the request is handled by a `smiley2` pod, just like
the `curl` request.

```bash
kubectl --context west exec -n faces -it deploy/tools -c tools -- \
        telnet smiley 80
```

<!-- @wait_clear -->

## Using `appProtocol`

So! Let's fix this by using the `appProtocol` field in the Service. If we set
that to `http`, Linkerd should treat this as HTTP traffic no matter how long
we wait.

```bash
kubectl --context west edit svc -n faces smiley
kubectl --context west exec -n faces -it deploy/tools -c tools -- \
        telnet smiley 80
```

We should see that the request is handled by a `smiley2` pod, just like the
`curl` request!

<!-- @wait -->
<!-- @show_slides -->
<!-- @wait_clear -->
<!-- @show_terminal -->

## GitOps-Compatible Multicluster

Finally, let's take a look at GitOps-compatible multicluster. In Linkerd 2.18,
the `linkerd multicluster link` command is deprecated. Instead:

- We provide values to `linkerd multicluster install` that tell Linkerd which
  clusters we'll be linking to, so that it can set up the right controllers to
  mirror Services.

- We then use the new `linkerd multicluster link-gen` command to generate the
  resources that we need in order to link the clusters together.

Crucially, the output from `linkerd multicluster link-gen` is
_GitOps-compatible_: you can check it into a Git repository, and then use a
GitOps tool like ArgoCD or Flux to deploy it. This is a big improvement over
the old `linkerd multicluster link` command, which required you to run a
command on each cluster to set up the link.

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

## Side Quest: Faces and Federated Services

We'd like to see something to prove that we really can just apply the
generated Links and have things work, though, so let's fire up Faces in the
`east` cluster too:

```bash
kubectl --context east create ns faces
kubectl --context east annotate ns/faces linkerd.io/inject=enabled
helm install --kube-context east \
     faces -n faces \
     oci://ghcr.io/buoyantio/faces-chart --version 2.0.0-rc.7 \
     --values clusters/east/faces-values.yaml \
     --wait

kubectl --context east rollout status -n faces deploy
```

Again, we can grab the LoadBalancer IP address of the `faces-gui` Service in
the `east` cluster and check it out in the browser:

```bash
IP=$(kubectl --context east get svc -n faces faces-gui -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
#@immed
echo "Faces: http://${IP}/"
```

<!-- @browser_then_terminal -->

Next up, let's set up federated Services for `smiley` and `color`. This is
just a matter of labeling the Services in both clusters.

```bash
kubectl --context east -n faces label svc/smiley mirror.linkerd.io/federated=member
kubectl --context west -n faces label svc/smiley mirror.linkerd.io/federated=member
kubectl --context east -n faces label svc/color mirror.linkerd.io/federated=member
kubectl --context west -n faces label svc/color mirror.linkerd.io/federated=member
```

If we check the Services in each cluster, we'll see new `smiley-federated` and `color-federated` Services:

```bash
kubectl --context east -n faces get svc
kubectl --context west -n faces get svc
```

Remember: we haven't actually linked our clusters yet! so at the moment, our
federated Services will have totally disjoint endpoints. For example, let's
look at the `smiley-federated` Service (this will take a few seconds for each
cluster):

```bash
linkerd --context east diagnostics endpoints smiley-federated.faces.svc.cluster.local
linkerd --context west diagnostics endpoints smiley-federated.faces.svc.cluster.local
```

<!-- @wait_clear -->
<!-- @show_5 -->

To prove that the `smiley-federated` and `color-federated` Services are
actually working, let's tweak Faces to go directly to them (we could also do
this with HTTPRoutes, but let's show off using the federated Services
directly):

```bash
kubectl --context east set env -n faces deploy/face \
          SMILEY_SERVICE=smiley-federated \
          COLOR_SERVICE=color-federated
kubectl rollout status -n faces deploy/face
```

So far so good, right? But watch what happens when we delete the
`smiley` workload in the `east` cluster:

```bash
kubectl --context east -n faces scale deploy/smiley --replicas=0
```

That's no good.

<!-- @wait_clear -->

## Linking the Clusters

Suppose we go ahead and actually apply those generated link resources? (Pay
careful attention to contexts here! We want to apply the `east` link to the
`west` cluster and vice versa.)

```bash
kubectl --context west apply -f east-link.yaml
kubectl --context east apply -f west-link.yaml
```

And poof! The `smiley-federated` Service in the `east` cluster just
automatically picked up the `smiley` from the `west` cluster:

```bash
linkerd --context east diagnostics endpoints \
          smiley-federated.faces.svc.cluster.local
linkerd --context west diagnostics endpoints \
          smiley-federated.faces.svc.cluster.local
```

This is the real power of federated Services: _they just act
like Services_, including the way routing just does the right
thing as endpoints appear and disappear. Let's make this a little
more obvious by switching the `smiley` workload in the `west`
cluster to return heart-eyed smileys:

```bash
kubectl --context west -n faces set env deploy/smiley \
          SMILEY=HeartEyes
kubectl --context west -n faces rollout status deploy/smiley
```

We'll see that immediately reflected in the GUI... but now
let's bring the `smiley` workload in the `east` cluster back up:

```bash
kubectl --context east -n faces scale deploy/smiley --replicas=1
```

That gives us a 50/50 split across clusters, since the
`smiley-federated` Service automatically starts load balancing
across the endpoints.

<!-- @wait_clear -->
<!-- @show_terminal -->

## Wait a Minute...

...didn't we already have an HTTPRoute in the `west` cluster that was
routing `smiley` traffic to `smiley2`, which already returned heart-eyed
smileys?

Yes, we did. This is the main gotcha of Gateway API with any cross-cluster
routing: _routing decisions only happen where the request originates_. So if
our `east` cluster `face` workload sends a request, _all the routing happens
in the `east` cluster_ and the request goes directly to whichever pod is
chosen.

Doing this any other way introduces the potential for some major disasters,
but it's definitely something to be aware of!

<!-- @wait_clear -->

## Summary

So there you have it! There are, of course, a lot more things in Linkerd 2.18;
these are just some of the highlights, with an aside about federated Services
-- but just these highlights help streamline a lot of real-world problems.

<!-- @wait -->

As always, feedback is welcome! You can reach me at flynn@buoyant.io or as
@flynn on the Linkerd Slack (https://slack.linkerd.io).

<!-- @wait -->
<!-- @show_slides -->
