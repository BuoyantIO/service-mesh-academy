# Deploying Buoyant Enterprise for Linkerd (BEL) With High Availability Zonal Load Balancing (HAZL)

## deploying-bel-with-hazl

### Jason Morgan | Tom Dean | Buoyant

### Last edit: 2/3/2024

## Introduction

In this *hands-on demonstration*, we will deploy Buoyant **Enterprise for Linkerd** on a `k3d` Kubernetes cluster and will demonstrate how to quickly enable **High Availability Zonal Load Balancing (HAZL)**.  We'll then take a look at how **HAZL** works to keep network traffic in-zone where possible, and explore Security Policy generation.

Feel free to follow along with *your own instance* if you'd like, using the resources and instructions provided in this repository.

### What is Buoyant Enterprise for Linkerd (BEL)

[Buoyant Enterprise for Linkerd](https://buoyant.io/enterprise-linkerd)

**Buoyant Enterprise for Linkerd** is an enterprise-grade service mesh for Kubernetes. It makes Kubernetes applications **reliable**, **secure**, and **cost-effective** *without requiring any changes to application code*. Buoyant Enterprise for Linkerd contains all the features of open-source Linkerd, the world's fastest, lightest service mesh, plus *additional* enterprise-only features such as:

- High Availability Zonal Load Balancing (HAZL)
- Security Policy Generation
- FIPS-140-2/3 Compliance
- Lifecycle Automation
- Enterprise-Hardened Images
- Software Bills of Materials (SBOMs)
- Strict SLAs Around CVE Remediation

We're going to try out **Security Policy Generation** and **HAZL** in this demo, but remember that we'll get all the **BEL** features, ***except for FIPS***, which isn't included in our Trial license.

### What is High Availability Zonal Load Balancing (HAZL)?

**High Availability Zonal Load Balancing (HAZL)** is a dynamic request-level load balancer in **Buoyant Enterprise for Linkerd** that balances **HTTP** and **gRPC** traffic in environments with **multiple availability zones**. For Kubernetes clusters deployed across multiple zones, **HAZL** can **dramatically reduce cloud spend by minimizing cross-zone traffic**.

Unlike other zone-aware options that use **Topology Hints** (including **Istio** and open source **Linkerd**), **HAZL** *never sacrifices reliability to achieve this cost reduction*.

In **multi-zone** environments, **HAZL** can:

- **Cut cloud spend** by eliminating cross-zone traffic both within and across cluster boundaries;
- **Improve system reliability** by distributing traffic to additional zones as the system comes under stress;
- **Prevent failures before they happe** by quickly reacting to increases in latency before the system begins to fail.
- **Preserve zone affinity for cross-cluster calls**, allowing for cost reduction in multi-cluster environments.

Like **Linkerd** itself, **HAZL** is designed to *"just work"*. It works without operator involvement, can be applied to any Kubernetes service that speaks **HTTP** / **gRPC** regardless of the number of endpoints or distribution of workloads and traffic load across zones, and in the majority of cases *requires no tuning or configuration*.

### How High Availability Zonal Load Balancing (HAZL) Works

For every endpoint, **HAZL** maintains a set of data that includes:

- The **zone** of the endpoint
- The **cost** associated with that zone
- The **recent latency** of responses to that endpoint
- The **recent failure rate** of responses to that endpoint

For every service, **HAZL** continually computes a load metric measuring the utilization of the service. When load to a service falls outside the acceptable range, whether through failures, latency, spikes in traffic, or any other reason, **HAZL** dynamically adds additional endpoints from other zones. When load returns to normal, **HAZL** automatically shrinks the load balancing pool to just in-zone endpoints.

In short: under normal conditions, **HAZL** keeps all traffic within the zone, but when the system is under stress, **HAZL** will temporarily allow cross-zone traffic until the system returns to normal. We'll see this in the **HAZL** demonstration.

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

**In this demonstration, we're going to do the following:**

- Deploy a `k3d` Kubernetes cluster
- Deploy **Buoyant Enterprise for Linkerd** with **HAZL** disabled on the cluster
- Deploy the **Colorwheel** application to the cluster, to generate multi-zonal traffic
  - Monitor traffic from the **Colorwheel** application, with **HAZL** disabled
- Enable **High Availability Zonal Load Balancing (HAZL)**
  - Monitor traffic from the **Colorwheel** application, with **HAZL** enabled
  - Observe the effect on cross-az traffic
- Increase the number of requests in the **Colorwheel** application
  - Monitor the increased traffic from the **Colorwheel** application
  - Observe the effect on cross-az traffic
- Decrease the number of requests in the **Colorwheel** application
  - Monitor the decreased traffic from the **Colorwheel** application
  - Observe the effect on cross-az traffic

### Demo: Prerequisites

**If you'd like to follow along, you're going to need the following:**

- [Docker](https://docs.docker.com/get-docker/)
- [k3d](https://k3d.io)
- [step](https://smallstep.com/docs/step-cli/installation/)
- The `watch` command must be installed and working
- [Buoyant Enterprise for Linkerd License](https://enterprise.buoyant.io/start_trial)
- [The Demo Assets, from GitHub](https://github.com/BuoyantIO/service-mesh-academy/tree/main/deploying-bel-with-hazl)

All prerequisites must be *installed* and *working properly* before proceeding. The instructions in the provided links will get you there. A trial license for Buoyant Enterprise for Linkerd can be obtained from the link above. Instructions on obtaining the demo assets from GitHub are below.

### Demo: Included Scripts

There are three `bel-demo-*` shell scripts provided with the repository, if you'd like to use CLI automation to work through the demonstration.

```bash
Contents of service-mesh-academy/deploying-bel-with-hazl:

.
├── README.md
├── bel-demo-full-repo.sh
├── bel-demo-install.sh
├── bel-demo-hazl-policy.sh
├── certs
├── cluster
├── colorz
└── demo-magic.sh
```

**Available Scripts:**

- `bel-demo-full-repo.sh`
  - Walks through the full repository, all steps demonstrated
- `bel-demo-install.sh`
  - Deploys the k3d cluster for you, walks through **BEL** install, **HAZL** and **policy** demonstration steps
- `bel-demo-hazl-policy.sh`
  - Deploys the k3d cluster and **BEL** without **HAZL** for you, walks through **HAZL** and **policy** demonstration steps

These scripts leverage the `demo-magic.sh` script. There's no need to call `demo-magic.sh` directly.

To execute a script, using the `full-repo` script as an example, use:

```bash
./bel-demo-full-repo.sh
```

For more information, look at the scripts.

### The Colorwheel Application

This repository includes the **Colorwheel** application, which generates traffic across multiple availability zones in our Kubernetes cluster, allowing us to observe the effect that **High Availability Zonal Load Balancing (HAZL)** has on traffic.

## Demo 1: Deploy a Kubernetes Cluster With Buoyant Enterprise for Linkerd, With HAZL Disabled

First, we'll deploy a Kubernetes cluster using `k3d` and deploy Buoyant Enterprise for Linkerd (BEL).

### Task 1: Clone the `deploying-bel-with-hazl` Repository

[GitHub: Deploying Buoyant Enterprise for Linkerd with High Availability Zonal Load Balancing (HAZL)](https://github.com/BuoyantIO/service-mesh-academy/tree/main/deploying-bel-with-hazl)

To get the resources we will be using in this demonstration, you will need to clone a copy of the GitHub `BuoyantIO/service-mesh-academy` repository. We'll be using the materials in the `service-mesh-academy/deploying-bel-with-hazl` subdirectory.

Clone the `BuoyantIO/service-mesh-academy` GitHub repository to your working directory:

```bash
git clone https://github.com/BuoyantIO/service-mesh-academy.git
```

Change directory to the `deploying-bel-with-hazl` subdirectory in the `service-mesh-academy` repository:

```bash
cd service-mesh-academy/deploying-bel-with-hazl
```

Taking a look at the contents of `service-mesh-academy/deploying-bel-with-hazl`:

```bash
ls -la
```

You should see the following:

```bash
total 112
drwxrwxr-x   9 tdean  staff    288 Feb  3 13:47 .
drwxr-xr-x  23 tdean  staff    736 Feb  2 13:05 ..
-rw-r--r--   1 tdean  staff  21495 Feb  3 13:43 README.md
-rwxr-xr-x   1 tdean  staff   9367 Feb  2 13:37 bel-demo-full-repo.sh
-rwxr-xr-x   1 tdean  staff  12581 Feb  2 13:37 bel-demo-hazl-policy.sh
-rwxr-xr-x   1 tdean  staff  12581 Feb  2 13:37 bel-demo-install.sh
drwxr-xr-x   3 tdean  staff     96 Feb  2 13:14 certs
drwxr-xr-x   3 tdean  staff     96 Feb  2 13:14 cluster
drwxr-xr-x   9 tdean  staff    288 Feb  2 13:14 colorz
-rwxr-xr-x   1 tdean  staff   3963 Feb  2 13:14 demo-magic.sh
```

With the assets in place, we can proceed to creating a cluster with `k3d`.

### Task 2: Deploy a Kubernetes Cluster Using `k3d`

Before we can deploy **Buoyant Enterprise for Linkerd**, we're going to need a Kubernetes cluster. Fortunately, we can use `k3d` for that.  There's a cluster configuration file in the `cluster` directory, that will create a cluster with one control plane and three worker nodes, in three different availability zones.

We can use the following commands to have `k3d` create a cluster with 3 availability zones.

Check for existing `k3d` clusters:

```bash
k3d cluster list
```

If you'd like to *delete* any existing clusters you might have, use:

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

Now that we have a Kubernetes cluster, we can proceed with deploying Buoyant Enterprise for Linkerd.

### Task 3: Create mTLS Root Certificates

[Generating the certificates with `step`](https://linkerd.io/2.14/tasks/generate-certificates/#generating-the-certificates-with-step)

[Linkerd Trust Root CA & Identity Certificates & Keys](https://linkerd.io/2/tasks/generate-certificates/#generating-the-certificates-with-step)

In order to support **mTLS** connections between *meshed pods*, **Linkerd** needs a **trust anchor certificate** and an **issuer certificate** with its corresponding **key**.

Since we're using **Helm** to install **BEL**, it’s not possible to automatically generate these certificates and keys. We'll need to generate certificates and keys, and we'll use `step`.

#### Create Certificates Using `step`

You can generate these certificates using a tool like `openssl` or `step`. All certificates must use the ECDSA P-256 algorithm which is the default for step. To generate ECDSA P-256 certificates with openssl, you can use the `openssl ecparam -name prime256v1` command. In this section, we’ll walk you through how to to use the `step` CLI to do this.

##### Step 1: Trust Anchor Certificate

To generate your certificates using `step`, use the `certs` directory:

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

##### Step 2: Issuer Certificate and Key

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

We should see:

```bash
total 40
drwxr-xr-x   7 tdean  staff  224 Feb  2 13:23 .
drwxr-xr-x  10 tdean  staff  320 Feb  3 16:53 ..
-rw-r--r--   1 tdean  staff   53 Feb  2 13:18 README.md
-rw-------   1 tdean  staff  599 Feb  2 13:23 ca.crt
-rw-------   1 tdean  staff  227 Feb  2 13:23 ca.key
-rw-------   1 tdean  staff  648 Feb  2 13:23 issuer.crt
-rw-------   1 tdean  staff  227 Feb  2 13:23 issuer.key
```

Change back to the parent directory:

```bash
cd ..
```

Now that we have mTLS root certificates, we can deploy BEL.

### Task 4: Deploy Buoyant Enterprise for Linkerd With HAZL Disabled

[Installation: Buoyant Enterprise for Linkerd with Buoyant Cloud](https://docs.buoyant.io/buoyant-enterprise-linkerd/installation/managed-bel-cloud-install/)

[Installation: Buoyant Enterprise for Linkerd Trial](https://docs.buoyant.io/buoyant-enterprise-linkerd/installation/trial/)

Next, we will walk through the process of installing **Buoyant Enterprise for Linkerd**. We're going to start with **HAZL** disabled, and will enable **HAZL** during testing.

#### Step 1: Obtain Buoyant Enterprise for Linkerd (BEL) Trial Credentials

To get credentials for accessing Buoyant Enterprise for Linkerd, [sign up here](https://enterprise.buoyant.io/start_trial), and follow the instructions.

You should end up with a set of credentials in environment variables like this:

```bash
export API_CLIENT_ID=[CLIENT_ID]
export API_CLIENT_SECRET=[CLIENT_SECRET]
export BUOYANT_LICENSE=[LICENSE]
```

Add these to a file in the root of the `service-mesh-academy/deploying-bel-with-hazl` directory, named `settings.sh`, plus add a new line with the cluster name, `export CLUSTER_NAME=demo-cluster`, like this:

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

Once you're satisfied with the contents, `source` the file, to load the variables:

```bash
source settings.sh
```

Your credentials have been loaded into environment variables, and we can proceed with installing **Buoyant Enterprise Linkerd (BEL)**.

#### Step 2: Download the BEL CLI

We'll be using the **Buoyant Enterprise Linkerd** CLI for many of our operations, so we'll need it *installed and properly configured*.

First, download the **BEL** CLI:

```bash
curl -sL https://enterprise.buoyant.io/install-preview | sh
```

Add the CLI executables to your `$PATH`:

```bash
export PATH=~/.linkerd2/bin:$PATH
```

Let's give the CLI a quick check:

```bash
linkerd version
```

We should see the following:

```bash
Client version: preview-24.1.5
Server version: unavailable
```

With the CLI installed and working, we can get on with running our pre-installation checks.

#### Step 3: Run Pre-Installation Checks

Before we run the pre-checks, we'll double-check our environment variables.

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

Use the `linkerd check --pre` command to validate that your cluster is ready for installation:

```bash
linkerd check --pre
```

We should see all green checks:

```bash
kubernetes-api
--------------
√ can initialize the client
√ can query the Kubernetes API

kubernetes-version
------------------
√ is running the minimum Kubernetes API version

pre-kubernetes-setup
--------------------
√ control plane namespace does not already exist
√ can create non-namespaced resources
√ can create ServiceAccounts
√ can create Services
√ can create Deployments
√ can create CronJobs
√ can create ConfigMaps
√ can create Secrets
√ can read Secrets
√ can read extension-apiserver-authentication configmap
√ no clock skew detected

linkerd-version
---------------
√ can determine the latest version
√ cli is up-to-date

Status check results are √
```

With everything good and green, we can proceed with installing the **BEL operator**.

#### Step 4: Install BEL Operator Components

Next, we'll install the **BEL operator**, which we will use to deploy the **ControlPlane** and **DataPlane** objects.

Add the `linkerd-buoyant` Helm chart, and refresh **Helm** before installing the operator:

```bash
helm repo add linkerd-buoyant https://helm.buoyant.cloud
helm repo update
```

Now, we can install the **BEL operator** itself:

```bash
helm install linkerd-buoyant \
  --create-namespace \
  --namespace linkerd-buoyant \
  --set metadata.agentName=cluster1 \
  --set api.clientID=$API_CLIENT_ID \
  --set api.clientSecret=$API_CLIENT_SECRET \
linkerd-buoyant/linkerd-buoyant
```

You should see something like the following:

```bash
NAME: linkerd-buoyant
LAST DEPLOYED: Sat Feb  3 17:40:38 2024
NAMESPACE: linkerd-buoyant
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
Thank you for installing linkerd-buoyant.

Your release is named linkerd-buoyant.

To help you manage linkerd-buoyant, you can install the CLI extension by
running:

  curl -sL https://buoyant.cloud/install | sh

Alternatively, you can download the CLI directly via the linkerd-buoyant
releases page:

  https://github.com/BuoyantIO/linkerd-buoyant/releases

To make sure everything works as expected, run the following:

  linkerd-buoyant check

Looking for more? Visit https://buoyant.io/linkerd
```

After the install, wait for the `buoyant-cloud-metrics` agent to be ready, then run the post-install operator health checks:

```bash
kubectl rollout status daemonset/buoyant-cloud-metrics -n linkerd-buoyant
linkerd buoyant check
```

```bash
daemon set "buoyant-cloud-metrics" successfully rolled out
linkerd-buoyant
---------------
√ Linkerd health ok
√ Linkerd vulnerability report ok
√ Linkerd data plane upgrade assistance ok
√ Linkerd trust anchor rotation assistance ok

linkerd-buoyant-agent
---------------------
√ linkerd-buoyant can determine the latest version
√ linkerd-buoyant cli is up-to-date
√ linkerd-buoyant Namespace exists
√ linkerd-buoyant Namespace has correct labels
√ agent-metadata ConfigMap exists
√ buoyant-cloud-org-credentials Secret exists
√ buoyant-cloud-org-credentials Secret has correct labels
√ buoyant-cloud-agent ClusterRole exists
√ buoyant-cloud-agent ClusterRoleBinding exists
√ buoyant-cloud-agent ServiceAccount exists
√ buoyant-cloud-agent Deployment exists
√ buoyant-cloud-agent Deployment is running
‼ buoyant-cloud-agent Deployment is injected
    could not find proxy container for buoyant-cloud-agent-57d767d88b-bl65r pod
    see https://linkerd.io/checks#l5d-buoyant for hints
√ buoyant-cloud-agent Deployment is up-to-date
√ buoyant-cloud-agent Deployment is running a single pod
√ buoyant-cloud-metrics DaemonSet exists
√ buoyant-cloud-metrics DaemonSet is running
‼ buoyant-cloud-metrics DaemonSet is injected
    could not find proxy container for buoyant-cloud-metrics-cmq8r pod
    see https://linkerd.io/checks#l5d-buoyant for hints
√ buoyant-cloud-metrics DaemonSet is up-to-date
√ linkerd-control-plane-operator Deployment exists
√ linkerd-control-plane-operator Deployment is running
√ linkerd-control-plane-operator Deployment is up-to-date
√ linkerd-control-plane-operator Deployment is running a single pod
√ controlplanes.linkerd.buoyant.io CRD exists
√ linkerd-data-plane-operator Deployment exists
√ linkerd-data-plane-operator Deployment is running
√ linkerd-data-plane-operator Deployment is up-to-date
√ linkerd-data-plane-operator Deployment is running a single pod
√ dataplanes.linkerd.buoyant.io CRD exists

Status check results are √
```

We may see a few warnings (!!), but we're good to procced as long as the overall status check results are good.

#### Step 5: Create the Identity Secret

[Linkerd Trust Root CA & Identity Certificates & Keys](https://linkerd.io/2/tasks/generate-certificates/#generating-the-certificates-with-step)

Now we're going to take those **certificates** and **keys** we created using `step`, and use the `ca.crt`, `issuer.crt`, and `issuer.key` to create a Kubernetes Secret that will be used by **Helm** at runtime.

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

Create the `linkerd-identity-secret` secret from the manifest:

```bash
kubectl apply -f linkerd-identity-secret.yaml
```



```bash
kubectl get secrets -A
```

We should see our `linkerd-identity-secret` secret.

```bash

```



Now that we have our `linkerd-identity-issuer` secret, we can proceed with creating the ControlPlane CRD configuration manifest.

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
      version: preview-24.1.5
      license: $BUOYANT_LICENSE
      controlPlaneConfig:
        proxy:
          image:
            version: preview-24.1.5-hazl
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

#### Step 9: Create the DataPlane Objects for `linkerd-buoyant`

```bash
cat <<EOF > linkerd-data-plane-config.yaml
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

Apply the DataPlane CRD configuration to have the **BEL** operator create the Control Plane:

```bash
kubectl apply -f linkerd-data-plane-config.yaml
```

With that you will see the proxy get added to your **Buoyant Cloud Agent**.  You've successfully installed **Buoyant Enterprise for Linkerd**. You can now use **BEL** to manage and secure your Kubernetes applications.

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


