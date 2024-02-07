# Emojivoto Installation for Linkerd and Ingress Workshop

This is the documentation - and executable code! - for installing the
Emojivoto demo application onto a running cluster (for use in the Service Mesh
Academy workshop on Linkerd and ingress controllers). The easiest way to use
this file is to execute it with [demosh].

Things in Markdown comments are safe to ignore when reading this later. When
executing this with [demosh], things after the horizontal rule below (which is
just before a commented `@SHOW` directive) will get displayed.

[demosh]: https://github.com/BuoyantIO/demosh

We'll do nothing at all if our cluster already has an `emojivoto` Namespace.

```bash
set -e
DEMOSH_QUIET_FAILURE=true

if kubectl get namespace emojivoto >/dev/null 2>&1; then \
    echo "Emojivoto seems to already be installed" >&2 ;\
    exit 1 ;\
fi
```

----
<!-- @SHOW -->

Time to install Emojivoto! This is straight out of its quickstart.

```bash
curl -sL https://run.linkerd.io/emojivoto.yml \
    | linkerd inject - \
    | kubectl apply -f -
```

After that, just wait for it to be ready.

```bash
kubectl wait pod --for=condition=ready -n emojivoto --all
```

Done! The Emojivoto application is running and ready.

<!-- @wait_clear -->
