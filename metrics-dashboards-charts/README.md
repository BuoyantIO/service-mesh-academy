<!--
SPDX-FileCopyrightText: 2024 Buoyant Inc.
SPDX-License-Identifier: Apache-2.0

SMA-Description: Metrics and Dashboards and Charts, Oh My!
-->

# SMA: Metrics and Dashboards and Charts, Oh My!

This is the documentation - and executable code! - for "Metrics and Dashboards
and Charts, oh my!" The easiest way to use this file is to execute it with
[`demosh`].

Things in Markdown comments are safe to ignore when reading this later. When
executing this with [`demosh`], things after the horizontal rule below (which
is just before a commented `@SHOW` directive) will get displayed.

[`demosh`]: https://github.com/BuoyantIO/demosh
[`linkerd`]: https://linkerd.io/2/getting-started/
[`step`]: https://smallstep.com/docs/step-cli/installation
[`helm`]: https://helm.sh/docs/intro/install/

<!-- set -e -->

Make sure that the cluster exists and has Linkerd, Faces, Emissary, and
Emojivoto installed.

```bash
BAT_STYLE="grid,numbers"
title "Lesson 3.4"

set -e

if [ $(kubectl get ns | grep -c linkerd) -eq 0 ]; then \
    echo "Linkerd is not installed in the cluster" >&2; \
    exit 1 ;\
fi

if [ $(kubectl get ns | grep -c faces) -eq 0 ]; then \
    echo "Faces is not installed in the cluster" >&2; \
    exit 1 ;\
fi

if [ $(kubectl get ns | grep -c emissary) -eq 0 ]; then \
    echo "Emissary is not installed in the cluster" >&2; \
    exit 1 ;\
fi

if [ $(kubectl get ns | grep -c emojivoto) -eq 0 ]; then \
    echo "Emojivoto is not installed in the cluster" >&2; \
    exit 1 ;\
fi
```

Then it's off to the real work.

```bash
#@start_livecast
```

----
<!-- @SHOW -->

## Metrics and Dashboards and Charts, Oh My!

We're starting out with our cluster already set up with

- Linkerd
- Grafana
- Linkerd Viz (pointing to our Grafana)
- Faces (using Emissary)
- Emojivoto

(If you need to set up your cluster, RESET.sh can do it for you!)

<!-- @wait -->

All these things are meshed, and we have some Routes installed too:

```bash
kubectl get httproute.gateway.networking.k8s.io -A
kubectl get grpcroute.gateway.networking.k8s.io -A
```

<!-- @wait_clear -->

Let's start by looking at the metrics stored in the control plane:

```bash
linkerd diagnostics controller-metrics | more
```

So that already looks kinda like a mess! Let's check out what the proxy stores
for us. For this we need to specify which proxy, so we'll tell it to look at
some Pod in the `face` Deployment in the `faces` namespace:

```bash
linkerd diagnostics proxy-metrics -n faces deploy/face | more
```

This seems like it just goes on forever! Let's try to make a bit more sense of
this with `promtool`. We'll start with a brutal hack to get a port-forward
running so that we can talk to Prometheus:

```bash
kubectl port-forward -n linkerd-viz svc/prometheus 9090:9090 &
```

Now we can use `promtool` to check the metrics. We'll ask it to pull all the
time series it can find with a `namespace="faces"` label as a representative
sample:

```bash
promtool query series http://localhost:9090 \
         --match '{namespace="faces"}' \
    | more
```

That's still a massive amount, but suppose we pare down that output to just
the names of the metrics?

```bash
promtool query series http://localhost:9090 \
         --match '{namespace="faces"}' \
    | sed -e 's/^.*__name__="\([^"][^"]*\)".*$/\1/' | sort -u | more
```

That's somewhat more manageable, and it actually gives us a place to stand for
talking about the metrics in broad classes.

<!-- @slides_then_terminal -->

OK, that was a lot. So how can we actually use this stuff?

Remember: you're going to start by figuring out what information you need,
then tailoring everything to that.

For this demo, we'll look at HTTP retries -- that's interesting and it's new
to Linkerd 2.16, so that should be fun.

<!-- @wait -->

The most basic retry info is the `outbound_http_route_retry_requests_total`
metric: that's a counter of total retries, and it has a bunch of labels that
we can use to slice and dice the data. We only need four of them, though:

- `deployment` and `namespace` identify the source of the request
- `parent_name` and `parent_namespace` identify the destination
   - (in Gateway API for service mesh, the `parent` is always the Service to
     which the request is being sent)

<!-- @wait -->

So let's start by trying to get a sense for how many retries are going from
Emissary, by using `curl` to run raw queries against our Prometheus.
Specifically we'll first do an 'instantaneous' query, which will return only
values for a single moment, and we'll just filter to the `emissary` namespace
and deployment. The query here is actually

```
outbound_http_route_retry_requests_total{
    namespace="emissary", deployment="emissary"
}
```

just all on one line.

<!-- @wait -->

```bash
curl -G http://localhost:9090/api/v1/query \
     --data-urlencode 'query=outbound_http_route_retry_requests_total{namespace="emissary", deployment="emissary"}' \
     | jq | bat -l json
```

<!-- @clear -->

There are a lot of labels in there, and they're kind of getting in our way. We
can use the `sum` function to get rid of most of them -- let's keep just
`parent_name` and `parent_namespace`:

```
sum by (parent_name, parent_namespace) (
    outbound_http_route_retry_requests_total{
        namespace="emissary", deployment="emissary"
    }
)
```

```bash
curl -G http://localhost:9090/api/v1/query \
     --data-urlencode 'query=sum by (parent_name, parent_namespace) (outbound_http_route_retry_requests_total{namespace="emissary", deployment="emissary"})' \
     | jq | bat -l json
```

<!-- @clear -->

MUCH better. From this, we can see that the `emissary` deployment is retrying
things only to `face` in the `faces` namespace, so let's add more labels to
focus on that:

```
sum by (parent_name, parent_namespace) (
    outbound_http_route_retry_requests_total{
        namespace="emissary", deployment="emissary",
        parent_name="face", parent_namespace="faces"
    }
)
```

```bash
curl -G http://localhost:9090/api/v1/query \
     --data-urlencode 'query=sum by (parent_name, parent_namespace) (outbound_http_route_retry_requests_total{namespace="emissary", deployment="emissary",parent_name="face", parent_namespace="faces"})' \
     | jq | bat -l json
```

<!-- @wait_clear -->

Now let's turn that into a rate, instead of an instantaneous count, using the `rate` function to get a rate calculated over a one-minute window:

```
sum by (parent_name, parent_namespace) (
    rate(
        outbound_http_route_retry_requests_total{
            namespace="emissary", deployment="emissary",
            parent_name="face", parent_namespace="faces"
        }[1m]
    )
)
```

```bash
curl -G http://localhost:9090/api/v1/query \
     --data-urlencode 'query=sum by (parent_name, parent_namespace) (rate(outbound_http_route_retry_requests_total{namespace="emissary", deployment="emissary",parent_name="face", parent_namespace="faces"}[1m]))' \
     | jq | bat -l json
```

<!-- @wait_clear -->

Finally, we can ask for a time series of that rate by adding a range to the
whole query. In this case we use `[5m:1m]` to get five minutes of rates,
spaced one minute apart:

```
sum by (parent_name, parent_namespace) (
    rate(
        outbound_http_route_retry_requests_total{
            namespace="emissary", deployment="emissary",
            parent_name="face", parent_namespace="faces"
        }[1m]
    )
)[5m:1m]
```

```bash
curl -G http://localhost:9090/api/v1/query \
     --data-urlencode 'query=sum by (parent_name, parent_namespace) (rate(outbound_http_route_retry_requests_total{namespace="emissary", deployment="emissary",parent_name="face", parent_namespace="faces"}[1m]))[5m:1m]' \
     | jq | bat -l json
```

<!-- @clear -->

This is the basis of anything we want to do. Let's finish this by flipping
over to Grafana and building this into the dashboard... which we'll do
basically the exact same way.

<!-- @browser_then_terminal -->

## One More Thing!

Remember I said that there's nothing special about Viz, it's just a Prometheus
client? Just to prove that, in our directory here is a Python program called
`promq.py` that displays a running breakdown of some of the gRPC metrics for
Emojivoto, without doing any math itself -- it's all just Prometheus queries.

(`promq.py` also deliberately does everything the hard way instead of using
the Python Prometheus client package.)


```bash
#@immed
set +e
python promq.py
```

We're not going to over the code in detail, but it's worth looking quickly at
the queries it's running.

```bash
bat promq.py
```

<!-- @wait_clear -->

## Summary

There's a lot of useful information in the metrics, and even though they look
complex, they're actually pretty easy to work with. The key is to start with
what you want to know, and then build up from there.

<!-- @wait -->

Finally, feedback is always welcome! You can reach me at flynn@buoyant.io or
as @flynn on the Linkerd Slack (https://slack.linkerd.io).

<!-- @wait -->
<!-- @show_slides -->
