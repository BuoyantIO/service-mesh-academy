# Linkerd Installation for Linkerd and Ingress Workshop

This is the documentation - and executable code! - for installing Linkerd onto
a running cluster (for use in the Service Mesh Academy workshop on Linkerd and
ingress controllers). The easiest way to use this file is to execute it with
[demosh].

Things in Markdown comments are safe to ignore when reading this later. When
executing this with [demosh], things after the horizontal rule below (which is
just before a commented `@SHOW` directive) will get displayed.

[demosh]: https://github.com/BuoyantIO/demosh

We'll do nothing at all if our cluster already has a `linkerd` Namespace.

```bash
set -e
DEMOSH_QUIET_FAILURE=true

if kubectl get namespace linkerd >/dev/null 2>&1; then \
    echo "Linkerd seems to already be installed" >&2 ;\
    exit 1 ;\
fi
```

<!-- @import demo-tools.sh -->
----
<!-- @SHOW -->

Time to install Linkerd! This is straight out of the Linkerd quickstart:
first, we need to install the CRDs...

```bash
linkerd install --crds | kubectl apply -f -
```

...then we install Linkerd itself.

```bash
linkerd install | kubectl apply -f -
```

Let's install `linkerd viz` as well.

```bash
linkerd viz install | kubectl apply -f -
```

Finally, we wait for everything to be ready.

```bash
linkerd check
```

Done! Linkerd and `linkerd viz` should be ready to go.

<!-- @wait_clear -->
