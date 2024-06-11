<!--
SPDX-FileCopyrightText: 2024 Buoyant Inc.
SPDX-License-Identifier: Apache-2.0

SMA-Description: Exploring Linkerd route-based policy in detail
-->

# Route-Based Policy

This is the source directory for "A Deep Dive into Route-Based Policy",
presented on 15 September 2022. In here you will find:

- `steps.sh`, the [demo-magic] script driving most of the presentation
- `create-cluster.sh`, a shell script to create a `k3d` cluster and prep it
  with [Linkerd], the [books] demo app, and [Emissary-ingress] for the ingress
   - `create-cluster.sh` uses `kustomize` only to scale Emissary down to one
      replica rather than three, to make it easier to work with e.g. `k3d`.
      This is **not recommended in production**.

To actually run the workshop:

- Make sure that `books.example.com` and `viz.example.com` both point to
  127.0.0.1 (for example, by editing `/etc/hosts`).

- Make sure `$KUBECONFIG` is set correctly.

- If you need to, run `bash create-cluster.sh` to create a new `k3d` cluster
  to use.
   - **Note:** `create-cluster.sh` will delete any existing `k3d` cluster
     named "policy".

- Finally, run `bash steps.sh` to actually run the workshop demo! or just
  read it and run what it does by hand.
   - Note that `steps.sh` includes code to call out to hooks. See the `HOOKS`
     section below for more on these: basically, though, if you do nothing
     special, the commands like `show_browser` etc. will be no-ops: you'll
     just see messages to check things in the browser, and the script will
     wait for you to continue. (You might have to hit ENTER twice, though.)

[books]: https://github.com/BuoyantIO/booksapp
[demo-magic]: https://github.com/paxtonhare/demo-magic/blob/master/demo-magic.sh
[Emissary-ingress]: https://www.getambassador.io/docs/emissary/
[Linkerd]: https://linkerd.io

---

#### HOOKS

When doing the demo live, especially as a livestream, it's nice to have the
demo automagically switch the screen you're sharing to the one that's relevant
at given points of the demo. However, if you're not doing this, it's a pain to
be constantly calling things that don't exist. Enter the `HOOK` setup.

At various points, the demo script will do e.g. `show_browser`, which turns
into a call to `run_hook BROWSER`. That will look for the `DEMO_HOOK_BROWSER`
environment variable: if it's defined, `run_hook` will execute the command in
`hook_browser`. If it's not defined, it gets silently skipped.

The end result: if you want to do fancy things, just set the requisite
`DEMO_HOOK_*` variables to the commands to do fancy things. If you don't set
the `DEMO_HOOK_*` variables, these steps will be silently skipped.
