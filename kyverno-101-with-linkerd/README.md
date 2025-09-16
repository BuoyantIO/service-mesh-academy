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

You'll also need the Kyverno CLI,

<!-- @import demosh/check-requirements.sh -->
<!-- @start_livecast -->
---
<!-- @SKIP -->

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
helm install kyverno kyverno/kyverno -n kyverno --create-namespace
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
bat require-memory-limits.yaml
kubectl apply -f require-memory-limits.yaml
```

We set up that policy in audit mode, so it should generate policy reports but
not block anything. Let's see if it found any violations:

```bash
kubectl get policyreports -n faces
```

Yeah, quite a few! Let's look at the first one:

```bash
kubectl get policyreport -n faces -o yaml | yq '.items[0]'
```

The policy report contains a lot of details about what happened, including
notes about the violations that were found.

<!-- @wait_clear -->

## Aside: Finding Specific PolicyReports

One weird bit about PolicyReports is that they have UUIDs for names, which
makes it a bit weird to find them if you want to look at the report for a
specific resource. A given PolicyReport will always be owned by the resource
on which it's reporting, though, and it will also always have a `scope` stanza
that gives the owner too. We can use either with `jq` to find the name of the
PolicyReport for a specific resource.

Of course, for Pods that's a little weird in its own right, since they have
derived names themselves! But it's scriptable anyway:

```bash
FACE_POD_NAME=$(kubectl get pods -n faces -l faces.buoyant.io/component=face -o jsonpath='{.items[0].metadata.name}')
echo $FACE_POD_NAME
```

Given the Pod name, we can then use `jq` to find the name of the PolicyReport
for that Pod. We'll work with the `scope` stanza here, it's a little simpler.

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
kind of nice.

We could do the rest by hand, of course, but wouldn't it be more fun to just
get Kyverno to fix these pods for us?

```bash
bat add-memory-limits.yaml
kubectl apply -f add-memory-limits.yaml
```

Let's see what happens now:

```bash
watch kubectl get policyreports -n faces
```
