<!--
SPDX-FileCopyrightText: 2024 Buoyant Inc.
SPDX-License-Identifier: Apache-2.0

SMA-Description: Kyverno 101 and Linkerd
-->

# Kyverno 101 and Linkerd

This is the documentation - and executable code! - for the Kyverno 101 and
Linkerd Service Mesh Academy workshop. The easiest way to use this file is to
execute it with [demosh].

Things in Markdown comments are safe to ignore when reading this later. When
executing this with [demosh], things after the horizontal rule below (which
is just before a commented `@SHOW` directive) will get displayed.

[demosh]: https://github.com/BuoyantIO/demosh

You'll need an **empty** cluster with LoadBalancer support to run this
workshop. If you don't already have such a cluster, `setup-base.sh` will
create a k3d cluster for you. (Note that if you're on a Mac, you'll have to
mess with things if you're using Docker Desktop for Mac. I highly recommend
you check out Orbstack instead.)

<!-- @import demosh/check-requirements.sh -->
<!-- @start_livecast -->
---
<!-- @SHOW -->

# Kyverno 101 and Linkerd

First things first! Let's make sure the Kyverno CLI is installed (if you don't
already have this, check out https://kyverno.io/docs/kyverno-cli/install/):

```bash
kyverno version
```

Of course, we need the Linkerd CLI too:

```bash
linkerd version --client --short
```

We'll be using Buoyant Enterprise for Linkerd for this demo. If you want to do
the same, you will need a free Buoyant ID from https://enterprise.buoyant.io/.
We promise it’s worth it and we won’t sell your information to anyone! 🙂

(Linkerd edge-25.4.4 or later will work, too.)

Given the CLIs, we can get things set up on our cluster!

<!-- @wait_clear -->

## Install Linkerd

We'll start by installing Linkerd, using the usual three-step process: first
we install the Gateway API CRDs...

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/standard-install.yaml
```

Then we install the Linkerd CRDs, followed by Linkerd itself...

```bash
linkerd install --crds | kubectl apply -f -
linkerd install | kubectl apply -f -
```

Finally, we use `linkerd check` to make sure everything is working:

```bash
linkerd check
```

## Install Kyverno

OK! Let's get Kyverno installed too. We'll use Helm for this.

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update
helm install kyverno kyverno/kyverno -n kyverno --create-namespace --wait
```

At this point, Kyverno is running, but it's not actually doing anything yet.
Before we fix that, let's get something else running for it to look at.

## Install Faces

We'll use the Faces application for this, so get that installed next. (The
`faces-values.yaml` file just turns off the errors that the Faces app normally
injects for resilience demos.)

```bash
helm install faces \
     --namespace faces --create-namespace \
     --values faces-values.yaml \
     oci://ghcr.io/buoyantio/faces-chart --version 2.0.0 \
     --wait
```

At this point, we should be able to access the Faces app via its LoadBalancer
IP address. Let's grab that:

```bash
FACES_IP=$(kubectl -n faces get svc faces-gui -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
#@immed
echo "Faces GUI: http://${FACES_IP}/"
```

We can check that everything is working by hitting the Faces GUI in a browser.

<!-- @browser_then_terminal -->

OK! Faces is running, so let's see if we can get Kyverno to do something
useful with it. To do this, we need to install some policies. We'll start with
something simple: a policy that requires all Pods outside system namespaces to
have a memory limit.

```bash
bat kyverno/require-memory-limits/require-pod-memory-limits.yaml
kubectl apply -f kyverno/require-memory-limits/require-pod-memory-limits.yaml
```

We set up that policy in audit mode, so it should generate policy reports but
not block anything. Let's see if it found any violations (this might take a
minute or two):

```bash
watch kubectl get policyreports -n faces
```

So yeah, quite a few errors! Note that we see reports for Pods, ReplicaSets,
and Deployments -- this is because when we ask for Pods, we get the things
connected to Pods as well.

Let's look at the first one:

```bash
kubectl get policyreport -n faces -o yaml | yq '.items[0]'
```

The policy report contains a lot of details about what happened, including
notes about the violations that were found.

<!-- @wait_clear -->

## Aside: Finding Specific PolicyReports

One weird bit about PolicyReports is that they have UUIDs for names, which can
make it tricky to the report for a specific resource. A given PolicyReport
will always be owned by the resource on which it's reporting, though, and it
will also always have a `scope` stanza that gives the owner too. We can use
either with `jq` to find the name of the PolicyReport for a specific resource.

Of course, for Pods that's a little weird in its own right, since they have
derived names themselves! But it's scriptable anyway -- first we use `kubectl
get` with a `jsonpath` to get the name of a Pod given a label selector:

```bash
FACE_POD_NAME=$(kubectl get pods -n faces -l faces.buoyant.io/component=face -o jsonpath='{.items[0].metadata.name}')
echo $FACE_POD_NAME
```

...and then we use `jq` to find the name of the PolicyReport for that Pod.
We'll work with the `scope` stanza here, it's a little simpler.

```bash
FACE_REPORT_NAME=$(kubectl get policyreports -n faces -o json | \
    jq -r '.items[] | select(.scope.name=="${FACE_POD_NAME}") | select(.scope.kind=="Pod") | .metadata.name')
echo $FACE_REPORT_NAME
kubectl describe policyreport -n faces ${FACE_REPORT_NAME}
```

<!-- @wait_clear -->

<!-- @SHOW -->

## Cleaning up the Situation

So. What can we do about all those violations? Well, the obvious thing is to
fix the Pods to have memory limits. Let's do that for the `face` pod, by
patching its Deployment template:

```bash
kubectl -n faces patch deploy face \
    --type='json' \
    -p='[{"op":"add", "path":"/spec/template/spec/containers/0/resources/limits", "value":{"memory":"64Mi"}}]'
kubectl rollout status -n faces deploy/face
```

It'll take a few seconds for Kyverno to notice the change:

```bash
watch kubectl get policyreports -n faces
```

Note that fixing the Deployment fixed its ReplicaSet and Pods too, which is
kind of nice... but, weirdly, note that there's still a report for the _old_
ReplicaSet. We'll come back to that.

<!-- @wait_clear -->

## Cleaning up the Situation

We could fix up the of the Deployments by hand, of course, but wouldn't it be
more fun to just get Kyverno to fix these pods for us?

```bash
bat kyverno/add-memory-limits/add-memory-limits.yaml
kubectl apply -f kyverno/add-memory-limits/add-memory-limits.yaml
```

Again, restarting our Pods is the simplest way to get Kyverno to act on our
new policy, so let's do that:

```bash
kubectl rollout restart -n faces deploy
kubectl rollout status -n faces deploy/face

watch kubectl get policyreports -n faces
```

At this point, the only failures we see should be for the old ReplicaSets.
So what's up with that?

<!-- @wait -->

As it turns out, they're still around because the old ReplicaSets are still
around!

```bash
kubectl get replicaset -n faces
```

This isn't a secret, but neither is it all that widely known: when a
Deployment creates a new ReplicaSet, it leaves the old ReplicaSet around (up
to the Deployment's `revisionHistoryLimit`, which defaults to 10). In theory
this is useful for rollbacks; in practice it's mostly just annoying, because
we have to clean up the old ReplicaSets ourselves if we want them gone.

We're not going to worry about that right now, though -- we could delete them
by hand, or we could configure Kyverno to do it for us, but in the interest of
time we'll set it aside for now.

<!-- @wait_clear -->

## Aside: `kyverno test`

We've shown a couple of policies so far, and we've shown them a couple of
levels deep in the directory structure. Here's the full set:

```bash
tree kyverno
```

The point of this is the `kyverno test` command, which is a way of checking
Kyverno policies before applying them. Let's give this a shot (we're using
`--remove-color` here to make the output a little easier to read when piped
through `more`):

```bash
kyverno test --remove-color kyverno | more
```

Everything shows us a result of `Pass`, which is what we want -- it lets us
know that these policies are likely to work when we apply them.

<!-- @wait_clear -->

## Aside: `kyverno test`

The `kyverno test` command works by recursively looking for
`kyverno-test.yaml` files. Here's the one for the `add-memory-limits` policy
that we've already applied:

```bash
bat kyverno/add-memory-limits/kyverno-test.yaml
```

The `policies` stanza tells `kyverno test` which policies to test, and the
`resources` stanza tells it which resources to test them against. In this
case, we're testing the `add-memory-limits` policy against these resources:

```bash
bat kyverno/add-memory-limits/resource.yaml
```

There are four Deployments in `reource.yaml`, for the four possible
combinations of memory requests and limits. If we look back at
`kyverno-test.yaml`, we can see that we expect two Deployments to be modified
by the policy and thus pass, and the other two to be left alone because they
need nothing, so they'll be skipped:

```bash
bat kyverno/add-memory-limits/kyverno-test.yaml
```

(We can also mark tests that are expected to fail, using `result: fail`.
You'll see that if you look at some of the other tests.)

Overall, this is a pretty powerful and flexible way to test Kyverno policies
before trying them on a live system.

<!-- @wait_clear -->

## Requiring Linkerd

Let's get back to policies, though. You might recall, back from when we
installed Faces, that we _didn't_ enable automatic Linkerd injection for the
`faces` namespace. So, in fact, Faces is not meshed right now. We can tell
because there's only one container in the Faces Pods, not two:

```bash
kubectl get pods -n faces
```

We can, of course, use a Kyverno policy to notice that as well! Let's take a
look at the `require-bel-proxy`, which requires that Pods have a running
Buoyant Enterprise for Linkerd proxy sidecar:

```bash
bat kyverno/require-bel/require-bel-proxy.yaml
```

(There's also a `require-linkerd-proxy` policy that does the same thing for
the open-source Linkerd proxy sidecar.)

Let's take advantage of `kyverno test` again to make sure that
`require-bel-proxy` looks good, since we're running Buoyant Enterprise for
Linkerd for this demo:

```bash
kyverno test --remove-color kyverno/require-bel | more
```

Looks good, so let's apply `require-bel-proxy` and see what happens!

```bash
kubectl apply -f kyverno/require-bel/require-bel-proxy.yaml
watch kubectl get policyreports -n faces
```

Suddenly we're seeing a stack of failures! Let's look at what's up for our
`face` workload Pod again:

```bash
FACE_POD_NAME=$(kubectl get pods -n faces -l faces.buoyant.io/component=face \
                        -o jsonpath='{.items[0].metadata.name}')
echo "face Pod: ${FACE_POD_NAME}"
FACE_REPORT_NAME=$(kubectl get policyreports -n faces -o json | \
    jq -r ".items[] | select(.scope.name==\"${FACE_POD_NAME}\") | select(.scope.kind==\"Pod\") | .metadata.name")
echo "face Pod report: ${FACE_REPORT_NAME}"
kubectl describe policyreport -n faces ${FACE_REPORT_NAME} | more
```

As expected, the `require-bel-proxy` policy is complaining that our Pod
doesn't have a Linkerd proxy sidecar -- which makes sense, because it doesn't.
We _could_ actually have Kyverno go and mutate things for us, but honestly,
it's simpler to just enable automatic injection for the namespace and restart
the workloads.

```bash
kubectl annotate namespace faces linkerd.io/inject=enabled --overwrite
kubectl rollout restart -n faces deploy
kubectl rollout status -n faces deploy/face

watch 'sh -c "kubectl get policyreports -n faces | grep Pod"'
```

Give that a little bit, and we should see that our Pods are showing no
failures!

<!-- @wait_clear -->
<!-- @show_terminal -->

## Summary

So there's your whirlwind tour of Kyverno keeping an eye on a Linkerd cluster!
As always, there's a lot more to Kyverno than we could cover here, but
hopefully this gives a good idea of how to get started. Remember `kyverno
test` as you get started!

<!-- @wait -->

As always, feedback is welcome! You can reach me at flynn@buoyant.io or as
@flynn on the Linkerd Slack (https://slack.linkerd.io).

<!-- @wait -->
<!-- @show_slides -->
