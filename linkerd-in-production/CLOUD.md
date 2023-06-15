# Linkerd in Production workshop: Buoyant Cloud

This is the documentation - and executable code! - for the Buoyant Cloud
section of the Service Mesh Academy "Linkerd in Production" workshop. The
easiest way to use this file is to execute it with [demosh].

Things in Markdown comments are safe to ignore when reading this later. When
executing this with [demosh], things after the horizontal rule below (which is
just before a commented `@SHOW` directive) will get displayed.

[demosh]: https://github.com/BuoyantIO/demosh

See [README.md] for important requirements for this SMA! Also note that you'll
need to create your own `cloud-values.yaml` file, containing the values from
Buoyant Cloud's "Add Cluster" command.

[Civo]: https://civo.io/

<!-- @import demosh/demo-tools.sh -->
<!-- @clear -->
---
<!-- @SKIP -->

# Link this cluster to Buoyant Cloud

We'll use Helm for this. Add the Buoyant Cloud Helm repo...

```bash
helm repo add linkerd-buoyant https://helm.buoyant.cloud --force-update
helm repo update linkerd-buoyant
```

...then install the Buoyant Cloud agent. The agent needs certain values from
Buoyant Cloud's "add a cluster" option, which we've saved in
`cloud-values.yaml`. These are sensitive: don't show them to people.

```bash
sed -e 's/: .*$/: .../' < cloud-values.yaml | bat -l yaml

helm install \
     --create-namespace --namespace buoyant-cloud \
     --values cloud-values.yaml \
     --set metadata.agentName=SMA \
     --wait \
     linkerd-buoyant linkerd-buoyant/linkerd-buoyant
```

<!-- @SHOW -->

OK -- now we're connected to Cloud. Let's take a look.

<!-- @browser_then_terminal -->

# Start managing the control plane

To have Cloud manage the control plane for us, we need to start by creating a
ControlPlane resource defining what version of the control plane we want to
use.

```bash
bat control-plane.yaml
kubectl apply -f control-plane.yaml
```

We also need to create DataPlane resources, one per namespace, so that Cloud
can keep our data plane workloads up to date when it changes the control plane
version:

```bash
bat data-plane.yaml
kubectl apply -f data-plane.yaml
```

OK! We should shortly see the "Managed status" in the Cloud console change to
"UpToDate".

<!-- @browser_then_terminal -->

# Roll back to 2.13.3

We can use Cloud to change the the control plane's version by simply editing
our ControlPlane resource.

```bash
kubectl edit controlplane control-plane
```

Switching back to the Cloud console, we should see the control plane roll back
for us.

<!-- @browser_then_terminal -->

So there's a very, very brief example of things Buoyant Cloud can do! To check
it out yourself, visit https://buoyant.io/demo.

<!-- @wait -->
