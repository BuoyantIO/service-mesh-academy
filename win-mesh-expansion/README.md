<!--
SPDX-FileCopyrightText: 2026 Buoyant Inc.
SPDX-License-Identifier: Apache-2.0

SMA-Description: Expanding a Linkerd Enterprise mesh to Windows workloads with the BEL Windows Mesh Expansion installer
-->

# Windows Mesh Expansion with Linkerd

> **Status: first-pass draft.** The demo flow below is being validated end-to-end
> on Azure (AKS + three Windows VMs) before the session. Treat the exact manifests
> and ports as provisional until that dry run is complete.

Mesh expansion lets workloads *outside* your Kubernetes cluster join the same
Linkerd mesh as the workloads inside it - same mTLS identity, same policy, same
observability - so a service running on a VM is a first-class mesh member rather
than an opaque external dependency.

Buoyant Enterprise for Linkerd (BEL) **Windows Mesh Expansion (WME)** brings
**Windows** workloads into the mesh. On each Windows VM it installs:

- the **linkerd2-proxy** and a **harness** that manages it and auto-registers the
  VM with the cluster, and
- **`linkerd-tcp-redirect.sys`**, a WFP (Windows Filtering Platform) kernel
  driver that transparently redirects the VM's **outbound** TCP through the proxy
  - the Windows equivalent of the iptables rules Linkerd uses inside Kubernetes.

This session expands a mesh to three Windows VMs and shows both directions
traffic can flow, why the driver matters, and how policy is enforced across the
cluster boundary.

For the product install reference (supported platforms, prerequisites, the MSI
and its properties, verification, uninstall, troubleshooting) we defer to the
official guide throughout:

**https://docs.buoyant.io/buoyant-enterprise-linkerd/latest/guides/installing-windows-mesh-expansion/**

---

## The two directions - and why the driver is the thing to prove

BEL WME bridges a VM into the mesh in **two independent directions**. They
exercise different parts of the stack, so a complete demo shows **both**:

| Direction | Path | What it proves | Driver? |
|---|---|---|---|
| **Inbound** (cluster → VM) | a cluster workload → the VM's proxy inbound port `:4143` (mTLS terminated) → the app on the VM | proxy + harness + identity | **No** - the driver is outbound-only |
| **Outbound** (VM → cluster) | app on the VM → **driver redirect** → proxy `:4140` → mTLS → destination pod `:4143` | the **WFP driver** (its whole reason to exist) + outbound mTLS | **Yes** |

Inbound mTLS arrives *directly* at the proxy, so the driver is never in that
path - a demo that only shows inbound proves nothing about the driver. The
**outbound** call is the one the driver makes possible, and it's where the
security story lands: require mTLS on the destination, turn the driver **off**,
and the outbound path disappears. No driver, no mesh identity, traffic denied.

The outbound path has two requirements the inbound path doesn't:

1. **The cluster pod CIDR must be routable from the VM** - the proxy completes
   the meshed hop to the *destination pod's* `:4143` at its pod IP. On AKS this
   comes from **VNet peering** between the VM's VNet and the AKS VNet.
2. **The VM must target a meshable cluster address** - a Service name (resolved
   by cluster DNS) or ClusterIP, **never a NodePort**. The proxy can't mesh a
   NodePort and would forward it as plaintext.

---

## What we're demoing: Faces on three VMs

We use the [**Faces**](https://github.com/BuoyantIO/faces-demo) demo app. Faces
renders a grid of cells in the browser; each healthy cell shows a grinning face
(from `smiley`) on a colored background (from `color`). Its call graph is a short
chain:

```
browser ──HTTP──▶ faces-gui ──HTTP──▶ face ──HTTP──▶ smiley
                                        └──gRPC──▶ color
```

- **faces-gui** - the front end the browser hits; calls `face`.
- **face** - fans out to two back ends per cell: `smiley` (HTTP) and `color` (gRPC).
- **smiley** / **color** - leaf back ends returning the emoji and the color.

We split Faces across the cluster and **three** Windows VMs so each VM
demonstrates one thing and runs **one** workload. This covers all three
supported Windows platforms - **Server 2025, Server 2022, and Windows 11** - and
shows the two inbound protocols (HTTP and gRPC) alongside the outbound path.

| VM | OS | Faces workload | Direction | Protocol | Driver? | Path |
|---|---|---|---|---|---|---|
| **VM1** | Windows Server 2025 | **`smiley`** | **Inbound** | HTTP | No | cluster `face` → VM1 proxy `:4143` → `smiley` |
| **VM2** | Windows Server 2022 | **`faces-gui`** | **Outbound** | HTTP | **Yes** | `faces-gui` → **driver** → proxy `:4140` → mTLS → cluster `face :4143` |
| **VM3** | Windows 11 | **`color`** | **Inbound** | **gRPC** | No | cluster `face` → VM3 proxy `:4143` → `color` |

The cluster runs the Linkerd control plane and **`face`** - the hub that fans
out to the two back ends. Every other Faces workload lives on a VM. The browser
points at **VM2's** GUI, so a single page load exercises every direction at once:

```
browser ─▶ faces-gui (VM2) ─[driver ▶ proxy ▶ mTLS]─▶ face (cluster) ─[mTLS, HTTP]─▶ smiley (VM1)
                                                           └─────────[mTLS, gRPC]──▶ color  (VM3)
```

If the cells render, the outbound driver path (gui→face) **and** both inbound
paths (face→smiley over HTTP on VM1, face→color over gRPC on VM3) are all working.

> **Both inbound protocols.** `smiley` is plain HTTP and the simplest to reason
> about live; `color` is gRPC - the direct analog of the gRPC service we meshed
> inbound in the emojivoto demos. The gRPC inbound-policy pattern differs
> slightly (authorize at the `Server`, `proxyProtocol: unknown`) and is shown in
> Part 5.

---

## Prerequisites

- An **AKS** cluster running **Linkerd Enterprise** with external-workload
  support, its control plane reachable from the VM subnet, and the pod CIDR
  routable from the VMs (VNet peering). Cluster bring-up (BEL install,
  certificates, the SPIRE upstream CA, internal load balancers, VNet peering, NSG
  rules) is the standard one-time setup for WME.
- Three **Windows** VMs - Server 2025, Server 2022, and Windows 11 - in a VNet
  peered with the AKS VNet.
- On each VM, in the order the official guide requires: a **SPIRE agent**, **DNS
  resolution** for `*.cluster.local`, then the **BEL WME MSI**. The helper
  scripts in this folder cover SPIRE and DNS; the MSI itself follows the
  [official guide](https://docs.buoyant.io/buoyant-enterprise-linkerd/latest/guides/installing-windows-mesh-expansion/).
- The **Faces Windows binaries** (`faces-gui`, `smiley`, ...) from the
  [faces-demo releases](https://github.com/BuoyantIO/faces-demo/releases)
  (x64 / AMD64), or built from source. The repo's
  `tools/Faces-Demo-Windows-Manager.ps1` can build and run a single component as
  a Windows service - we use it to run **one** component per VM.

---

## Part 1 - Deploy Faces to the cluster

Install Faces into a Linkerd-injected `faces` namespace, then hand two of its
workloads off to the VMs.

```powershell
kubectl create namespace faces
kubectl annotate namespace faces linkerd.io/inject=enabled

helm install faces -n faces oci://ghcr.io/buoyantio/faces-chart --version 2.0.0
kubectl rollout status -n faces deploy
```

Move `smiley`, `color`, and the GUI off-cluster - scale their in-cluster
Deployments to zero. Their **Services stay**: `smiley` and `color` will resolve
to their VMs via ExternalWorkloads, and the browser will hit VM2's GUI directly.

```powershell
kubectl scale deployment smiley color faces-gui -n faces --replicas=0
```

`face` keeps running in the cluster with its default wiring
(`SMILEY_SERVICE=smiley`, `COLOR_SERVICE=color`), so no cluster-side env changes
are needed - it finds both back ends through the same Service names once the VMs
are registered.

---

## Part 2 - Give each VM its own identity (SPIRE)

Every VM joins the mesh as an **ExternalWorkload** with a SPIFFE identity issued
by SPIRE. The production-ready pattern is a **shared intermediate**: a dedicated
**SPIRE upstream CA** (chained to the Linkerd root, stored once in the cluster)
that every VM pulls. Each VM runs its own SPIRE server, which uses that
intermediate to mint a local sub-CA and issue that VM's SVIDs. The result:

- **distinct identities per VM**, so cluster policy can name each one precisely, and
- **one shared trust chain** up to the Linkerd root - the root private key never
  lands on a VM.

Run the SPIRE setup script on each VM (it's in this folder's `spire/`), giving
each a **different** workload SPIFFE ID:

```powershell
# On VM1 (smiley)
powershell.exe -ExecutionPolicy Bypass -File C:\spire\setup-spire.ps1 `
  -CACert     C:\spire\certs\spire-issuer.crt `
  -CAKey      C:\spire\certs\spire-issuer.key `
  -BundleCert C:\spire\certs\bundle.crt `
  -WorkloadSpiffeId spiffe://cluster.local/smiley

# On VM2 (faces-gui)
powershell.exe -ExecutionPolicy Bypass -File C:\spire\setup-spire.ps1 `
  -CACert     C:\spire\certs\spire-issuer.crt `
  -CAKey      C:\spire\certs\spire-issuer.key `
  -BundleCert C:\spire\certs\bundle.crt `
  -WorkloadSpiffeId spiffe://cluster.local/faces-gui

# On VM3 (color)
powershell.exe -ExecutionPolicy Bypass -File C:\spire\setup-spire.ps1 `
  -CACert     C:\spire\certs\spire-issuer.crt `
  -CAKey      C:\spire\certs\spire-issuer.key `
  -BundleCert C:\spire\certs\bundle.crt `
  -WorkloadSpiffeId spiffe://cluster.local/color
```

`-WorkloadSpiffeId` defaults to `spiffe://cluster.local/external-workload`; we
override it so the three VMs get separate identities. These are the identities
the policies in Part 5 authorize.

> A single central SPIRE server shared across VMs is architecturally valid but is
> not the tested BEL WME topology - the per-VM server with a shared upstream CA
> is what we run here.

---

## Part 3 - DNS on each VM (CoreDNS)

The VM's proxy and harness address in-cluster services by **DNS name**
(`*.cluster.local`), so each VM needs to resolve cluster names. `setup-coredns-azure.ps1`
in this folder installs CoreDNS as a Windows service that maps the three Linkerd
control-plane services to their internal-load-balancer IPs and forwards
everything else `*.cluster.local` to kube-dns.

```powershell
powershell.exe -ExecutionPolicy Bypass -File C:\temp\scripts\setup-coredns-azure.ps1 `
  -AutoregIP     <AUTOREG_ILB_IP> `
  -DestinationIP <DEST_ILB_IP> `
  -PolicyIP      <POLICY_ILB_IP> `
  -KubeDnsIP     <DNS_ILB_IP>
```

VM2's `faces-gui` also relies on this to resolve `face.faces.svc.cluster.local`
for its outbound call.

### Matching DNS to non-default installs

The service **names** CoreDNS resolves must match what the harness and proxy
actually look up. Those come from the harness config the MSI generates, and each
is overridable at install time (`CONTROL_ADDRESS`, `DESTINATION_SVC_ADDR`,
`POLICY_SVC_ADDR`; see the official guide's property reference). We use the
defaults in this session, so nothing extra is needed. **If you override those in
your environment**, pass the matching host names to CoreDNS so the two stay in
lockstep:

```powershell
setup-coredns-azure.ps1 ... `
  -AutoregName     linkerd-autoregistration.<ns>.svc.<domain> `
  -DestinationName linkerd-dst.<ns>.svc.<domain> `
  -PolicyName      linkerd-policy.<ns>.svc.<domain>
```

These default to the standard `linkerd-*.linkerd.svc.<ClusterDomain>` names - the
same defaults the installer derives - so overriding is only necessary when your
install does.

---

## Part 4 - Install BEL WME and run the workloads

On **each** VM, with SPIRE running and DNS resolving, install the MSI following
the [official guide](https://docs.buoyant.io/buoyant-enterprise-linkerd/latest/guides/installing-windows-mesh-expansion/).
The session-specific properties are the VM's private IP and its workload group:

```powershell
# VM1
msiexec /i C:\temp\bel_wme_installer.msi /quiet /l*vx C:\temp\install.log `
  INBOUND_NETWORK_ADDRESS="<VM1_PRIVATE_IP>" `
  WORKLOAD_GROUP_NAME="smiley-vm" `
  WORKLOAD_GROUP_NAMESPACE="faces"

# VM2
msiexec /i C:\temp\bel_wme_installer.msi /quiet /l*vx C:\temp\install.log `
  INBOUND_NETWORK_ADDRESS="<VM2_PRIVATE_IP>" `
  WORKLOAD_GROUP_NAME="faces-gui-vm" `
  WORKLOAD_GROUP_NAMESPACE="faces"

# VM3
msiexec /i C:\temp\bel_wme_installer.msi /quiet /l*vx C:\temp\install.log `
  INBOUND_NETWORK_ADDRESS="<VM3_PRIVATE_IP>" `
  WORKLOAD_GROUP_NAME="color-vm" `
  WORKLOAD_GROUP_NAMESPACE="faces"
```

Create an **ExternalGroup** per VM in the `faces` namespace so the harness can
auto-register. VM1's template carries the label the `smiley` Service selects, so
the Service resolves to the VM:

```yaml
# VM1 - smiley (inbound). Labels match the smiley Service selector.
apiVersion: workload.buoyant.io/v1alpha1
kind: ExternalGroup
metadata:
  name: smiley-vm
  namespace: faces
spec:
  probes:
  - httpGet: { path: /ready, port: 4192, scheme: HTTP, host: 127.0.0.1 }
    initialDelaySeconds: 5
    periodSeconds: 10
    failureThreshold: 3
    successThreshold: 1
    timeoutSeconds: 2
  template:
    metadata:
      labels:
        buoyant.io/application: faces
        faces.buoyant.io/component-type: backend
        faces.buoyant.io/component: smiley
    ports:
    - name: http      # smiley Service targetPort is the named port "http"
      port: 8080      # the port smiley listens on, on the VM
---
# VM2 - faces-gui (outbound only). Registers for identity; serves no cluster traffic.
apiVersion: workload.buoyant.io/v1alpha1
kind: ExternalGroup
metadata:
  name: faces-gui-vm
  namespace: faces
spec:
  probes:
  - httpGet: { path: /ready, port: 4192, scheme: HTTP, host: 127.0.0.1 }
    initialDelaySeconds: 5
    periodSeconds: 10
    failureThreshold: 3
    successThreshold: 1
    timeoutSeconds: 2
  template:
    metadata:
      labels:
        buoyant.io/application: faces
        faces.buoyant.io/component: faces-gui
    ports:
    - name: http
      port: 8083
---
# VM3 - color (gRPC inbound). Labels match the color Service selector.
apiVersion: workload.buoyant.io/v1alpha1
kind: ExternalGroup
metadata:
  name: color-vm
  namespace: faces
spec:
  probes:
  - httpGet: { path: /ready, port: 4192, scheme: HTTP, host: 127.0.0.1 }
    initialDelaySeconds: 5
    periodSeconds: 10
    failureThreshold: 3
    successThreshold: 1
    timeoutSeconds: 2
  template:
    metadata:
      labels:
        buoyant.io/application: faces
        faces.buoyant.io/component-type: backend
        faces.buoyant.io/component: color
    ports:
    - name: http      # color Service targetPort is the named port "http" (gRPC rides it)
      port: 8081      # the port color listens on, on the VM
```

Then run the one Faces component on each VM (via the faces-demo Windows manager,
or the binary directly). VM2's GUI points at the in-cluster `face` Service:

```powershell
# VM1 - smiley on :8080 (default)
.\Faces-Demo-Windows-Manager.ps1 Install -Component smiley

# VM2 - GUI on :8083, calling the in-cluster face Service (meshable name, not a NodePort)
#   set FACE_SERVICE=face.faces.svc.cluster.local in the gui env file, then:
.\Faces-Demo-Windows-Manager.ps1 Install -Component gui

# VM3 - color on :8081 (default), gRPC
.\Faces-Demo-Windows-Manager.ps1 Install -Component color
```

**Verify registration** (from a machine with `kubectl`):

```powershell
kubectl get externalworkload -n faces -o wide
# Expect one per VM, each with its own IDENTITY:
#   spiffe://cluster.local/smiley      (VM1)
#   spiffe://cluster.local/faces-gui   (VM2)
#   spiffe://cluster.local/color       (VM3)
```

---

## Part 5 - The demo

**Base flow.** Browse to VM2's GUI (`http://<VM2_PRIVATE_IP>:8083`). Cells should
render grinning faces on colored backgrounds. That single page proves all three
mesh hops at once:

- **outbound / driver**: the GUI's call to `face` left VM2 through the WFP
  driver, was meshed by the proxy, and reached the cluster over mTLS;
- **inbound, HTTP**: `face` reached `smiley` **on VM1** over mTLS (the emoji); and
- **inbound, gRPC**: `face` reached `color` **on VM3** over mTLS (the background).

**Enforce mTLS - and show the driver is required (the payoff).**

Put a policy on the in-cluster `face` Service that requires the caller to be
meshed and authorizes **exactly VM2's identity**. Because the browser talks to
the GUI (not to `face`), we can require mTLS on all of `face` - no read/write
route split is needed.

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: policy.linkerd.io/v1beta3
kind: Server
metadata: { name: face-require-mtls, namespace: faces }
spec:
  podSelector: { matchLabels: { faces.buoyant.io/component: face } }
  port: http
  proxyProtocol: HTTP/1
---
apiVersion: policy.linkerd.io/v1alpha1
kind: MeshTLSAuthentication
metadata: { name: faces-gui-vm-mtls, namespace: faces }
spec:
  identities: ["spiffe://cluster.local/faces-gui"]   # VM2's SPIRE identity
---
apiVersion: policy.linkerd.io/v1alpha1
kind: AuthorizationPolicy
metadata: { name: face-allow-gui-vm, namespace: faces }
spec:
  targetRef: { group: policy.linkerd.io, kind: Server, name: face-require-mtls }
  requiredAuthenticationRefs:
    - { group: policy.linkerd.io, kind: MeshTLSAuthentication, name: faces-gui-vm-mtls }
EOF
```

Now toggle the driver on VM2:

- **driver on** → GUI's outbound call to `face` is meshed as `faces-gui` → authorized → **cells render**.
- **driver off** → no meshed path → `face` denies the (now unmeshed) call → **cells break**.

```powershell
# On VM2 - stop the redirect driver, watch the browser cells fail, then restore
sc.exe stop linkerdtcpredirect
# ... cells break in the browser ...
sc.exe start linkerdtcpredirect
# ... cells recover ...
```

That is the security property: without the driver there is no mesh identity on
the VM's outbound traffic, so policy denies it.

**Inbound enforcement (optional, on the VM back ends).** A default-deny `Server`
plus an `AuthorizationPolicy` authorizing `face`'s in-cluster identity shows the
same story on the inbound side: a direct, unmeshed call to the back end on the
VM is denied, while `face`'s meshed call is allowed. The only difference between
the two back ends is the `Server` protocol - **`smiley` is HTTP**
(`proxyProtocol: HTTP/1`), **`color` is gRPC**, which the proxy treats opaquely
(`proxyProtocol: unknown`), so authorize at the `Server`, not a route.

```bash
cat <<'EOF' | kubectl apply -f -
# --- smiley (HTTP) on VM1 ---
apiVersion: policy.linkerd.io/v1beta3
kind: Server
metadata: { name: smiley-require-mtls, namespace: faces }
spec:
  externalWorkloadSelector: { matchLabels: { faces.buoyant.io/component: smiley } }
  port: http
  proxyProtocol: HTTP/1
---
# --- color (gRPC) on VM3 ---
apiVersion: policy.linkerd.io/v1beta3
kind: Server
metadata: { name: color-require-mtls, namespace: faces }
spec:
  externalWorkloadSelector: { matchLabels: { faces.buoyant.io/component: color } }
  port: http
  proxyProtocol: unknown   # gRPC treated opaquely; authorize at the Server
---
apiVersion: policy.linkerd.io/v1alpha1
kind: MeshTLSAuthentication
metadata: { name: backend-callers, namespace: faces }
spec:
  identities: ["face.faces.serviceaccount.identity.linkerd.cluster.local"]
---
apiVersion: policy.linkerd.io/v1alpha1
kind: AuthorizationPolicy
metadata: { name: smiley-allow-face, namespace: faces }
spec:
  targetRef: { group: policy.linkerd.io, kind: Server, name: smiley-require-mtls }
  requiredAuthenticationRefs:
    - { group: policy.linkerd.io, kind: MeshTLSAuthentication, name: backend-callers }
---
apiVersion: policy.linkerd.io/v1alpha1
kind: AuthorizationPolicy
metadata: { name: color-allow-face, namespace: faces }
spec:
  targetRef: { group: policy.linkerd.io, kind: Server, name: color-require-mtls }
  requiredAuthenticationRefs:
    - { group: policy.linkerd.io, kind: MeshTLSAuthentication, name: backend-callers }
EOF
```

Remove policies when done:

```bash
kubectl delete -n faces server/face-require-mtls authorizationpolicy/face-allow-gui-vm meshtlsauthentication/faces-gui-vm-mtls
kubectl delete -n faces server/smiley-require-mtls server/color-require-mtls authorizationpolicy/smiley-allow-face authorizationpolicy/color-allow-face meshtlsauthentication/backend-callers
```

> **On `AuthorizationPolicy` vs `ServerAuthorization`.** Authorizing an external
> workload keys off its **SPIFFE identity**, so we use `AuthorizationPolicy` +
> `MeshTLSAuthentication` naming that identity. The enterprise build ignores the
> legacy `ServerAuthorization` under its per-route authz model, and `["*"]`
> does not match a SPIFFE id - name the identity explicitly.

---

## Configuring for your environment

Everything above uses defaults so the demo stays simple. The pieces that a real
deployment overrides, and where:

| Setting | Demo value | Where to change it |
|---|---|---|
| Cluster domain / control-plane addresses | defaults (`cluster.local`, `linkerd-*` names) | MSI properties `CLUSTER_DOMAIN`, `CONTROL_ADDRESS`, `DESTINATION_SVC_ADDR`, `POLICY_SVC_ADDR` (official guide) |
| CoreDNS service names | defaults | `setup-coredns-azure.ps1 -AutoregName/-DestinationName/-PolicyName` (must match the MSI addresses above) |
| VM workload identity | per-VM SPIFFE id | `setup-spire.ps1 -WorkloadSpiffeId` |
| Faces service wiring | `FACE_SERVICE`, `SMILEY_SERVICE`, `COLOR_SERVICE` | Faces component env files |

---

## Cleanup

```powershell
# On each VM: uninstall BEL WME (see the official guide), then remove Faces
.\Faces-Demo-Windows-Manager.ps1 Uninstall -Force

# In the cluster
helm uninstall faces -n faces
kubectl delete namespace faces
```

---

## References

- Official install guide:
  https://docs.buoyant.io/buoyant-enterprise-linkerd/latest/guides/installing-windows-mesh-expansion/
- Faces demo: https://github.com/BuoyantIO/faces-demo
