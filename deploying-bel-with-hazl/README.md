# Deploying Buoyant Enterprise for Linkerd (BEL) With High Availability Zonal Load Balancing (HAZL)

## deploying-bel-with-hazl

### Jason Morgan | Tom Dean | Buoyant

### Last edit: 2/2/2024

## Introduction

In this *hands-on demonstration*, we will deploy Buoyant **Enterprise for Linkerd** on a `k3d` Kubernetes cluster and will demonstrate how to quickly enable **High Availability Zonal Load Balancing (HAZL)**.  We'll then take a look at how **HAZL** works to keep network traffic in-zone where possible, and explore Security Policy generation.

Feel free to follow along with *your own instance* if you'd like, using the provided resources and instructions.

### What is Buoyant Enterprise for Linkerd (BEL)

[Buoyant Enterprise for Linkerd](https://buoyant.io/enterprise-linkerd)

**Buoyant Enterprise for Linkerd** is an enterprise-grade service mesh for Kubernetes. It makes Kubernetes applications reliable, secure, and cost-effective *without requiring any changes to application code*. Buoyant Enterprise for Linkerd contains all the features of open-source Linkerd, the world's fastest, lightest service mesh, plus additional enterprise-only features such as:

- High Availability Zonal Load Balancing (HAZL)
- Security Policy Generation
- FIPS-140-2/3 Compliance
- Lifecycle Automation
- Enterprise-Hardened Images
- Software Bills of Materials (SBOMs)
- Strict SLAs Around CVE Remediation

We're going to try out **Security Policy Generation and HAZL** in this demo, but remember that we'll get all the **BEL** features, ***except for FIPS***, which isn't included in our Trial license.

### What is HAZL?

**High Availability Zonal Load Balancing (HAZL)** is a dynamic request-level load balancer in **Buoyant Enterprise for Linkerd** that balances **HTTP** and **gRPC** traffic in environments with **multiple availability zones**. For Kubernetes clusters deployed across multiple zones, **HAZL** can **dramatically reduce cloud spend by minimizing cross-zone traffic**.

Unlike other zone-aware options that use **Topology Hints** (including **Istio** and open source **Linkerd**), **HAZL** *never sacrifices reliability to achieve this cost reduction*.

In **multi-zone** environments, **HAZL** can:

- **Cut cloud spend** by eliminating cross-zone traffic both within and across cluster boundaries;
- **Improve system reliability** by distributing traffic to additional zones as the system comes under stress;
- **Prevent failures before they happe** by quickly reacting to increases in latency before the system begins to fail.
- **Preserve zone affinity for cross-cluster calls**, allowing for cost reduction in multi-cluster environments.

Like **Linkerd** itself, **HAZL** is designed to *"just work"*. It works without operator involvement, can be applied to any Kubernetes service that speaks **HTTP** / **gRPC** regardless of the number of endpoints or distribution of workloads and traffic load across zones, and in the majority of cases *requires no tuning or configuration*.

### How HAZL Works

For every endpoint, **HAZL** maintains a set of data that includes:

- The **zone** of the endpoint
- The **cost** associated with that zone
- The **recent latency** of responses to that endpoint
- The **recent failure rate** of responses to that endpoint

For every service, **HAZL** continually computes a load metric measuring the utilization of the service. When load to a service falls outside the acceptable range, whether through failures, latency, spikes in traffic, or any other reason, **HAZL** dynamically adds additional endpoints from other zones. When load returns to normal, **HAZL** automatically shrinks the load balancing pool to just in-zone endpoints.

In short: under normal conditions, **HAZL** keeps all traffic within the zone, but when the system is under stress, **HAZL** will temporarily allow cross-zone traffic until the system returns to normal.

**HAZL** will also apply these same principles to cross-cluster / multi-cluster calls: it will preserve zone locality by default, but allow cross-zone traffic if necessary to preserve reliability.

### HAZL vs Topology Hints
**HAZL** was designed in response to limitations seen by customers using Kubernetes's native **Topology Hints** (aka **Topology-aware Routing**) mechanism. These limitations are shared by native Kubernetes balancing (**kubeproxy**) as well as systems such as open source **Linkerd** and **Istio** that make use of **Topology Hint**s to make routing decisions.

Within these systems, the endpoints for each service are allocated ahead of time to specific zones by the **Topology Hints** mechanism. This distribution is done at the Kubernetes API level, and attempts to allocate endpoints within the same zone (but note this behavior isn't guaranteed, and the Topology Hints mechanism may allocate endpoints from other zones). Once this allocation is done, it is static until endpoints are added or removed. It does not take into account traffic volumes, latency, or service health (except indirectly, if failing endpoints get removed via health checks).

Systems that make use of **Topology Hints**, including **Linkerd** and **Istio**, use this allocation to decide where to send traffic. This accomplishes the goal of keeping traffic within a zone but at the expense of reliability: **Topology Hints** itself provides no mechanism for sending traffic across zones if reliability demands it. The closest approximation in (some of) these systems are manual failover controls that allow the operator to failover traffic to a new zone.

Finally, **Topology Hints** has a set of well-known constraints, including:

- It does not work well for services where a large proportion of traffic originates from a subset of zones.
- It does not take into account tolerations, unready nodes, or nodes that are marked as control plane or master nodes.
- It does not work well with autoscaling. The autoscaler may not respond to increases in traffic, or respond by adding endpoints in other zones.
- No affordance is made for cross-cluster traffic.

These constraints have real-world implications. As one customer put it when trying **Istio** + **Topology Hints**: 
"What we are seeing in *some* applications is that they won’t scale fast enough or at all (because maybe two or three pods out of 10 are getting the majority of the traffic and is not triggering the HPA) and *can cause a cyclic loop of pods crashing and the service going down*."

### Demonstration: Overview

In this demonstration, we're going to do the following:

- Deploy a `k3d` Kubernetes cluster
- Deploy **Buoyant Enterprise for Linkerd** with **HAZL** disabled
- Deploy the **Colorwheel** application to generate multi-zonal traffic
- Monitor traffic from the **Colorwheel** application, with **HAZL** disabled
- Enable **High Availability Zonal Load Balancing (HAZL)**
- Monitor traffic from the **Colorwheel** application, with **HAZL** enabled
- Increase the number of requests in the **Colorwheel** application
- Monitor the increased traffic from the **Colorwheel** application
  - Observe the effect on cross-az traffic
- Decrease the number of requests in the **Colorwheel** application
- Monitor the decreased traffic from the **Colorwheel** application
  - Observe the effect on cross-az traffic

### Prerequisites

**If you'd like to follow along, you're going to need the following:**

- [Docker](https://docs.docker.com/get-docker/)
- [k3d](https://k3d.io)
- [step](https://smallstep.com/docs/step-cli/installation/)
- The `watch` command must be installed and working
  - Install procedure varies by operating system

All prerequisites must be *installed* and *working properly* before proceeding.  The instructions in the provided links will get you there.

### The Colorwheel Application

This repository includes the **Colorwheel** application, which generates traffic across multiple availability zones in our Kubernetes cluster, allowing us to observe the effect that **High Availability Zonal Load Balancing (HAZL)** has on traffic.

## Getting Started

### Task 1: Clone the `deploying-bel-with-hazl` Repository

[GitHub: Deploying Buoyant Enterprise for Linkerd with High Availability Zonal Load Balancing (HAZL)](https://github.com/BuoyantIO/service-mesh-academy/tree/main/deploying-bel-with-hazl)

Clone the `BuoyantIO/service-mesh-academy` GitHub repository to your working directory:

```bash
git clone https://github.com/BuoyantIO/service-mesh-academy.git
```

Change directory to the repository:

```bash
cd service-mesh-academy/deploying-bel-with-hazl
```

### Task 2: Deploy a Cluster Using `k3d`

We can use the following commands to have `k3d` create a cluster with 3 availability zones.

Check for existing `k3d` clusters:

```bash
k3d cluster list
```

If you'd like to *delete* any existing clusters, use:

```bash
k3d cluster delete <<cluster-name>>
```

Create the `demo-cluster` cluster, using the configuration file in `cluster/hazl.yaml`:

```bash
k3d cluster create -c cluster/demo-cluster.yaml --wait
```

Check for our `demo-cluster` cluster:

```bash
k3d cluster list
```

Checking out cluster using `kubectl`:

*Nodes:*

```bash
kubectl get nodes
```

*Pods:*

```bash
watch -n 1 kubectl get pods -A -o wide --sort-by .metadata.namespace
```

### Task 3: Create Certificates

Why do we need certificates?  Explain that here, link to documentation here.

#### Create Certificates Using `step`

[Generating the certificates with `step`](https://linkerd.io/2.14/tasks/generate-certificates/#generating-the-certificates-with-step)

If you'd like to generate your own secure certificates, you can use `step` to do so.

##### Trust Anchor Certificate

If you want to generate your own certificates using `step`, use the `certs` directory:

```bash
cd certs
```

Generate the root certificate with its private key (using step):

```bash
step certificate create root.linkerd.cluster.local ca.crt ca.key \
--profile root-ca --no-password --insecure
```

This generates the `ca.crt` and `ca.key` files. The `ca.crt` file is what you need to pass to the `--identity-trust-anchors-file` option when installing Linkerd with the CLI, and the `identityTrustAnchorsPEM` value when installing the `linkerd-control-plane` chart with Helm.

*Note: We use `--no-password` `--insecure` to avoid encrypting those files with a passphrase.*

For a longer-lived trust anchor certificate, pass the `--not-after` argument to the step command with the desired value (e.g. `--not-after=87600h`).

##### Issuer Certificate and Key

Next, generate the intermediate certificate and key pair that will be used to sign the Linkerd proxies’ CSR.

```bash
step certificate create identity.linkerd.cluster.local issuer.crt issuer.key \
--profile intermediate-ca --not-after 8760h --no-password --insecure \
--ca ca.crt --ca-key ca.key
```

This will generate the `issuer.crt` and `issuer.key` files.

Checking our certificates:

```bash
ls -la
```

Change back to the parent directory:

```bash
cd ..
```

### Task 4: Deploy Buoyant Enterprise for Linkerd Without HAZL

[Buoyant Enterprise for Linkerd: Installation](https://docs.buoyant.io/buoyant-enterprise-linkerd/installation/)

[Buoyant Enterprise for Linkerd Trial](https://docs.buoyant.io/buoyant-enterprise-linkerd/installation/trial/)

Next, we will walk through the process of installing **Buoyant Enterprise for Linkerd**, including **High Availability Zonal Load Balancing (HAZL)**.

#### Step 1: Obtain Buoyant Enterprise for Linkerd (BEL) Trial Credentials

To get credentials for accessing Buoyant Enterprise for Linkerd, go to the [Buoyant Enterprise for Linkerd Installation page](https://enterprise.buoyant.io/start_trial), and follow the instructions.

You should end up with a set of credentials in environment variables like this:

```bash
export API_CLIENT_ID=[CLIENT_ID]
export API_CLIENT_SECRET=[CLIENT_SECRET]
export BUOYANT_LICENSE=[LICENSE]
```

Add these to a file in the root of the repository, named `settings.sh`, plus add a new line with the cluster name, `export CLUSTER_NAME=demo-cluster`, like this:

```bash
export API_CLIENT_ID=[CLIENT_ID]
export API_CLIENT_SECRET=[CLIENT_SECRET]
export BUOYANT_LICENSE=[LICENSE]
export CLUSTER_NAME=demo-cluster
```

Check the contents of the `settings.sh` file:

```bash
more settings.sh
```

Source the file, to load the variables:

```bash
source settings.sh
```

Your credentials have been loaded into environment variables, and we can proceed with installing Buoyant Enterprise Linkerd (BEL).

#### Step 2: Download the BEL CLI

Next, download the **BEL** CLI:

```bash
curl -sL https://enterprise.buoyant.io/install-preview | sh
```

Add the CLI executables to your `$PATH`:

```bash
export PATH=~/.linkerd2/bin:$PATH
```

#### Step 3: Run Pre-Checks

Check the `API_CLIENT_ID` environment variable:

```bash
echo $API_CLIENT_ID
```

Confirm the `API_CLIENT_SECRET` environment variable:

```bash
echo $API_CLIENT_SECRET
```

Confirm the `BUOYANT_LICENSE` environment variable:

```bash
echo $BUOYANT_LICENSE
```

Confirm the `CLUSTER_NAME` environment variable:

```bash
echo $CLUSTER_NAME
```

Validate that your cluster is ready for installation:

```bash
linkerd check --pre
```

#### Step 4: Install BEL Operator Components

We'll use the `linkerd-buoyant` Helm chart to install the operator:

```bash
helm repo add linkerd-buoyant https://helm.buoyant.cloud
helm repo update
```

Now, we can install the BEL operator itself:

```bash
helm install linkerd-buoyant \
  --create-namespace \
  --namespace linkerd-buoyant \
  --set metadata.agentName=cluster1 \
  --set api.clientID=$API_CLIENT_ID \
  --set api.clientSecret=$API_CLIENT_SECRET \
linkerd-buoyant/linkerd-buoyant
```

After the install, wait for the metrics agent to be ready, then run the post-install operator health checks:

```bash
kubectl rollout status daemonset/buoyant-cloud-metrics -n linkerd-buoyant
linkerd buoyant check
```

#### Step 5: Create the Identity Secret



Use the [Linkerd Trust Root CA & Identity Certificates & Keys](https://linkerd.io/2/tasks/generate-certificates/#generating-the-certificates-with-step) to create a Kubernetes Secret that will be used by Helm at runtime. You will need `ca.crt`, `issuer.crt`, and `issuer.key` files.

Generate the `linkerd-identity-secret.yaml` manifest:

```bash
cat <<EOF > linkerd-identity-secret.yaml
apiVersion: v1
data:
  ca.crt: $(base64 < certs/ca.crt | tr -d '\n')
  tls.crt: $(base64 < certs/issuer.crt| tr -d '\n')
  tls.key: $(base64 < certs/issuer.key | tr -d '\n')
kind: Secret
metadata:
  name: linkerd-identity-issuer
  namespace: linkerd
type: kubernetes.io/tls
EOF
```

Create the `linkerd-identity-secret` secret:

```bash
kubectl apply -f linkerd-identity-secret.yaml
```

#### Step 6: Create a Linkerd BEL Operator CRD

Create a CRD config that will be used by the Linkerd BEL operator to install and manage the Linkerd control plane. You will need the `ca.crt` file from above.  This CRD configuration also enables High Availability Zonal Load Balancing (HAZL), using the `- -experimental-endpoint-zone-weights` `experimentalArgs`.  We're going to omit the `- -experimental-endpoint-zone-weights` in the `experimentalArgs` for now, by commenting it out with a `#` in the manifest.

```bash
cat <<EOF > linkerd-control-plane-config.yaml
apiVersion: linkerd.buoyant.io/v1alpha1
kind: ControlPlane
metadata:
  name: linkerd-control-plane
spec:
  components:
    linkerd:
      version: preview-24.1.3
      license: $BUOYANT_LICENSE
      controlPlaneConfig:
        proxy:
          image:
            version: preview-24.1.3-hazl
        identityTrustAnchorsPEM: |
$(sed 's/^/          /' < certs/ca.crt )
        identity:
          issuer:
            scheme: kubernetes.io/tls
        destinationController:
          experimentalArgs:
          # - -experimental-endpoint-zone-weights
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: topology.kubernetes.io/zone
                operator: DoesNotExist
EOF
```

#### Step 7: Install Linkerd

Apply the ControlPlane CRD config to have the Linkerd BEL operator create the Linkerd control plane:

```bash
kubectl apply -f linkerd-control-plane-config.yaml
```

#### Step 8: Verify Linkerd Installation

After the installation is complete, you can watch the deployment of the Control Plane using `kubectl`:

```bash
watch -n 1 kubectl get pods -A -o wide --sort-by .metadata.namespace
```

You can verify the health and configuration of Linkerd by running the `linkerd check` command:

```bash
linkerd check
```

#### Step 9: Create the Dataplane Objects for `linkerd-buoyant`

```bash
kubectl apply -f - <<EOF
---
apiVersion: linkerd.buoyant.io/v1alpha1
kind: DataPlane
metadata:
  name: linkerd-buoyant
  namespace: linkerd-buoyant
spec:
  workloadSelector:
    matchLabels: {}
EOF
```

With that you will see the Linkerd proxy get added to your Buoyant Cloud Agent.  You've successfully installed your trial of Buoyant Enterprise for Linkerd. You can now use Linkerd to manage and secure your Kubernetes applications.

To make adjustments to your Linkerd deployment simply edit and re-apply the previously-created `linkerd-control-plane-config.yaml` CRD config.

#### Step 10: Monitor Buoyant Cloud Metrics Rollout and Check Proxies

```bash
kubectl rollout status daemonset/buoyant-cloud-metrics -n linkerd-buoyant
```

```bash
linkerd check --proxy -n linkerd-buoyant
```

### Deploy the Colorwheel Application

*Let's generate some traffic!*

```bash
kubectl apply -k colorz
```

We can check the status of Colorwheel by watching the rollout:

```bash
watch -n 1 kubectl get pods -A -o wide --sort-by .metadata.namespace
```

### Create Security Policy

Say something about creating Security Policies with BEL here.

Use the `linkerd policy generate` command to have BEL generate policies from observed traffic:
```bash
linkerd policy generate > linkerd-policy.yaml
```

We've put these policies into a manifest in the `linkerd-policy.yaml`.  Let's take a look:
```bash
more linkerd-policy.yaml
```

We see...

Now, let's apply the policies to our cluster:
```bash
kubectl apply -f linkerd-policy.yaml
```

Let's take a look at our new Security Policies in Buoyant Cloud.

## Monitor Traffic Without HAZL

Let's take a look at traffic flow without HAZL enabled.

### Using Buoyant Cloud

Let's take a look at what traffic looks like in Buoyant Cloud.  This will give us a more visual representation of our baseline traffic.

## Enable High Availability Zonal Load Balancing (HAZL)

Let's take a look at how quick and easy we can enable High Availability Zonal Load Balancing (HAZL).

Remember, to make adjustments to your Linkerd deployment simply edit and re-apply the previously-created `linkerd-control-plane-config.yaml` CRD config.  We're going to enable the `- -experimental-endpoint-zone-weights` in the `experimentalArgs` for now, by uncommenting it in the manifest:

Edit the `linkerd-control-plane-config.yaml` file:

```bash
vim linkerd-control-plane-config.yaml
```

Apply the ControlPlane CRD config to have the Linkerd BEL operator update the Linkerd control plane configuration, and enable HAZL:

```bash
kubectl apply -f linkerd-control-plane-config.yaml
```

Now, we can see the effect HAZL has on the traffic in our multi-az cluster.

## Monitor Traffic With HAZL Enabled

Let's take a look at what traffic looks like with HAZL enabled.

### Using Buoyant Cloud

Let's take a look at what traffic looks like in Buoyant Cloud.  This will give us a more visual representation of the effect of HAZL on our traffic.

## Increase Number of Requests

### Monitor Traffic Using Buoyant Cloud

Let's take a look at what traffic looks like in Buoyant Cloud.  This will give us a more visual representation of the effect of HAZL on our traffic.

## Summary


