<!--
SPDX-FileCopyrightText: 2022-2024 Buoyant Inc.
SPDX-License-Identifier: Apache-2.0
-->

# Gateway API 101: Chihiro's stuff

This file has the documentation - and executable code! - for Chihiro's role in
the Gateway API 101 Service Mesh Academy. The easiest way to use this file is
to execute it with [demosh].

Things in Markdown comments are safe to ignore when reading this later. When
executing this with [demosh], things after the horizontal rule below (which
is just before a commented `@SHOW` directive) will get displayed.

[demosh]: https://github.com/BuoyantIO/demosh

---
<!-- @clear -->
<!-- @show_terminal -->
<!-- @SHOW -->

# Gateway API 101: Chihiro's stuff

Chihiro is our _cluster operator_. They'll get a cluster from Ian - in our
case, this is a fully-managed cluster with Linkerd and a Gateway controller -
and it's Chihiro's job to set up a Gateway for Ana to use. So let's start by
finding out what GatewayClass(es) we have available:

```bash
kubectl get gatewayclasses
```

Just the one, named `ingress-gateway-class`, so that's the one we'll use.
Let's go ahead and create the Gateway that Ana should be using.

```bash
bat chihiro/gateway.yaml
kubectl apply -f chihiro/gateway.yaml
```

Now we wait for the Gateway to have an IP address...

```bash
while true; do \
    date ;\
    PROGRAMMED=$( \
        kubectl get gateway ingress -o json \
            | jq -r '.status.listeners[0].conditions[] | select(.type == "Programmed") | .status' \
    ) ;\
    if [ "$PROGRAMMED" = "True" ]; then \
        IPADDR=$(kubectl get gateway ingress -o jsonpath='{.status.addresses[0].value}') ;\
        echo "Programmed: IP address is $IPADDR" ;\
        if [ -n "$IPADDR" ]; then \
            break ;\
        fi ;\
    else \
        echo "Not programmed yet" ;\
    fi ;\
    kubectl get gateway ;\
    sleep 5 ;\
done
#@immed
GATEWAYADDR=$(kubectl get gateway ingress -o jsonpath='{.status.addresses[0].value}')
```

So we have a Gateway at ${GATEWAYADDR}!

```bash
kubectl get gateway ingress
```

And with that our job is done and we can hand off to Ana!

<!-- @wait -->
