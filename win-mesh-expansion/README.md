# Windows Mesh Expansion with Buoyant Enterprise for Linkerd

Mesh expansion lets workloads *outside* your Kubernetes cluster join the same
Linkerd mesh as the workloads inside it - same mTLS identity, same policy, same
observability - so a service running on a VM is a first-class mesh member rather
than an opaque external dependency.

Buoyant Enterprise for Linkerd (BEL) **Windows Mesh Expansion (WME)** brings **Windows**
workloads into the mesh. On each VM the MSI installs the **`linkerd-proxy-harness`** service
(`harness.exe` - supervises the linkerd2-proxy and auto-registers the VM as an
ExternalWorkload), the **`linkerd-tcp-redirect.sys`** WFP kernel driver (redirects the VM's
**outbound** TCP into the proxy - the Windows analog of Linkerd's iptables; inbound needs no
redirect, the cluster hits the proxy's inbound port directly), an ETW logging session, and
the **`harnessctl.exe`** CLI. **SPIRE and DNS are prerequisites, not installed by the MSI.**

This session expands a mesh to three Windows VMs, showing both traffic directions, why the
driver matters, and how policy is enforced across the cluster boundary.

For the product install reference (supported platforms, prerequisites, the MSI
and its properties, verification, uninstall, troubleshooting) we defer to the
official guide throughout:

**https://docs.buoyant.io/buoyant-enterprise-linkerd/latest/guides/installing-windows-mesh-expansion/**

---

## What we're demoing: Faces across a cluster and three VMs

We use the [**Faces**](https://github.com/BuoyantIO/faces-demo) app: the browser loads a
grid of cells, each a face (`smiley`) on a colored background (`color`), assembled by
`face` and served by `faces-gui`. We keep the Linkerd control plane and `face` in the
cluster and move the other three workloads onto three Windows VMs - one each, covering
all three supported platforms and both inbound protocols:

| VM | OS | Faces workload |
|---|---|---|
| **VM1** | Server 2025 | `smiley` |
| **VM2** | Server 2022 | `faces-gui` |
| **VM3** | Windows 11 | `color` |

A fourth VM runs the **SPIRE server** and no Faces workload. Identity is infrastructure, not
part of the app, and separating it is what lets the three workload VMs hold no CA key at all
(Part 2).

The browser points at **VM2's GUI**, so one page load exercises every path at once. The
**outbound** call (`gui → face`) is the only one that needs the **WFP driver** - it
redirects the VM's outbound TCP into the proxy for mTLS - and it's where the security
story lands (require mTLS on `face` and turn the driver off on VM2 - the path
disappears, the demo's payoff). The **inbound** calls (`face → smiley` over HTTP, `face → color` over gRPC)
never touch the driver; the cluster connects straight to each VM's proxy `:4143`. If
every cell renders, all three hops are meshed.

The outbound path has two requirements inbound doesn't:
1. **the cluster pod CIDR routable from the VM** - the proxy meshes to the destination
   *pod IP* on `:4143`; on AKS this comes from VNet peering;
2. **a meshable target** - a Service name or ClusterIP, never a NodePort (the proxy
   can't mesh a NodePort and would forward it plaintext).

---

## Prerequisites

- An **AKS** cluster running **Linkerd Enterprise (BEL 2.20.1)** with external-workload
  support, its VNet **peered** to the VMs'. Peering routes real VNet addresses, so the
  outbound data path (**pod IPs**) reaches the VM directly - but the control-plane
  **ClusterIP** services don't route over peering, so they're published to the VMs as
  **internal load balancers** (autoregistration, destination, policy, kube-dns). Cluster
  bring-up - BEL install, certs, SPIRE upstream CA, those ILBs, peering, NSG rules - is
  the standard one-time WME setup.
- Three **Windows** workload VMs - Server 2025, Server 2022, and Windows 11 - in a VNet
  peered with the AKS VNet, plus one more VM running the **SPIRE server** (Part 2). The
  SPIRE server VM needs no peering-dependent access of its own; it only has to be reachable
  on `:8081` from the workload VMs' subnet.
- On each VM, in the order the official guide requires: a **SPIRE agent**, **DNS
  resolution** for `*.cluster.local`, then the **BEL WME MSI**. The helper
  scripts in this folder cover SPIRE and DNS; the MSI itself follows the
  [official guide](https://docs.buoyant.io/buoyant-enterprise-linkerd/latest/guides/installing-windows-mesh-expansion/).
  The MSI does **not** touch Windows Firewall - inbound-serving VMs need the proxy ports
  opened to the cluster (Part 4), which is also the workload-isolation control.
- The **Faces Windows binaries** (`faces-gui`, `smiley`, ...) at **v2.1.0-rc.2**,
  from the [faces-demo v2.1.0-rc.2 release](https://github.com/BuoyantIO/faces-demo/releases/tag/v2.1.0-rc.2)
  (asset `faces-demo_generic_2.1.0-rc.2_windows_amd64.zip`, x64 / AMD64), or built
  from source (`tools/Faces-Demo-Windows-Manager.ps1 Build`). This **must** match
  the in-cluster Faces chart version installed in Part 1. We run **one** component per VM,
  registered as an SCM service by `install-faces-service.ps1` (see Part 5).
  Note that archive holds **binaries only - no web assets**. The GUI serves its pages off
  disk from `DATA_PATH`; the container image gets them from `COPY assets/html /app/data`,
  so on Windows `install-faces-service.ps1` stages `assets/html` from the matching source
  tag instead. Without that the GUI proxies `/face/` correctly and returns **404** for the
  page itself - a confusing failure, since the mesh is working fine.

### How identity is established on the cluster (one-time)

Everything meshed - the control plane and every VM - derives its mTLS identity from a
single **trust anchor**: the Linkerd **root CA** (`root.linkerd.cluster.local`), whose
private key stays with the operator and never lands on a VM. Two intermediates chain
under it and are loaded into the cluster as the Kubernetes objects the rest of the stack
reads:

- **Linkerd issuer** (`pathlen:0`) signs the control plane's own TLS certs. It's stored
  as the `linkerd-identity-issuer` **TLS secret** - the issuer cert and key, with the
  root's `ca.crt` merged into the secret's data - alongside the
  `linkerd-identity-trust-roots` **configmap** holding the root bundle that proxies verify
  peers against. BEL is installed pointing at these (`identity.externalCA=true`,
  `identity.issuer.scheme=kubernetes.io/tls`) instead of self-generating an issuer.
- **SPIRE upstream CA** (`pathlen:1`) is a second intermediate dedicated to VM identity,
  generated once and stored as the `spire-upstream-ca` **secret**. The **SPIRE server VM**
  pulls it once in Part 2 to mint a sub-CA and issue SVIDs for every workload VM, so all VM
  identities chain back to the same root **while the root key never leaves the cluster** -
  and the upstream CA key lands on exactly **one** VM rather than all of them. Because it's
  a dedicated intermediate, it can be rotated or revoked without touching the root - using
  the root directly would work but would put the root key on a VM.

This is the standard one-time WME cluster bring-up (BEL install plus these certs), done
before any VM is onboarded; the ILBs, peering, and NSG rules noted in
[Prerequisites](#prerequisites) are the rest of it.

---

## Part 1 - Deploy Faces to the cluster

Install the Faces chart into a Linkerd-injected `faces` namespace (the `inject=enabled`
annotation is what meshes the pods), then scale the VM-bound workloads to zero so their
Services resolve to the VMs. The two value overrides expose the GUI on a public
LoadBalancer (to watch the grid before the VMs exist) and zero Faces' built-in
error/latency injection for a clean baseline.

**On the cluster** (PowerShell → `kubectl`/`helm`):
```text
kubectl create namespace faces
kubectl annotate namespace faces linkerd.io/inject=enabled

@'
gui:     { serviceType: LoadBalancer }
face:    { errorFraction: "0", delayBuckets: "" }
backend: { errorFraction: "0", delayBuckets: "" }
'@ | helm install faces -n faces oci://ghcr.io/buoyantio/faces-chart --version 2.1.0-rc.2 -f -
kubectl rollout status -n faces deploy
kubectl get svc faces-gui -n faces    # EXTERNAL-IP = demo URL until the GUI moves to VM2

# after you've eyeballed the grid, hand the VM-bound workloads off (their Services stay):
kubectl scale deployment smiley color faces-gui -n faces --replicas=0
```

---

## Part 2 - Give each VM its own identity (SPIRE)

Every VM joins as an **ExternalWorkload** with its own SPIFFE identity. **One** VM runs the
SPIRE **server**, backed by the shared `spire-upstream-ca` intermediate (see
[How identity is established on the cluster](#how-identity-is-established-on-the-cluster-one-time));
each workload VM runs only a SPIRE **agent** that attests to it. Every VM gets a distinct
SPIFFE ID (`.../smiley`, `.../faces-gui`, `.../color`) that cluster policy can authorize, and
all of them chain to the same root.

Why split it out: the SPIRE server needs the upstream CA **private key** to mint its sub-CA.
Running a server per VM means copying that key onto every machine that runs application code
- so compromising any workload VM yields the ability to mint identities for the whole trust
domain. With one server VM, the key sits on a machine that runs no application, and a
workload VM holds nothing more sensitive than a public trust bundle. It's also less to set
up per VM, and registrations live in one place instead of three.

**On a machine with `kubectl`**, pull the upstream CA (from the secret) and the Linkerd root
(from the trust-roots configmap), and build the trust bundle (upstream CA **+** root - the
proxy needs the root to verify the control plane's TLS):

```text
$stage = "C:\temp\spire\certs"; New-Item -ItemType Directory -Force $stage | Out-Null
$b64 = kubectl get secret spire-upstream-ca -n linkerd -o jsonpath='{.data.ca\.crt}'
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64)) | Out-File -Encoding ascii "$stage\spire-issuer.crt"
$b64 = kubectl get secret spire-upstream-ca -n linkerd -o jsonpath='{.data.ca\.key}'
[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64)) | Out-File -Encoding ascii "$stage\spire-issuer.key"
kubectl get configmap linkerd-identity-trust-roots -n linkerd -o jsonpath='{.data.ca-bundle\.crt}' | Out-File -Encoding ascii "$stage\root-ca.crt"
Get-Content "$stage\spire-issuer.crt", "$stage\root-ca.crt" | Out-File -Encoding ascii "$stage\bundle.crt"
```

Distribute those files carefully - this is where the security property lives:

| file | goes to | why |
|---|---|---|
| `spire-issuer.crt` + `spire-issuer.key` | **the SPIRE server VM only** | the CA key it mints its sub-CA from |
| `bundle.crt` | **every** VM | public certs only; the agent verifies the server with it, the proxy verifies the control plane with it |

### 2a. The SPIRE server VM

Copy this folder's `spire\` scripts and all three certs to `C:\temp\spire\`, then run as
Administrator. The script downloads SPIRE, bootstraps the server against the upstream CA,
opens `:8081` to the workload subnet, and installs it as an auto-start service:

**On the SPIRE server VM** (PowerShell, as admin):
```powershell
powershell -ExecutionPolicy Bypass -File C:\temp\spire\setup-spire.ps1 -Role Server `
  -CACert     C:\temp\spire\certs\spire-issuer.crt `
  -CAKey      C:\temp\spire\certs\spire-issuer.key `
  -BundleCert C:\temp\spire\certs\bundle.crt `
  -AllowFromCidr 10.20.0.0/24
```

The server binds `0.0.0.0:8081`. `Get-NetTCPConnection -LocalPort 8081` reports `::` rather
than `0.0.0.0` - that is Go rendering a wildcard bind as a dual-stack socket, not a failure.

### 2b. Each workload VM

Two commands **on the server VM** per workload VM - register what identity that VM's
workload may have, then mint its one-shot join token:

**On the SPIRE server VM** (PowerShell, as admin):
```powershell
# <vm> is any stable label (smiley / faces-gui / color); <workload> is the Faces component.
C:\spire\bin\spire-server.exe entry create `
  -parentID spiffe://cluster.local/agent/<vm> `
  -spiffeID spiffe://cluster.local/<workload> `
  -selector "windows:user_name:NT AUTHORITY\SYSTEM"
C:\spire\bin\spire-server.exe token generate -spiffeID spiffe://cluster.local/agent/<vm>
```

**Give every VM a distinct `-parentID`.** `token generate -spiffeID` creates a *node alias*
for the attesting agent, and the workload entry hangs off that alias. Reuse one alias across
VMs and they do not collide or error - they all match the first VM's workload entry, so the
second VM silently comes up carrying the wrong identity, which then fails cluster policy for
reasons that point nowhere near SPIRE.

Then copy the `spire\` scripts and **`bundle.crt` only** to the workload VM and run as
Administrator, pasting the token you just minted. The token is one-shot with a short TTL, so
mint it immediately before this:

**On the workload VM** (PowerShell, as admin):
```powershell
powershell -ExecutionPolicy Bypass -File C:\temp\spire\setup-spire.ps1 -Role Agent `
  -BundleCert    C:\temp\spire\certs\bundle.crt `
  -ServerAddress 10.20.0.11 `
  -JoinToken     <token-from-above>
```

The script refuses `-CACert`/`-CAKey` in this role, so a workload VM cannot accidentally be
handed a CA key. It also installs the agent service with **no** `depend=`, since there is no
local server - if the server VM or the network is not ready at boot, SCM's restart actions
retry.

Verify, then remove the staging copy (certs are now installed under `C:\spire\certs`):

**On the workload VM** (PowerShell):
```powershell
sc.exe query spire-agent                       # STATE : RUNNING
Test-Path "\\.\pipe\spire-agent\public\api"     # True
Remove-Item C:\temp\spire -Recurse -Force
```

`C:\spire\logs\agent.log` should show `Bundle loaded` and a `Creating X509-SVID` line naming
**this** VM's workload SPIFFE ID. If it shows a different VM's ID, the `-parentID` was reused.

---

## Part 3 - DNS on each VM (CoreDNS)

A VM's harness and proxy reach the control plane by **DNS name**. Because the control-plane
Services are ClusterIPs (which don't route over the VNet peering), cluster setup publishes
them - and kube-dns - as **internal LoadBalancers** (see [Prerequisites](#prerequisites));
CoreDNS on each VM maps the control-plane names to those ILB IPs and forwards the rest of
`*.cluster.local` to the kube-dns ILB.

First confirm the four ILBs are reachable from the VM (peering + LBs in place):

**On the VM** (PowerShell):
```powershell
Test-NetConnection <autoreg-ilb-ip> -Port 8081 -InformationLevel Quiet
Test-NetConnection <dest-ilb-ip>    -Port 8086 -InformationLevel Quiet
Test-NetConnection <policy-ilb-ip>  -Port 8090 -InformationLevel Quiet
Test-NetConnection <kubedns-ilb-ip> -Port 53   -InformationLevel Quiet
```

All `True`, then install CoreDNS (`setup-coredns-azure.ps1` from this folder, staged under
`C:\temp\coredns\`), passing the four ILB IPs:

**On the VM** (PowerShell, as admin):
```powershell
powershell -ExecutionPolicy Bypass -File C:\temp\coredns\setup-coredns-azure.ps1 -AutoregIP <autoreg-ilb-ip> -DestinationIP <dest-ilb-ip> -PolicyIP <policy-ilb-ip> -KubeDnsIP <kubedns-ilb-ip>
```

Verify the control-plane names resolve to the ILB IPs:

**On the VM** (PowerShell):
```powershell
Resolve-DnsName linkerd-autoregistration.linkerd.svc.cluster.local -Server 127.0.0.1
Resolve-DnsName linkerd-dst.linkerd.svc.cluster.local -Server 127.0.0.1
Resolve-DnsName linkerd-policy.linkerd.svc.cluster.local -Server 127.0.0.1
```

VM2's `faces-gui` also uses this to resolve `face.faces.svc.cluster.local`. (Non-default
control-plane namespace/domain? Pass `-AutoregName/-DestinationName/-PolicyName` to match
the MSI's `CONTROL_ADDRESS`/`DESTINATION_SVC_ADDR`/`POLICY_SVC_ADDR`.)

---

## Part 4 - Install BEL WME on each VM

With SPIRE running and DNS resolving, install the MSI. The only per-VM properties are the
private IP and workload group - the control-plane addresses, SPIRE socket, and cluster
domain all default to what our cluster + CoreDNS already use.

**On each VM** (PowerShell, as admin):
```text
# download the BEL WME MSI (2.20.1 - see the driver-signing note below; do NOT use 2.20.0)
curl.exe -L -o C:\temp\bel_wme.msi "https://github.com/BuoyantIO/linkerd-buoyant/releases/download/enterprise-2.20.1/bel_wme_installer-enterprise-2.20.1.msi"

# install. <VM_PRIVATE_IP> = this VM's IP; <WORKLOAD_GROUP> = smiley-vm | faces-gui-vm | color-vm (the <NAME> column below).
msiexec /i C:\temp\bel_wme.msi /quiet /l*vx C:\temp\wme-install.log INBOUND_NETWORK_ADDRESS="<VM_PRIVATE_IP>" WORKLOAD_GROUP_NAME="<WORKLOAD_GROUP>" WORKLOAD_GROUP_NAMESPACE="faces"

# verify: both services RUNNING, and the harness certified its identity
sc.exe query linkerd-proxy-harness   # RUNNING
sc.exe query linkerdtcpredirect      # RUNNING - the WFP driver (loads under Secure Boot; it's WHQL-signed)
Get-Content "C:\Program Files\Buoyant\Linkerd\harness.log" -Tail 30
```

`harness.log` should show `Certified identity id=spiffe://cluster.local/<component>`, the
three control-plane endpoints resolving to their ILB IPs, and no `UnknownIssuer`/connection
errors. If the install itself fails, the verbose log is at `C:\temp\wme-install.log`.

> **Why 2.20.1, not 2.20.0.** The MSI carries the WFP driver, and the two releases carry
> different builds of it: 2.20.0 ships driver `1.2.0.0`, WHQL-signed for Windows 11 and
> Server 2025 only, while 2.20.1 ships `1.3.0.0`, the combined **Server 2022 + 2025**
> signature. On VM2 - Server 2022 with Secure Boot - the 2.20.0 driver has no acceptable
> signature and `linkerdtcpredirect` will not load, which breaks the one VM whose whole
> story is the driver. `sc.exe query linkerdtcpredirect` returning `RUNNING` as a
> `KERNEL_DRIVER` is the direct check that the right build is installed.

The **WFP driver** logs to a WPP ETW trace at `C:\Program Files\Buoyant\Linkerd\linkerd-tcp-redirect-driver.etl`
(a 50 MB circular file, capturing from boot). `sc.exe query linkerdtcpredirect` = `RUNNING` above is the
quick proof it loaded; for driver-level detail, decode the ETL with `tracefmt` (from the Windows Driver Kit)
against the installed symbols:

**On the VM** (PowerShell; needs the WDK's `tracefmt`):
```powershell
$d = "$env:ProgramFiles\Buoyant\Linkerd"
tracefmt -p "$d\driver" -o "$d\driver.log" "$d\linkerd-tcp-redirect-driver.etl"
# in driver.log, look for: CONNECT_REDIRECT_V4 Filter added   (the outbound callout registered)
```

`tracefmt` isn't on a stock VM, so treat the ETL decode as troubleshooting, not a required step.

### Lock the workloads to cluster-only access (Windows Firewall)

Inbound-serving VMs (VM1 `smiley`, VM3 `color`) need the proxy's inbound + metrics ports
opened **only to the AKS pod CIDR**, with the app port left closed - the MSI adds no firewall
rules.

**On inbound VMs** (PowerShell, as admin):
```powershell
# scope to the AKS VNet address space (10.224.0.0/12 in this session)
New-NetFirewallRule -DisplayName "Linkerd mesh inbound (4143)"  -Direction Inbound -Action Allow -Protocol TCP -LocalPort 4143 -RemoteAddress 10.224.0.0/12
New-NetFirewallRule -DisplayName "Linkerd proxy metrics (4191)" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 4191 -RemoteAddress 10.224.0.0/12
```

With the app port (`smiley` :8080 / `color` :8081) closed, the workload is reachable **only
through the mesh** (cluster → proxy `:4143`, mTLS, from the AKS range) - never directly from
other VMs or the VNet. That firewall-plus-mesh isolation is the production-lockdown property.
(No tap port - tap is deprecated.)

**VM2 is the exception, and it inverts the rule.** It needs no *mesh* inbound rules - nothing
in the cluster dials it - but the GUI is a web page humans load, so its **app port `:8083`
must be open**, which is the opposite of the lockdown above. That takes rules at *two* layers:
Windows Firewall on the VM, and an Azure **NSG** rule, since `az vm create` attaches a NIC NSG
that allows only RDP and the default `DenyAllInBound` drops everything else.

**On VM2** (PowerShell, as admin):
```powershell
New-NetFirewallRule -DisplayName "Faces GUI app port (8083)" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8083
```

**On the cluster host** (az; `<NSG_NAME>` is the VM's NIC NSG, `<VM_NAME>NSG` by default):
```powershell
az network nsg rule create -g <RESOURCE_GROUP> --nsg-name <NSG_NAME> -n faces-gui-8083 `
  --priority 1010 --direction Inbound --access Allow --protocol Tcp `
  --destination-port-ranges 8083 --source-address-prefixes '*'
```

The mesh ports stay unexposed on VM2 - this opens only the page itself.

### Register each VM as an ExternalWorkload

Apply one **ExternalGroup** per VM so the harness auto-registers; the labels match that
component's Service selector, so the Service resolves to the VM.

**On the cluster** (kubectl):

```yaml
# One per VM - fill <NAME>, <COMPONENT>, <PORT> from the table below.
apiVersion: workload.buoyant.io/v1alpha1
kind: ExternalGroup
metadata:
  name: <NAME>
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
        faces.buoyant.io/component-type: backend    # backends only; OMIT for faces-gui (outbound-only)
        faces.buoyant.io/component: <COMPONENT>
    ports:
    - { name: http, port: <PORT> }
```

| VM | `<NAME>` | `<COMPONENT>` | `<PORT>` | notes |
|---|---|---|---|---|
| VM1 | `smiley-vm` | `smiley` | 8080 | backend |
| VM2 | `faces-gui-vm` | `faces-gui` | 8083 | outbound-only - **omit** the `component-type` label |
| VM3 | `color-vm` | `color` | 8081 | backend (gRPC rides the named `http` port) |

Confirm registration:

**On the cluster** (kubectl):
```text
kubectl get externalworkload -n faces -o wide   # one per VM, each with its own spiffe:// identity
```

---

## Part 5 - Run the Faces workloads

Run the one Faces component per VM as an SCM service with `install-faces-service.ps1`. The
Faces binaries are plain console apps, so the script wraps each in
[WinSW](https://github.com/winsw/winsw) - a real service that starts after the mesh is up
(depends on `linkerd-proxy-harness`), restarts on failure, and rolls logs to
`C:\faces-demo\logs\<component>\`. It downloads the pinned Faces binary for the component,
so you just pass `-Component`. For `-Component gui` it also stages the web assets and sets
`DATA_PATH`, since the Windows release ships none (see [Prerequisites](#prerequisites)).

**On each VM** (PowerShell, as admin):
```powershell
# VM1 - smiley (:8080)
.\install-faces-service.ps1 -Component smiley

# VM2 - GUI (:8083), calling the in-cluster face Service by its meshable name
.\install-faces-service.ps1 -Component gui -EnvVars @{ FACE_SERVICE = "face.faces.svc.cluster.local" }

# VM3 - color (:8081, gRPC)
.\install-faces-service.ps1 -Component color
```

### smiley and color: they just appear in the grid

`smiley` and `color` are back ends - each is one cell in whatever grid you're already
watching. With the component running on its VM and its in-cluster Deployment at 0 (Part 1),
the `smiley` / `color` Service resolves to the VM (via the `linkerd-external-<svc>-*`
EndpointSlice), so the emoji and its background now come from Windows over inbound mTLS.
There's no new address to visit - the cells just change source.

### The GUI is the front door: it moves off the cluster onto VM2

The GUI is different - it's the page you view, not a cell in it. Part 1 scaled the in-cluster
`faces-gui` to 0 along with the back ends, so the LoadBalancer URL from Part 1
(`kubectl get svc faces-gui -n faces`) now has no backing pod and goes dark. The live GUI is
the one on **VM2**, served on VM2's own address - not the cluster LB.

Reach it over VM2's public IP: open inbound TCP `:8083` and browse `http://<VM2_PUBLIC_IP>:8083`
(both the Windows Firewall rule and the NSG rule from Part 4). That's the GUI app port only -
the mesh ports stay locked down as in Part 4.

> **Close the old LB tab before you demo this.** "Goes dark" undersells what a stale tab does:
> the page HTML is already loaded, so its JS keeps polling `/face/` through a LoadBalancer
> that now has no endpoints, and every cell renders the **error face**. On a projector that
> reads as "he broke it", not as "the front door moved to Windows". A hard refresh of that tab
> just fails to connect, which is the honest picture - or close it and open VM2's URL fresh.

VM2's GUI then renders the full grid - `face` (in-cluster) fanning out to `smiley` on VM1 and
`color` on VM3, all over mTLS - the whole mesh spanning the cluster and three Windows VMs.
