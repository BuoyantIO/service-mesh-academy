<!--
SPDX-FileCopyrightText: 2024 Buoyant Inc.
SPDX-License-Identifier: Apache-2.0

SMA-Description: Kyverno 101 and Linkerd
-->

# Cleaning up the ReplicaSets

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

# Cleaning up the ReplicaSets

Remember those old PolicyReports? They're still around because the old
ReplicaSets are still around!

```bash
kubectl get replicaset -n faces
```

This isn't a secret, but neither is it all that widely known: when a
Deployment creates a new ReplicaSet, it leaves the old ReplicaSet around (up
to the Deployment's `revisionHistoryLimit`, which defaults to 10). In theory
this is useful for rollbacks; in practice it's mostly just annoying, because
we have to clean up the old ReplicaSets ourselves if we want them gone...

Happily, Kyverno can do that for us too! We can use a `ClusterCleanupPolicy`
for this:

```bash
bat kyverno/cleanup-old-replicasets/cleanup-old-replicasets.yaml
```

Unfortunately, `kyverno test` doesn't work with `ClusterCleanupPolicy` yet, so
we can't test it beforehand -- we'll just have to apply it and hope for the
best! Since we have it set up to run every minute, we should be able to see
changes pretty quickly:

```bash
kubectl apply -f kyverno/cleanup-old-replicasets/cleanup-old-replicasets.yaml
```

Oops. First we have to wrestle RBAC. Looking in the Kyverno docs at
https://kyverno.io/docs/installation/customization/#role-based-access-controls,
we can see that Kyverno is using an aggregated ClusterRole for its cleanup
controllers, so we should be able to fix this by adding an additional
ClusterRole resource. First, let's confirm that the cleanup controller's
account cannot do what we want:

```bash
kubectl auth can-i delete replicaset \
             --as system:serviceaccount:kyverno:kyverno-cleanup-controller
```

Nope, it can't. Let's fix that:

```bash
bat cleanup-replicaset-rbac.yaml
kubectl apply -f cleanup-replicaset-rbac.yaml
kubectl auth can-i delete replicaset \
             --as system:serviceaccount:kyverno:kyverno-cleanup-controller
```

OK, let's try that cleanup policy again:

```bash
kubectl apply -f kyverno/cleanup-empty-replicasets/cleanup-empty-replicasets.yaml
```

There we go! Let's see what happens.

```bash
watch kubectl get replicaset -n faces
```
