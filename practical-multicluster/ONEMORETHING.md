<!--
SPDX-FileCopyrightText: 2024 Buoyant Inc.
SPDX-License-Identifier: Apache-2.0
-->

# One More Thing

This is the documentation - and executable code! - for one more thing in the
Practical Multicluster Service Mesh Academy workshop. The easiest way to use
this file is to execute it with [demosh].

Things in Markdown comments are safe to ignore when reading this later. When
executing this with [demosh], things after the horizontal rule below (which
is just before a commented `@SHOW` directive) will get displayed.

[demosh]: https://github.com/BuoyantIO/demosh

This workshop requires kind _and_ k3d, and assumes that you can run a lot of
clusters at once.

<!-- @import demosh/check-requirements.sh -->
<!-- @start_livecast -->
---
<!-- @SHOW -->

# One More Thing

We used k3d and kind to simulate different cloud providers... but in fact we
can live a little more dangerously than that. Let's do a canary between my
laptop and an actual cloud cluster.

<!-- @wait -->

I've created a Civo cluster with Linkerd and Faces installed.

```bash
kubectl --context civo-faces cluster-info
kubectl --context civo-faces get ns
```

So let's link _that_ to our `cdn` cluster. **Note**: this will only work in
one direction! Since the `cdn` cluster on my laptop can reach the `civo-faces`
cluster, linking that direction will work -- but the `civo-faces` cluster
can't reach the `cdn` cluster on my laptop, so we wouldn't be able to link the
other direction. This is fine for our purposes though.

```bash
linkerd --context civo-faces multicluster link --cluster-name civo-faces \
    | kubectl --context cdn apply -f -
```

Once that's done, just like before, we can mirror the `faces-gui` Service from
the `civo-faces` cluster into the `cdn` cluster.

```bash
kubectl --context civo-faces label -n faces \
    svc/faces-gui mirror.linkerd.io/exported=true
linkerd --context civo-faces multicluster check
linkerd --context cdn multicluster check
kubectl --context cdn get svc -n faces
```

And then we can create our usual canary TCPMapping in the `cdn` cluster to
send traffic to the `civo-faces` cluster.

<!-- @show_5 -->

```bash
bat clusters/civo-faces/tcpmapping.yaml
kubectl --context cdn apply -f clusters/civo-faces/tcpmapping.yaml
```

We'll just go ahead and delete the original TCPMapping, back to the `faces-dr`
cluster, rather than doing this politely.

```bash
kubectl --context cdn delete -n faces tcpmapping faces-dr-mapping
```

<!-- @wait_clear -->
<!-- @show_2 -->

## Summary

And there you have it... cross-cloud migration using an actual cloud cluster!
Looks remarkably like doing in all inside the laptop, doesn't it? This is the
whole point of Linkerd's gateway-based multicluster: permit amazing things
without relying on any particular network topology. And, again, once you have
multicluster you have all kinds of amazing things.

<!-- @wait -->

Finally, feedback is always welcome! You can reach me at flynn@buoyant.io or
as @flynn on the Linkerd Slack (https://slack.linkerd.io).

<!-- @wait -->
<!-- @show_slides -->
