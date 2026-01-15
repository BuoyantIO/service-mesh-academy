<!--
SPDX-FileCopyrightText: 2026 Buoyant Inc.
SPDX-License-Identifier: Apache-2.0

SMA-Description: Installing and using Linkerd in a production environment
-->

# Linkerd Production Readiness

This is the documentation - and executable code! - for the Service Mesh
Academy "Linkerd Production Readiness" workshop. The easiest way to use this file is
to execute it with [demosh].

Things in Markdown comments are safe to ignore when reading this later. When
executing this with [demosh], things after the horizontal rule below (which is
just before a commented `@SHOW` directive) will get displayed.

[demosh]: https://github.com/BuoyantIO/demosh

Run `./create.sh` to setup the k3d demo environment.

<!-- @import demosh/demo-tools.sh -->
<!-- @import demosh/check-requirements.sh -->
<!-- @start_livecast -->
---
<!-- @SHOW -->

This is a short, executable demo for Service Mesh Academy showing:

- A multi-node Kubernetes cluster
- Linkerd Enterprise running in HA mode
- A full observability stack (metrics, logs, traces)
- A simple demo application using Gateway API

This file is intended to be run with demosh.

<!-- @SHOW -->

# Verify the cluster

This demo uses a local Kubernetes cluster with more than three nodes.

```bash
kubectl get nodes
```

We should see multiple nodes available for scheduling.

<!-- @wait_clear -->

# Verify Linkerd is installed and healthy

```bash
linkerd check
```

<!-- @wait_clear -->

# Linkerd control plane (HA)

```bash
kubectl get deployments -n linkerd
```

<!-- @wait_clear -->

# Control plane spread across nodes

```bash
kubectl get pods -n linkerd -o wide
```

<!-- @wait_clear -->

# Observability stack

```bash
kubectl get pods -n monitoring
```

<!-- @wait_clear -->

# Helm values used for observability

<!-- @SHOW -->

# Loki Values

This is the Observability Loki values file used for this demo.

```bash
less linkerd-loki-values.yaml
```

<!-- @wait_clear -->

# Alloy Values

```bash
less linkerd-alloy-values.yaml
```

<!-- @wait_clear -->

# Linkerd o11y stack values

<!-- @notypeout -->


```bash
less linkerd-o11y-stack.yaml
```

<!-- @wait_clear -->

# Demo application: Faces

```bash
kubectl get pods -n faces
```

<!-- @wait_clear -->

# Grafana

Open http://localhost:3000

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
```

<!-- @wait_clear -->

# Summary

- Multi-node cluster
- Linkerd Enterprise in HA
- External CA identity
- Full observability stack
- Faces demo with Gateway API

<!-- @wait -->
