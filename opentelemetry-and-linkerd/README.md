<!--
SPDX-FileCopyrightText: 2024 Buoyant Inc.
SPDX-License-Identifier: Apache-2.0

SMA-Description: OpenTelemetry and Linkerd with Dash0
-->

# OpenTelemetry and Linkerd with Dash0

This is the documentation - and executable code! - for the Service Mesh
Academy workshop about OpenTelemetry and Linkerd. The easiest way to use this
file is to execute it with [demosh].

Things in Markdown comments are safe to ignore when reading this later. When
executing this with [demosh], things after the horizontal rule below (which is
just before a commented `@SHOW` directive) will get displayed.

[demosh]: https://github.com/BuoyantIO/demosh

You'll need to start this workshop with an EMPTY Kubernetes cluster, and
you'll need $DASH0_AUTH_TOKEN set to your Dash0 authorization token. When you
use `demosh` to run this file, requirements will be checked for you.

<!-- set -e >
<!-- @import demosh/check-requirements.sh -->

<!-- @start_livecast -->

---

<!-- @SHOW -->

# OpenTelemetry and Linkerd with Dash0

In this workshop, we're going to take a look at how get Linkerd playing nicely
with OpenTelemetry, using Dash0 (<https://www.dash0.com/>) to show off what
OpenTelemetry brings you. If you don't already have a Dash0 account, head on
over and get set up with one - it's free! - and then come back here.

When you do that, make sure to set up your environment with `DASH0_AUTH_TOKEN`
and `DASH0_OTLP_ENDPOINT` containing the token and the endpoint for the Dash0
API. You can find these on the Settings page of the Dash0 dashboard.

<!-- @wait_clear -->

## Installing Linkerd

We'll start by firing up Linkerd in our cluster. This is a pretty typical CLI
installation based on the Linkerd installation instructions at

<https://linkerd.io/2/getting-started>

We'll be using an edge release of Linkerd for this workshop - you need at
least edge-25.1.3 - but stable releases after that will work fine too.

```bash
curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install-edge | sh
linkerd version --short --client
linkerd check --pre
linkerd install --crds | kubectl apply -f -
linkerd install ${LINKERD_EXTRA_INSTALL_FLAGS} | kubectl apply -f -
linkerd viz install | kubectl apply -f -
linkerd check
```

So that's Linkerd running! Next up, let's get the OpenTelemetry demo app,
`otel-demo`, running.

<!-- @wait_clear -->

## Installing the demo app

The `otel-demo` app is a microservices application that's heavily instrumented
for OpenTelemetry. It'll typically be installed from its Helm chart at

<https://open-telemetry.github.io/opentelemetry-helm-charts>

but we're cheating a bit: we used `helm template` to fetch the YAML, and we've
added the `config.linkerd.io/trace-collector-name` annotation to the Pods
created by the chart, for example:

```bash
yq 'select(.kind == "Deployment")' < otel-demo/otel-demo.yaml \
    | yq 'select(di==1)' \
    | bat -l yaml
```

This annotation tells Linkerd which service name the proxy for this Pod should
use when sending traces to OpenTelemetry, so that you can tell which proxy is
which in when reading the traces! (And we know this is clumsy at the moment --
we're working on that.)

<!-- @wait -->

So! We start by creating a namespace for `otel-demo` and annotating it for
Linkerd injection...

```bash
kubectl create ns otel-demo
kubectl annotate ns otel-demo linkerd.io/inject=enabled
```

The `otel-demo` app also needs to use an auth token to send traces to Dash0,
and it needs to know the OTLP endpoint for Dash0. We'll get those from the
`DASH0_AUTH_TOKEN` and `DASH0_OTLP_ENDPOINT` environment variables, and
substitute them into the correct places as we apply the `otel-demo` YAML:

```bash
sed -e "s/DASH0_AUTH_TOKEN/$DASH0_AUTH_TOKEN/" \
    -e "s/DASH0_OTLP_ENDPOINT/$DASH0_OTLP_ENDPOINT/" \
        < otel-demo/otel-demo.yaml \
        | kubectl apply -n otel-demo -f -

watch kubectl get pods -n otel-demo
```

<!-- @clear -->

At this point, we can flip over and take a look at the `otel-demo` app in the
Dash0 dashboard!

<!-- @wait_clear -->

## Adding the Jaeger extension

So that's well and good, but we have no Linkerd information in the traces.
Let's fix that.

The Linkerd proxy can add its own spans to any OpenTelemetry traces that are
present in the requests coming through the proxy, but this only happens if
we've also told the proxy to send those spans to some OpenTelemetry collector.
At present, the horribly-misnamed Linkerd Jaeger extension is the simplest way
to do this... but be careful!

If you just install the Jaeger extension, it will install various components
that we really don't want. The _only_ thing we want it to do is to tell
Linkerd's proxies to send traces to an OpenTelemetry collector (in this case,
the one supplied by the `otel-demo` application). We'll use a custom values
file for that:

```bash
bat jaeger-linkerd.yaml
```

Given that, installing the extension is simple:

```bash
linkerd jaeger install --values ./jaeger-linkerd.yaml | kubectl apply -f -
linkerd jaeger check
```

But if we go back to the Dash0 dashboard now, we still won't see any Linkerd
information. That's because the Linkerd proxies are still running with the old
configuration.

<!-- @wait_clear -->

## Rolling out linkerd proxies across the demo application

To get the proxies to pick up their shiny new OTel configuration, we need to
restart them. We can do this with a simple `kubectl rollout restart` command:

```bash
kubectl rollout restart -n otel-demo deploy,statefulset
```

Now we'll wait for that to finish...

```bash
watch kubectl get pods -n otel-demo
```

and _now_ we should see Linkerd trace information in the Dash0 dashboard!

<!-- @wait_clear -->
<!-- @show_slides -->
