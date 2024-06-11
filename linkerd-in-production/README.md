<!--
SPDX-FileCopyrightText: 2024 Buoyant Inc.
SPDX-License-Identifier: Apache-2.0

SMA-Description: Installing and using Linkerd in a production environment
-->

# Linkerd in Production

This is the documentation - and executable code! - for the Service Mesh
Academy "Linkerd in Production" workshop. The easiest way to use this file is
to execute it with [demosh].

Things in Markdown comments are safe to ignore when reading this later. When
executing this with [demosh], things after the horizontal rule below (which is
just before a commented `@SHOW` directive) will get displayed.

[demosh]: https://github.com/BuoyantIO/demosh

This workshop requires that you have a running Kubernetes cluster _with at
least three Nodes_. This demo assumes that you're using a [Civo] cluster for
this, but pretty much any cloud provider should work as long as your cluster
has at least three Nodes. This demo also assumes that your cluster is called
`sma` – if you named it something else, you can either substitute its name for
`sma` in the commands below, or use `kubectl config rename-context` to rename
your cluster's context to match.

[Civo]: https://civo.io/

<!-- @import demosh/demo-tools.sh -->
<!-- @import demosh/check-requirements.sh -->
<!-- @start_livecast -->
---
<!-- @SHOW -->

# Install `cert-manager`

Start by installing `cert-manager`.

```bash
helm repo add jetstack https://charts.jetstack.io --force-update
helm repo update

helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true \
  --wait
```

Now we have `cert-manager` running in our cluster, ready to manage
certificates for us.

<!-- @wait_clear -->

# Non-Production: In-Cluster Trust Anchor

**This is not what you really want to do in production. This one bit is still
just a demo.**

In real-world production, you really don't want to ever have the trust
anchor's private key present in your cluster at all: instead, you want to let
`cert-manager` hand off a CSR to your off-cluster CA and get a signed
certificate. `cert-manager` supports several different mechanisms here,
including Vault, Venafi, etc.

All of those mechanisms are very much out of scope for this SMA, so we're
going to load the trust anchor's private key into the cluster. **Again, don't
do this in the real world.**

```bash
bash non-prod-trust-anchor.sh
```

At this point, we have a TLS Secret for our trust anchor certificate:

```bash
kubectl get secret -n linkerd linkerd-trust-anchor
```

We also have a `cert-manager` Issuer called `linkerd-trust-anchor` that will
issue certs signed by the `linkerd-trust-anchor` Secret.

```bash
kubectl get issuer -n linkerd -o yaml linkerd-trust-anchor | bat -l yaml
```

<!-- @wait_clear -->

# Using `cert-manager` for the identity issuer

Next, we tell `cert-manager` how to use our `linkerd-trust-anchor` Issuer to
create identity issuer certificates. This **is** how you'll do things in
production -- you'd define the `linkerd-trust-anchor` Issuer differently, but
you'd use it the same way.

```bash
bat cert-manager.yaml
kubectl apply -f cert-manager.yaml
```

We should now see the identity issuer certificate ready to go:

```bash
#@immed
rm -rf linkerd-control-plane

kubectl get certificate -n linkerd
kubectl get secret -n linkerd linkerd-identity-issuer
```

<!-- @wait_clear -->

# Installing Linkerd

We're going to use Helm to install Linkerd in HA mode. We'll start by grabbing
the Helm chart so we can take a look at `values-ha.yaml`:

```bash
helm fetch --untar linkerd/linkerd-control-plane
bat linkerd-control-plane/values-ha.yaml
```

Given `values-ha.yaml`, we can install Linkerd with Helm. First up, install
the CRDs.

```bash
helm install linkerd-crds -n linkerd linkerd/linkerd-crds
```

Next up, install the Linkerd control plane. Note the `-f` parameter including
`values-ha.yaml`, so that we install in HA mode.

Also note that we're passing the public half of the trust anchor to Helm, so
it can update the trust anchor bundle that Linkerd uses for workload identity
verification. This is also something that may need to change when you're using
a proper off-cluster CA.

```bash
helm install linkerd-control-plane -n linkerd \
  --set-file identityTrustAnchorsPEM=./ca.crt \
  --set identity.issuer.scheme=kubernetes.io/tls \
  -f linkerd-control-plane/values-ha.yaml \
  linkerd/linkerd-control-plane
```

Once Helm says we're good, let's make sure everything is really on the level:

```bash
linkerd check
```

We can also take a look to verify that we really do have multiple Nodes and
multiple control plane replicas:

```bash
kubectl get nodes
kubectl get pods -n linkerd
```

And, if we're paranoid, we can verify that no two replicas for a single
Deployment share the same Node:

```bash
kubectl get pod -n linkerd -o go-template='{{ range .items }}{{ .metadata.name}}: {{ .spec.nodeName }}{{"\n"}}{{end}}'
```

<!-- @wait_clear -->

# Linkerd is installed. Now what?

Well... Linkerd is installed in HA mode, cert-manager is handling rotating the
identity issuer every 48 hours... as far as installing Linkerd in a
production-ready way, this really is pretty much all there is to it.

Next steps would be installing your application, setting up policy, etc.
Policy is out of scope for this, but let's go ahead and install emojivoto to
show a touch of debugging with. There's nothing dramatic here: we're just
doing a straightforward install using auto-injection.

```bash
kubectl create ns emojivoto
kubectl annotate ns emojivoto linkerd.io/inject=enabled
kubectl apply -f https://run.linkerd.io/emojivoto.yml
kubectl wait pod --for=condition=ready -n emojivoto --all
```

<!-- @wait_clear -->

# Basic debugging: events

At the most basic level, Linkerd is just another Kubernetes workload, so the
place to start with getting a sense of what's up is with events:

```bash
kubectl get event -n emojivoto --sort-by="{.lastTimestamp}" | tail -20
```

We'll probably see `IssuedLeafCertificate` events above -- these get posted
when Linkerd issues workload identity certificates, so if they're missing,
it's a problem. Let's make sure we see those:

```bash
kubectl get event -n emojivoto --field-selector reason=IssuedLeafCertificate
```

We should see four, one for each relevant ServiceAccount.

<!-- @wait_clear -->

# Basic debugging: logs

The logs can also be useful. Let's take a quick look at the logs for the
Linkerd `identity` workload, `linkerd-identity`.

```bash
IDPOD=$(kubectl get pods -n linkerd -l 'linkerd.io/control-plane-component=identity' -o jsonpath='{ .items[0].metadata.name }')
#@print "# Found identity pod ${IDPOD}"

kubectl logs -n linkerd ${IDPOD} | head -10
```

`linkerd-identity` is responsible for managing workload identity, so it makes
sense that we see things about identities in its logs -- but note that it
mentioned other containers, too. Checking those quickly...

```bash
kubectl logs -n linkerd ${IDPOD} -c linkerd-proxy | head -10
```

The `linkerd-proxy` container deals with... proxying things. You may see
transient errors here (Kubernetes is only eventually consistent, after all),
but persistent errors can point to real problems.

```bash
kubectl logs -n linkerd ${IDPOD} -c linkerd-init | head -10
```

The `linkerd-init` container deals with network configuration at startup --
and a special note here is that this can be very different if you're using the
Linkerd CNI plugin! We're not, though, so here we see the init container
messing with kernel routing on our behalf.

<!-- @wait_clear -->

# Basic debugging: logs

One last note: let's take a look at the logs for one of our emojivoto
containers.

```bash
EMOJIPOD=$(kubectl get pods -n emojivoto -l 'app=emoji-svc' -o jsonpath='{ .items[0].metadata.name }')
#@print "# Found emoji-svc pod ${EMOJIPOD}"

kubectl logs -n emojivoto ${EMOJIPOD} | head -10
```

Note that, by default, we get the `linkerd-proxy` container. Although it's
nice to see what identities it's using, this may well not be what you're
interested in -- it's worth remembering that you may well need to be explicit
about the container you want:

```bash
kubectl logs -n emojivoto ${EMOJIPOD} -c emoji-svc | head -10
```

<!-- @wait_clear -->

# More advanced debugging

We'll take a quick look at two other debugging tools: the `linkerd
identity` and `linkerd diagnostic` commands.

`linkerd identity` is a bit simpler, so let's take a look at it first. Its
purpose in life is to show you what identity Linkerd is using for a given
workload. For example, we can look at the identity in use for the `emoji-svc`
workload -- the output is a dump of the workload's identity certificate:

```bash
linkerd identity -n emojivoto -l app=emoji-svc | more
```

There's a lot of detail there, so it can be instructive just to zoom in on the
human-readable parts:

```bash
linkerd identity -n emojivoto -l app=emoji-svc | grep CN=
```

which shows us that the `emoji-svc` uses an identity named
`emoji.emojivoto.serviceaccount.identity.linkerd.cluster.local`, issued by
`identity.linkerd.cluster.local` (AKA the Linkerd identity issuer).

<!-- @wait_clear -->

# More advanced debugging: `linkerd identity`

An aside: the control plane components have identities too! For example:

```bash
linkerd identity -n linkerd -l linkerd.io/control-plane-component=identity \
    | grep CN=
```

We see multiple outputs because there are multiple replicas for this workload,
but we can clearly see that the `linkerd-identity` controller has its own
identity (and that this identity is the same across all the replicas).

<!-- @wait_clear -->

# More advanced debugging: `linkerd diagnostics`

`linkerd diagnostics` has a few powerful functions:

- `linkerd diagnostics proxy-metrics` will fetch low-level metrics directly
  from Linkerd proxies.
- `linkerd diagnostics controller-metrics` does the same, but from control
  plane components.
- `linkerd diagnostics endpoints` will show you what endpoints Linkerd
  believes are alive for a given destination.
- `linkerd diagnostics policy` will show you about active 2.13 policy.

These tend to be very, very verbose: get used to using `grep`.

<!-- @wait_clear -->

# `linkerd diagnostics endpoints`

Let's start with a simple one: what endpoints are active for the `emoji-svc`?

```bash
linkerd diagnostics endpoints emoji-svc.emojivoto.svc.cluster.local:8080
```

This shows us a single active endpoint. Note that you use the fully-qualified
DNS name of the Service, plus the port you're interested in.

- **Only active endpoints** will be shown: if, for example, one replica is
  being fastfailed, it will not appear in this list.

- **Policy is not taken into account** here: if, for example, you're using an
  HTTPRoute to divert all the traffic going to a given Service, the active
  endpoints listed here won't change.

<!-- @wait_clear -->

# `linkerd diagnostics proxy-metrics`

We'll take a quick look at proxy-metrics too:

```bash
linkerd diagnostics proxy-metrics po/${EMOJIPOD} -n emojivoto | more
```

This is... basically a firehose. There are a _lot_ of metrics. The great win
about the `linkerd diagnostics proxy-metrics` is that it gives you a way to
check metrics _even if your metrics aggregator isn't working_. For example, if
you're trying to set up your own Prometheus and you don't see any metrics,
this is the single best way to cross-check what's going on.

<!-- @wait_clear -->

# Other `linkerd diagnostics` commands

We're not going to show `linkerd diagnostics controller-metrics` because it's
pretty much like `proxy-metrics`, and we're not going to show `linkerd
diagnostics policy` here because it's covered in the SMA on Linkerd 2.13+
circuit breaking and dynamic routing (at
https://buoyant.io/service-mesh-academy/circuit-breaking-and-dynamic-routing-deep-dive).

So that's a wrap on our quick dive into production Linkerd -- thanks!

<!-- @wait -->
<!-- @show_browser -->
