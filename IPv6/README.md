<!--
SPDX-FileCopyrightText: 2024 Buoyant Inc.
SPDX-License-Identifier: Apache-2.0

SMA-Description: Using Linkerd in IPv6 and dualstack Kubernetes clusters
-->

# Linkerd and IPv6

This is the documentation - and executable code! - for the Service Mesh
Academy workshop about Linkerd and IPv6. The easiest way to use this file is
to execute it with [demosh].

Things in Markdown comments are safe to ignore when reading this later. When
executing this with [demosh], things after the horizontal rule below (which
is just before a commented `@SHOW` directive) will get displayed.

[demosh]: https://github.com/BuoyantIO/demosh

This workshop requires Kind, and will destroy any cluster named
"linkerd-ipv6".

<!-- @import demosh/check-requirements.sh -->
<!-- @start_livecast -->
---
<!-- @SHOW -->

