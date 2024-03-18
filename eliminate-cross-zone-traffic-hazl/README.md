# Eliminating Cross-Zone Kubernetes Traffic With High Availability Zonal Load Balancing (HAZL)

## eliminate-cross-zone-traffic-hazl

### Tom Dean | Buoyant

### Last edit: 3/18/2024

## Introduction

In this _hands-on workshop_, we will deploy **Buoyant Enterprise for Linkerd** and demonstrate how to enable **High Availability Zonal Load Balancing (HAZL)**. We'll then take a look at how **HAZL** works to keep network traffic _in-zone_ where possible by exploring some different traffic, load and availability situations.

### Buoyant Enterprise for Linkerd (BEL)

[Buoyant Enterprise for Linkerd](https://buoyant.io/enterprise-linkerd)

**Buoyant Enterprise for Linkerd** is an enterprise-grade service mesh for Kubernetes. It makes Kubernetes applications **reliable**, **secure**, and **cost-effective** _without requiring any changes to application code_. Buoyant Enterprise for Linkerd contains all the features of open-source Linkerd, the world's fastest, lightest service mesh, plus _additional_ enterprise-only features such as:

- High-Availability Zonal Load Balancing (HAZL)
- Security Policy Management
- FIPS-140-2/3 Compliance
- Lifecycle Automation
- Buoyant Cloud
- Mesh Expansion

**Plus:**

- Enterprise-Hardened Images
- Software Bills of Materials (SBOMs)
- Strict SLAs Around CVE Remediation
- 24x7x365 Support With SLAs
- Quarterly Outcomes and Strategy Reviews

We're going to try out **High-Availability Zonal Load Balancing (HAZL)** in this workshop.

### High Availability Zonal Load Balancing (HAZL)

**High Availability Zonal Load Balancing (HAZL)** is a dynamic request-level load balancer in **Buoyant Enterprise for Linkerd** that balances **HTTP** and **gRPC** traffic in environments with **multiple availability zones**. For Kubernetes clusters deployed across multiple zones, **HAZL** can **dramatically reduce cloud spend by minimizing cross-zone traffic**.

Unlike other zone-aware options that use **Topology Hints** (including **Istio** and open source **Linkerd**), **HAZL** _never sacrifices reliability to achieve this cost reduction_.

In **multi-zone** environments, **HAZL** can:

- **Cut cloud spend** by eliminating cross-zone traffic both within and across cluster boundaries;
- **Improve system reliability** by distributing traffic to additional zones as the system comes under stress;
- **Prevent failures before they happen** by quickly reacting to increases in latency before the system begins to fail.
- **Preserve zone affinity for cross-cluster calls**, allowing for cost reduction in multi-cluster environments.

Like **Linkerd** itself, **HAZL** is designed to _"just work"_. It works without operator involvement, can be applied to any Kubernetes service that speaks **HTTP** / **gRPC** regardless of the number of endpoints or distribution of workloads and traffic load across zones, and in the majority of cases _requires no tuning or configuration_.

### How High Availability Zonal Load Balancing (HAZL) Works

For every endpoint, **HAZL** maintains a set of data that includes:

- The **zone** of the endpoint
- The **cost** associated with that zone
- The **recent latency** of responses to that endpoint
- The **recent failure rate** of responses to that endpoint

For every service, **HAZL** continually computes a load metric measuring the utilization of the service. When load to a service falls outside the acceptable range, whether through failures, latency, spikes in traffic, or any other reason, **HAZL** dynamically adds additional endpoints from other zones. When load returns to normal, **HAZL** automatically shrinks the load balancing pool to just in-zone endpoints.

In short: under normal conditions, **HAZL** keeps all traffic within the zone, but when the system is under stress, **HAZL** will temporarily allow cross-zone traffic until the system returns to normal. We'll see this in the **HAZL** demonstration.

**HAZL** will also apply these same principles to cross-cluster / multi-cluster calls: it will preserve zone locality by default, but allow cross-zone traffic if necessary to preserve reliability.

### High Availability Zonal Load Balancing (HAZL) vs Topology Hints

**HAZL** was designed in response to limitations seen by customers using Kubernetes's native **Topology Hints** (aka **Topology-aware Routing**) mechanism. These limitations are shared by native Kubernetes balancing (**kubeproxy**) as well as systems such as open source **Linkerd** and **Istio** that make use of **Topology Hints** to make routing decisions.

Within these systems, the endpoints for each service are allocated ahead of time to specific zones by the **Topology Hints** mechanism. This distribution is done at the Kubernetes API level, and attempts to allocate endpoints within the same zone (but note this behavior isn't guaranteed, and the Topology Hints mechanism may allocate endpoints from other zones). Once this allocation is done, it is static until endpoints are added or removed. It does not take into account traffic volumes, latency, or service health (except indirectly, if failing endpoints get removed via health checks).

Systems that make use of **Topology Hints**, including **Linkerd** and **Istio**, use this allocation to decide where to send traffic. This accomplishes the goal of keeping traffic within a zone but at the expense of reliability: **Topology Hints** itself provides no mechanism for sending traffic across zones if reliability demands it. The closest approximation in (some of) these systems are manual failover controls that allow the operator to failover traffic to a new zone.

Finally, **Topology Hints** has a set of well-known constraints, including:

- It does not work well for services where a large proportion of traffic originates from a subset of zones.
- It does not take into account tolerations, unready nodes, or nodes that are marked as control plane or master nodes.
- It does not work well with autoscaling. The autoscaler may not respond to increases in traffic, or respond by adding endpoints in other zones.
- No affordance is made for cross-cluster traffic.

These constraints have real-world implications. As one customer put it when trying **Istio** + **Topology Hints**: "What we are seeing in _some_ applications is that they won’t scale fast enough or at all (because maybe two or three pods out of 10 are getting the majority of the traffic and is not triggering the HPA) and _can cause a cyclic loop of pods crashing and the service going down_."

### Workshop: Overview

In this _hands-on workshop_, we will deploy **Buoyant Enterprise for Linkerd** on a `k3d` Kubernetes cluster and will demonstrate how to quickly enable **High Availability Zonal Load Balancing (HAZL)**. We'll then take a look at how **HAZL** works to keep network traffic _in-zone_ where possible.

**In this demonstration, we're going to do the following:**

- Deploy a `k3d` Kubernetes cluster
- Deploy **Buoyant Enterprise for Linkerd** with **HAZL** disabled on the cluster
- Deploy the **Orders** application to the cluster, to generate multi-zonal traffic
  - Monitor traffic from the **Orders** application, with **HAZL** disabled
- Enable **High Availability Zonal Load Balancing (HAZL)**
  - Monitor traffic from the **Orders** application, with **HAZL** enabled
- Scale traffic in various zones
  - Monitor traffic from the **Orders** application
  - Observe effects of **HAZL**
  - Observe interaction with Horizontal Pod Autoscaling
- Add latency to one zone
  - Monitor traffic from the **Orders** application
  - Observe effects of **HAZL**
  - Observe interaction with Horizontal Pod Autoscaling
- Simulate an outage in one zone
  - Monitor traffic from the **Orders** application
  - Observe effects of **HAZL**
  - Observe interaction with Horizontal Pod Autoscaling
- Restore outage and remove latency
  - Monitor traffic from the **Orders** application
  - Observe effects of **HAZL**
  - Observe interaction with Horizontal Pod Autoscaling
- Restore **Orders** application to initial state

Feel free to follow along with _your own instance_ if you'd like, using the resources and instructions provided in this repository.

### Workshop: Prerequisites

**If you'd like to follow along, you're going to need the following:**

- [Docker](https://docs.docker.com/get-docker/)
- [Helm](https://helm.sh/docs/intro/install/)
- [k3d](https://k3d.io)
- [step](https://smallstep.com/docs/step-cli/installation/)
- The `kubectl` command must be installed and working
- The `watch` command must be installed and working, if you want to use it
- The `kubectx` command must be installed and working, if you want to use it
- [Buoyant Enterprise for Linkerd License](https://enterprise.buoyant.io/start_trial)
- [The Demo Assets, from GitHub](https://github.com/BuoyantIO/service-mesh-academy/tree/main/eliminate-cross-zone-traffic-hazl)

All prerequisites must be _installed_ and _working properly_ before proceeding. The instructions in the provided links will get you there. A trial license for Buoyant Enterprise for Linkerd can be obtained from the link above. Instructions on obtaining the demo assets from GitHub are below.

### Workshop: Included Assets

The top-level contents of the repository look like this:

```bash
.
├── README.md           <-- This README
├── certs               <-- Directory for the TLS root certificates
├── cluster             <-- The k3d cluster configuration files live here
├── cluster_destroy.sh  <-- Script to destroy the cluster environment
├── cluster_setup.sh    <-- Script to stand up the cluster, install Linkerd and Orders
├── images              <-- Images for the README
├── orders -> orders-hpa
├── orders-hpa          <-- The Orders application, with Horizontal Pod Autoscaling
└── orders-nohpa        <-- The Orders application, without Horizontal Pod Autoscaling
```

#### Workshop: Automation

The repository contains the following automation:

- `cluster_setup.sh`
  - Script to stand up the cluster, install Linkerd and Orders
- `cluster_destroy.sh`
  - Script to destroy the cluster environment

If you choose to use the `cluster_setup.sh` script, make sure you've created the `settings.sh` file and run `source settings.sh` to set your environment variables. For more information, see the **Obtain Buoyant Enterprise for Linkerd (BEL) Trial Credentials and Log In to Buoyant Cloud** instructions.

#### Cluster Configurations

This repository contains three `k3d` cluster configuration files:

```bash
.
├── cluster
│   ├── demo-cluster-orders-hazl-large.yaml
│   ├── demo-cluster-orders-hazl-medium.yaml
│   ├── demo-cluster-orders-hazl-small.yaml
│   └── demo-cluster-orders-hazl.yaml -> demo-cluster-orders-hazl-small.yaml
```

By default, `demo-cluster-orders-hazl-small.yaml` is linked to `demo-cluster-orders-hazl.yaml`, so you can just use `demo-cluster-orders-hazl.yaml` if you want a small cluster. We will be using the small cluster in this workshop.

#### The Orders Application

This repository includes the **Orders** application, which generates traffic across multiple availability zones in our Kubernetes cluster, allowing us to observe the effect that **High Availability Zonal Load Balancing (HAZL)** has on traffic.

```bash
.
├── orders -> orders-nohpa
├── orders-hpa
│   ├── kustomization.yaml
│   ├── ns.yaml
│   ├── orders-central.yaml
│   ├── orders-east.yaml
│   ├── orders-west.yaml
│   ├── server.yaml
│   ├── warehouse-boston.yaml
│   ├── warehouse-chicago.yaml
│   └── warehouse-oakland.yaml
└── orders-nohpa
    ├── kustomization.yaml
    ├── ns.yaml
    ├── orders-central.yaml
    ├── orders-east.yaml
    ├── orders-west.yaml
    ├── server.yaml
    ├── warehouse-boston.yaml
    ├── warehouse-chicago.yaml
    └── warehouse-oakland.yaml
```

The repository contains two copies of the Orders application:

- `orders-hpa`: HAZL version of the orders app with Horizontal Pod Autoscaling
- `orders-nohpa`: HAZL version of the orders app without Horizontal Pod Autoscaling

An  `orders` soft link points to the `hpa` version of the application (`orders -> orders-hpa`), with Horizontal Pod Autoscaling.  We will reference the `orders`  soft link in the steps.  If you want to use the `nohpa` version of the application, without Horizontal Pod Autoscaling, deploy the Orders application from the `orders-nohpa` directory, or recreate the `orders` soft link, pointing to the `orders-nohpa` directory.

## Hands-On Exercise 1: Deploy a Kubernetes Cluster With Buoyant Enterprise for Linkerd, With HAZL Disabled

First, we'll deploy a Kubernetes cluster using `k3d` and deploy Buoyant Enterprise for Linkerd (BEL).

### Task 1: Clone the `eliminate-cross-zone-traffic-hazl` Assets

[GitHub: Deploying Buoyant Enterprise for Linkerd with High Availability Zonal Load Balancing (HAZL)](https://github.com/BuoyantIO/service-mesh-academy/tree/main/eliminate-cross-zone-traffic-hazl)

To get the resources we will be using in this demonstration, you will need to clone a copy of the GitHub `BuoyantIO/service-mesh-academy` repository. We'll be using the materials in the `service-mesh-academy/eliminate-cross-zone-traffic-hazl` subdirectory.

Clone the `BuoyantIO/service-mesh-academy` GitHub repository to your preferred working directory:

```bash
git clone https://github.com/BuoyantIO/service-mesh-academy.git
```

Change directory to the `eliminate-cross-zone-traffic-hazl` subdirectory in the `service-mesh-academy` repository:

```bash
cd service-mesh-academy/eliminate-cross-zone-traffic-hazl
```

Taking a look at the contents of `service-mesh-academy/eliminate-cross-zone-traffic-hazl`:

```bash
ls -la
```

With the assets in place, we can proceed to creating a cluster with `k3d`.

### Task 2: Deploy a Kubernetes Cluster Using `k3d`

Before we can deploy **Buoyant Enterprise for Linkerd**, we're going to need a Kubernetes cluster. Fortunately, we can use `k3d` for that. We're going to use the small configuration file in the `cluster` directory, which will create a cluster with one control plane and three worker nodes, in three different availability zones.

Create the `demo-cluster-orders-hazl` cluster, using the configuration file in `cluster/demo-cluster-orders-hazl.yaml`:

```bash
k3d cluster create -c cluster/demo-cluster-orders-hazl.yaml --wait
```

Check for our cluster:

```bash
k3d cluster list
```

Checking our contexts:

```bash
kubectx
```

Let's shorten our context name, for ease of use:

```bash
kubectx hazl=k3d-demo-cluster-orders-hazl
```

Finally, we'll switch to the `hazl` context:

```bash
kubectx hazl
```

Checking our contexts again:

```bash
kubectx
```

Now that we have our Kubernetes cluster and context up and configured, we can proceed with deploying **Buoyant Enterprise for Linkerd** on it.

### Task 3: Create mTLS Root Certificates

[Generating the certificates with `step`](https://linkerd.io/2.14/tasks/generate-certificates/#generating-the-certificates-with-step)

In order to support **mTLS** connections between _meshed pods_, **Linkerd** needs a **trust anchor certificate** and an **issuer certificate** with its corresponding **key**.

Since we're using **Helm** to install **BEL**, it’s not possible to automatically generate these certificates and keys. We'll need to generate certificates and keys, and we'll use `step`for this.

#### Create Certificates Using `step`

You can generate certificates using a tool like `step`. All certificates must use the ECDSA P-256 algorithm which is the default for `step`. In this section, we’ll walk you through how to to use the `step` CLI to do this.

##### Step 1: Generate Trust Anchor Certificate

To generate your certificates using `step`, use the `certs` directory:

```bash
cd certs
```

Generate the root certificate with its private key (using step):

```bash
step certificate create root.linkerd.cluster.local ca.crt ca.key \
--profile root-ca --no-password --insecure
```

_Note: We use `--no-password` `--insecure` to avoid encrypting those files with a passphrase._

This generates the `ca.crt` and `ca.key` files. The `ca.crt` file is what you need to pass to the `--identity-trust-anchors-file` option when installing **Linkerd** with the CLI, and the `identityTrustAnchorsPEM` value when installing the `linkerd-control-plane` chart with Helm.

For a longer-lived trust anchor certificate, pass the `--not-after` argument to the step command with the desired value (e.g. `--not-after=87600h`).

##### Step 2: Generate Intermediate Certificate and Key Pair

Next, generate the intermediate certificate and key pair that will be used to sign the **Linkerd** proxies’ CSR.

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
drwxr-xr-x  7 tdean  staff  224 Mar  4 18:30 .
drwxr-xr-x  8 tdean  staff  256 Mar  4 18:09 ..
-rw-r--r--  1 tdean  staff   55 Mar  4 17:45 README.md
-rw-------  1 tdean  staff  599 Mar  4 18:29 ca.crt
-rw-------  1 tdean  staff  227 Mar  4 18:29 ca.key
-rw-------  1 tdean  staff  652 Mar  4 18:30 issuer.crt
-rw-------  1 tdean  staff  227 Mar  4 18:30 issuer.key
```

Change back to the parent directory:

```bash
cd ..
```

Now that we have **mTLS** root certificates, we can deploy **BEL**.

### Task 4: Deploy Buoyant Enterprise for Linkerd With HAZL Disabled

[Installation: Buoyant Enterprise for Linkerd](https://docs.buoyant.io/buoyant-enterprise-linkerd/latest/installation/)

Next, we will walk through the process of installing **Buoyant Enterprise for Linkerd**. We're going to start with **HAZL** disabled, and will enable **HAZL** during testing.

#### Step 1: Obtain Buoyant Enterprise for Linkerd (BEL) Trial Credentials and Log In to Buoyant Cloud

If you require credentials for accessing **Buoyant Enterprise for Linkerd**, [sign up here](https://enterprise.buoyant.io/start_trial), and follow the instructions.

You should end up with a set of credentials in environment variables like this:

```bash
export API_CLIENT_ID=[CLIENT_ID]
export API_CLIENT_SECRET=[CLIENT_SECRET]
export BUOYANT_LICENSE=[LICENSE]
```

Add these to a file in the root of the `linkerd-demos/demo-orders` directory, named `settings.sh`, plus add a new line with the cluster name, `export CLUSTER_NAME=demo-cluster-orders-hazl`, like this:

```bash
export API_CLIENT_ID=[CLIENT_ID]
export API_CLIENT_SECRET=[CLIENT_SECRET]
export BUOYANT_LICENSE=[LICENSE]
export CLUSTER_NAME=demo-cluster-orders-hazl
```

Check the contents of the `settings.sh` file:

```bash
more settings.sh
```

Once you're satisfied with the contents, `source` the file, to load the variables:

```bash
source settings.sh
```

Now that you have a trial login, open an additional browser window or tab, and open **[Buoyant Cloud](https://buoyant.cloud)**. _Log in with the credentials you used for your trial account_.

![Buoyant Cloud: Add Cluster](images/buoyant-cloud-addcluster.png)

We'll be adding a cluster during **BEL** installation, so go ahead and click 'Cancel' for now.

![Buoyant Cloud: Overview](images/buoyant-cloud-overview.png)

You should find yourself in the Buoyant Cloud Overview page. This page provides summary metrics and status data across all your deployments. We'll be working with **Buoyant Cloud** a little more in the coming sections, so we'll set that aside for the moment.

Our credentials have been loaded into environment variables, we're logged into **Buoyant Cloud**, and we can proceed with installing **Buoyant Enterprise Linkerd (BEL)**.

#### Step 2: Download the BEL CLI

We'll be using the **Buoyant Enterprise Linkerd** CLI for many of our operations, so we'll need it _installed and properly configured_.

First, download the **BEL** CLI:

```bash
curl https://enterprise.buoyant.io/install | sh
```

Add the CLI executables to your `$PATH`:

```bash
export PATH=~/.linkerd2/bin:$PATH
```

Let's give the CLI a quick check:

```bash
linkerd version
```

With the CLI installed and working, we can get on with running our pre-installation checks.

#### Step 3: Run Pre-Installation Checks

Use the `linkerd check --pre` command to validate that your clusters are ready for installation.

```bash
linkerd check --pre
```

We should see all green checks.  With everything good and green, we can proceed with installing the **BEL operator**.

#### Step 4: Install BEL Operator Components

[Kubernetes Docs: Operator Pattern](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/)

Next, we'll install the **BEL operator**, which we will use to deploy the **ControlPlane** and **DataPlane** objects.

Add the `linkerd-buoyant` Helm chart, and refresh **Helm** before installing the operator:

```bash
helm repo add linkerd-buoyant https://helm.buoyant.cloud
helm repo update
```

Deploy the **BEL Operator** to the `hazl` cluster using Helm:

```bash
helm install linkerd-buoyant \
  --create-namespace \
  --namespace linkerd-buoyant \
  --kube-context hazl \
  --set metadata.agentName=$CLUSTER_NAME \
  --set api.clientID=$API_CLIENT_ID \
  --set api.clientSecret=$API_CLIENT_SECRET \
  --set metrics.debugMetrics=true \
  --set agent.logLevel=debug \
  --set metrics.logLevel=debug \
linkerd-buoyant/linkerd-buoyant
```

After the install, wait for the `buoyant-cloud-metrics` agents to be ready, then run the post-install operator health checks.

```bash
kubectl rollout status daemonset/buoyant-cloud-metrics -n linkerd-buoyant
linkerd buoyant check
```

We may see a few warnings (!!), but we're good to proceed _as long as the overall status check results are good_.

#### Step 5: Create the Identity Secret

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

Create the `linkerd-identity-issuer` secret from the `linkerd-identity-secret.yaml` manifest.

```bash
kubectl apply -f linkerd-identity-secret.yaml
```

Let's check the secrets on our cluster.

```bash
kubectl get secrets  -n linkerd
```

Now that we have our `linkerd-identity-issuer` secrets, we can proceed with creating the **ControlPlane CRD** configuration manifest.

#### Step 6: Create a ControlPlane Manifest

[Kubernetes Docs: Custom Resources](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/)

We deploy the **BEL ControlPlane** and **DataPlane** using **Custom Resources**. We'll create a manifest for each that contains the object's configuration. We'll start with the **ControlPlane** first.

This **CRD configuration** also enables **High Availability Zonal Load Balancing (HAZL)**, using the `- -ext-endpoint-zone-weights` `additionalArgs`. We're going to omit the `- -ext-endpoint-zone-weights` in the `additionalArgs` for now, by commenting it out with a `#` in the manifest.

Let's create the ControlPlane manifest for the `hazl` cluster:

```bash
cat <<EOF > linkerd-control-plane-config-hazl.yaml
apiVersion: linkerd.buoyant.io/v1alpha1
kind: ControlPlane
metadata:
  name: linkerd-control-plane
spec:
  components:
    linkerd:
      version: enterprise-2.15.1-1
      license: $BUOYANT_LICENSE
      controlPlaneConfig:
        proxy:
          image:
            version: enterprise-2.15.1-1-hazl
        identityTrustAnchorsPEM: |
$(sed 's/^/          /' < certs/ca.crt )
        identity:
          issuer:
            scheme: kubernetes.io/tls
        destinationController:
          additionalArgs:
           # - -ext-endpoint-zone-weights
EOF
```

Apply the ControlPlane CRD configuration to have the Linkerd BEL operator create the **ControlPlane**.

```bash
kubectl apply -f linkerd-control-plane-config-hazl.yaml
```

To make adjustments to your **BEL ControlPlane** deployment _simply edit and re-apply the `linkerd-control-plane-config-hazl.yaml` manifest_.

#### Step 7: Verify the ControlPlane Installation

After the installation is complete, watch the deployment of the Control Plane using `kubectl`.

```bash
watch -n 1 kubectl get pods -A -o wide --sort-by .metadata.namespace
```

**_Use `CTRL-C` to exit the watch command._**

Checking our work:

```bash
kubectl get controlplane -A
```

Let's verify the health and configuration of Linkerd by running the `linkerd check` command.

```bash
linkerd check
```

Again, we may see a few warnings (!!), but we're good to proceed _as long as the overall status is good_.

#### Step 8: Create the DataPlane Object for the `linkerd-buoyant` Namespace

Now, we can deploy the **DataPlane** for the `linkerd-buoyant` namespace. Let's create the **DataPlane** manifest:

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

Apply the **DataPlane CRD configuration** manifest to have the **BEL operator** create the **DataPlane**.

```bash
kubectl apply -f linkerd-data-plane-config.yaml
```

Checking our work:

```bash
kubectl get dataplane -A
```

#### Step 9: Monitor Buoyant Cloud Metrics Rollout and Check Proxies

Now that both our **BEL ControlPlane** and **DataPlane** have been deployed, we'll check the status of our `buoyant-cloud-metrics` daemonset rollout.

```bash
kubectl rollout status daemonset/buoyant-cloud-metrics -n linkerd-buoyant
```

Once the rollout is complete, we'll use `linkerd check --proxy` command to check the status of our **BEL** proxies.

```bash
linkerd check --proxy -n linkerd-buoyant
```

Again, we may see a few warnings (!!), _but we're good to proceed as long as the overall status is good_.

We've successfully installed **Buoyant Enterprise for Linkerd**, and can now use **BEL** to manage and secure our Kubernetes applications.

## Hands-On Exercise 2: Observe the Effects of High Availability Zonal Load Balancing (HAZL)

Now that **BEL** is fully deployed, we're going to need some traffic to observe.

### Scenario: Hacky Sack Emporium

In this scenario, we're delving into the operations of an online business specializing in Hacky Sack products. This business relies on a dedicated orders application to manage customer orders efficiently and to ensure that these orders are promptly dispatched to warehouses for shipment. To guarantee high availability and resilience, the system is distributed across three geographical availability zones: `zone-east`, `zone-central`, and `zone-west`. This strategic distribution ensures that the system operates smoothly, maintaining a balanced and steady state across different regions.

For the deployment of the Orders application, the business utilizes a modern infrastructure approach by employing Kubernetes. To further enhance the system's reliability and observability, Buoyant's Enterprise Linkerd service mesh is deployed on our cluster. Remember, Linkerd provides critical features such as dynamic request routing, service discovery, and comprehensive monitoring, which are instrumental for maintaining the health and performance of the Orders application across the clusters. Deploying the Orders application to a fresh Kubernetes cluster, augmented with Buoyant Enterprise Linkerd, signifies a significant step towards achieving robust, scalable, and highly available online business operations, ensuring that customers receive their Hacky Sack products without delays.

**_We don't know it yet, but our business, and the magic of hacky sack, are about to be featured on an episode of a popular sitcom tonight and orders are going to spike!_**

### Deploy the Orders Application

The repository contains two copies of the Orders application:

- `orders-hpa`: HAZL version of the orders app with Horizontal Pod Autoscaling
- `orders-nohpa`: HAZL version of the orders app without Horizontal Pod Autoscaling

An  `orders` soft link points to the `hpa` version of the application (`orders -> orders-hpa`), with Horizontal Pod Autoscaling.  We will reference the `orders`  soft link in the steps.  If you want to use the `nohpa` version of the application, without Horizontal Pod Autoscaling, deploy the Orders application from the `orders-nohpa` directory, or recreate the `orders` soft link, pointing to the `orders-nohpa` directory.

Deploy the **Orders** application from the `orders` directory. This will deploy the application with Horizontal Pod Autoscaling.

```bash
kubectl apply -k orders
```

We can check the status of the **Orders** application by watching the rollout.

```bash
watch -n 1 kubectl get pods -n orders -o wide --sort-by .spec.nodeName
```

**_Use `CTRL-C` to exit the watch command._**

Once the application is deployed, you can monitor the status of the Orders deployments and Horizontal Pod Autoscaling using:

```bash
watch -n 1 kubectl get deploy,hpa -n orders
```

You might want to open a terminal and leave this watch command running to keep an eye on the state of our deployments.

**_Use `CTRL-C` to exit the watch command._**

### Create a DataPlane Object for the `orders` Namespace

Now that the Orders application has been deployed, let's create the **DataPlane** manifest for the `orders` namespace:

```bash
cat <<EOF > linkerd-data-plane-orders-config.yaml
---
apiVersion: linkerd.buoyant.io/v1alpha1
kind: DataPlane
metadata:
  name: linkerd-orders
  namespace: orders
spec:
  workloadSelector:
    matchLabels: {}
EOF
```

Apply the **DataPlane CRD configuration** manifest to have the **BEL operator** create the **DataPlane** object for the `orders` namespace.

```bash
kubectl apply -f linkerd-data-plane-orders-config.yaml
```

Checking our work:

```bash
kubectl get dataplane -A
```

With the **Orders** application deployed, we now have some traffic to work with.

### Monitor Traffic Without HAZL Enabled

Let's take a look at traffic flow _without **HAZL** enabled_ in **Buoyant Cloud**. This will give us a more visual representation of our baseline traffic. Head over to **Buoyant Cloud**, and take a look at the contents of the `orders` namespace in the Topology tab.

![Buoyant Cloud: Topology](images/orders-no-hazl-bcloud.png)

![Grafana: HAZL Dashboard](images/orders-no-hazl-grafana.png)

![Deployments / HPA](images/orders-no-hazl-deployments-hpa.png)

We can see that traffic from each `orders` deployment is flowing to all three `warehouse` deployments, and that about 2/3 of total traffic is out of zone. Latency is hovering around 80 ms per zone, and Requests By Warehouse has some variation over time. All deployments are currently scaled to one replica.

**_Let's see what happens when we enable HAZL._**

### Enable High Availability Zonal Load Balancing (HAZL)

Let's take a look at how quick and easy we can enable **High Availability Zonal Load Balancing (HAZL)**.

Remember, to make adjustments to your **BEL** deployment _simply edit and re-apply the previously-created `linkerd-control-plane-config-hazl.yaml` manifest_. We're going to **enable** the `- -ext-endpoint-zone-weights` in the `additionalArgs` for now, by uncommenting it in the manifest:

Edit the `linkerd-control-plane-config-hazl.yaml` file:

```bash
vi linkerd-control-plane-config-hazl.yaml
```

Apply the ControlPlane CRD config to have the Linkerd BEL operator update the Linkerd control plane configuration, and enable HAZL _on the `hazl` cluster only_:

```bash
kubectl apply -f linkerd-control-plane-config-hazl.yaml
```

Now, we can see the effect **HAZL** has on the traffic in our multi-az cluster.

### Monitor Traffic With HAZL Enabled

Let's take a look at what traffic looks like with **HAZL** enabled, using **Buoyant Cloud**. This will give us a more visual representation of the effect of **HAZL** on our traffic.

![Buoyant Cloud: Topology](images/orders-hazl-bcloud.png)

![Grafana: HAZL Dashboard](images/orders-hazl-grafana.png)

![Deployments / HPA](images/orders-hazl-deployments-hpa.png)

With HAZL enabled, we see traffic stay in zone, at 50 requests per second.  Cross-AZ traffic drops to zero, latency by zone drops to around 50 ms and Requests By Warehouse smooths out. Application load stays consistent and all deployments remain at one replica.

### Increase Orders Traffic in `zone-east`

A popular sitcom aired an episode in which the characters, a bunch of middle-aged Generation X folks, flash back to their teenage years, and remember the joy they experienced playing hacky sack together. Our characters decide they're going to relive those wonderful hacky sack memories, and go online to order supplies, featuring _our_ website and products. **_Jackpot!_**

Let's simulate what that looks like. The first thing we see is an uptick of orders in `zone-east`, as they're the first to watch the episode.

We can increase traffic in `zone-east` by scaling the `orders-east` deployment.  Let's scale to 10 replicas.

```bash
kubectl scale -n orders deploy orders-east --replicas=10
```

Let's see the results of scaling `orders-east`:

```bash
watch -n 1 kubectl get deploy,hpa -n orders
```

**_Use `CTRL-C` to exit the watch command._**

Let's take a look at what the increased traffic looks like in **Buoyant Cloud**. This will give us a more visual representation of the effect of **HAZL** on our traffic.

![Buoyant Cloud: Topology](images/orders-hazl-increased-east-bcloud.png)

![Grafana: HAZL Dashboard](images/orders-hazl-increased-east-grafana.png)

After scaling `orders-east` to 10 replicas, traffic remains in the same AZ and latency holds steady at around 50 ms. Order success remains at 100%.

### Increase Orders Traffic in `zone-central`

The middle of the country _really_ liked our hacky sacks! Order volume is running more than double what we saw in `zone-east`.

We can increase traffic in `zone-central` by scaling the `orders-central` deployment.  Let's scale to 25 replicas.

```bash
kubectl scale -n orders deploy orders-central --replicas=25
```

Let's see the results of scaling `orders-central`:

```bash
watch -n 1 kubectl get deploy,hpa -n orders
```

**_Use `CTRL-C` to exit the watch command._**

Let's take a look at what the increased traffic looks like in **Buoyant Cloud**. This will give us a more visual representation of the effect of **HAZL** on our traffic.

![Buoyant Cloud: Topology](images/orders-hazl-increased-central-bcloud.png)

![Grafana: HAZL Dashboard](images/orders-hazl-increased-central-grafana.png)

![Deployments / HPA](images/orders-hazl-increased-central-deployments-hpa.png)

Again, after scaling `orders-central` to 25 replicas, all traffic remains in the same AZ and latency holds steady at around 50 ms. Order success remains at 100%. Both `warehouse-boston` and `warehouse-chicago` have autoscaled to 3 replicas.

### Increase Orders Traffic in `zone-west`

By now, word of the episode is all over social media, and when the episode airs in Pacific time, orders in `zone-west` spike.

We can increase traffic in `zone-west` by scaling the `orders-west` deployment.  Let's scale to 30 replicas.

```bash
kubectl scale -n orders deploy orders-west --replicas=30
```

Let's see the results of scaling `orders-west`:

```bash
watch -n 1 kubectl get deploy,hpa -n orders
```

**_Use `CTRL-C` to exit the watch command._**

Let's take a look at what the increased traffic looks like in **Buoyant Cloud**. This will give us a more visual representation of the effect of **HAZL** on our traffic.

![Buoyant Cloud: Topology](images/orders-hazl-increased-west-bcloud.png)

![Grafana: HAZL Dashboard](images/orders-hazl-increased-west-grafana.png)

![Deployments / HPA](images/orders-hazl-increased-west-deployments-hpa.png)

Once more, after scaling `orders-west` to 30 replicas, all traffic remains in the same AZ and latency holds steady at around 50 ms. Order success remains at 100%. Both `warehouse-boston`, `warehouse-chicago` and `warehouse-oakland` have autoscaled to 3 replicas.

**_So far, everything has gone right. What about when things go wrong?_**

### Increase Latency in `zone-central`

Unfortunately, we've had some network issues creep in at our Chicago warehouse!

We can increase latency in `zone-central` by editing the `warehouse-config` configmap, which has a setting for latency.

```bash
kubectl edit -n orders cm/warehouse-config
```

You'll see:

```yml
data:
  blue.yml: |
    color: "#0000ff"
    averageResponseTime: 0.020
  green.yml: |
    color: "#00ff00"
    averageResponseTime: 0.020
  red.yml: |
    color: "#ff0000"
    averageResponseTime: 0.020
```

The colors map to the warehouses as follows:

- Red: This is the Oakland warehouse (`warehouse-oakland`)
- Blue: This is the Boston warehouse (`warehouse-boston`)
- Green: This is the Chicago warehouse (`warehouse-chicago`)

Change the value of `averageResponseTime` under `green.yml` from `0.020` to `0.120`. Save and exit.

We need to restart the `warehouse-chicago` deployment to pick up the changes:

```bash
kubectl rollout restart -n orders deploy warehouse-chicago
```

Let's take a look at what the increased latency looks like in **Buoyant Cloud**. This will give us a more visual representation of the effect of **HAZL** on our traffic in response to increased latency.

![Buoyant Cloud: Topology](images/orders-hazl-increased-latency-bcloud.png)

![Grafana: HAZL Dashboard](images/orders-hazl-increased-latency-grafana.png)

![Deployments / HPA](images/orders-hazl-increased-latency-deployments-hpa.png)

HAZL steps in and does what it needs to do, redirecting a portion of the traffic from `orders-central` across AZs to `warehouse-oakland` to keep success rate at 100%. Latency increases in `orders-central`, but HAZL adjusts.

### Take the `warehouse-chicago` Deployment Offline in `zone-central`

More bad news! The latency we've been experiencing is about to turn into an outage!

We can simulate this by scaling the `warehouse-chicago` deployment.  Let's scale to 0 replicas.

```bash
kubectl scale -n orders deploy warehouse-chicago --replicas=0
```

Let's see the results of scaling `warehouse-chicago` to 0:

```bash
watch -n 1 kubectl get deploy,hpa -n orders
```

**_Use `CTRL-C` to exit the watch command._**

Let's take a look at what the increased traffic looks like in **Buoyant Cloud**. This will give us a more visual representation of the effect of **HAZL** on our traffic.

![Buoyant Cloud: Topology](images/orders-hazl-chicago-offline-bcloud.png)

![Grafana: HAZL Dashboard](images/orders-hazl-chicago-offline-grafana.png)

![Deployments / HPA](images/orders-hazl-chicago-offline-deployments-hpa.png)

Once again, HAZL steps in and does what it needs to do, redirecting all of the traffic from `orders-central` across AZs to `warehouse-oakland` to keep success rate at 100%. Latency drops in `orders-central` as we are no longer sending traffic to `warehouse-chicago`, which added latency.

### Bring the `warehouse-chicago` Deployment Back Online and Remove Latency

Good news! The latency and outage is about to end!

We can simulate this by scaling the `warehouse-chicago` deployment.  Let's scale to 1 replica. The Horizontal Pod Autoscaler will take over from there.

```bash
kubectl scale -n orders deploy warehouse-chicago --replicas=1
```

We also need to edit the `warehouse-config` configmap, and set the latency to match the other `warehouse` deployments.

```bash
kubectl edit -n orders cm/warehouse-config
```

We need to restart the `warehouse-chicago` deployment to pick up the changes:

```bash
kubectl rollout restart -n orders deploy warehouse-chicago
```

Let's see the results of scaling `warehouse-chicago` and restarting the deployment:

```bash
watch -n 1 kubectl get deploy,hpa -n orders
```

**_Use `CTRL-C` to exit the watch command._**

Let's take a look at what the service restoration looks like in **Buoyant Cloud**. This will give us a more visual representation of the effect of **HAZL** on our traffic.

![Buoyant Cloud: Topology](images/orders-hazl-chicago-restored-bcloud.png)

![Grafana: HAZL Dashboard](images/orders-hazl-chicago-restored-grafana.png)

![Deployments / HPA](images/orders-hazl-chicago-restored-deployments-hpa.png)

We can see things have returned to 100% in-zone traffic, with latency back to about 50 ms across the board and success rates at 100%.  HPA has 3 replicas of the `warehouse` deployments per zone.

### Reset the Orders Application

Now that we're finished, let's reset the Orders application back to its initial state.

```bash
kubectl apply -k orders
```

Let's see the results of the reset:

```bash
watch -n 1 kubectl get deploy,hpa -n orders
```

**_Use `CTRL-C` to exit the watch command._**

If we give things a minute to settle back down, we should see all traffic back in zone and request rates back to 50.

![Buoyant Cloud: Topology](images/orders-hazl-app-reset-bcloud.png)

![Grafana: HAZL Dashboard](images/orders-hazl-app-reset-grafana.png)

![Deployments / HPA](images/orders-hazl-app-reset-deployments-hpa.png)

Everything has returned to the initial state with HAZL enabled. All deployments are a single replica, all traffic remains in-zone, and success rates are 100%.  Looking good!

### Workshop: Cleanup

You can clean up the workshop environment by running the included script:

```bash
./cluster_destroy.sh
```

Checking our work:

```bash
k3d cluster list
```

We shouldn't see our `demo-cluster-orders-hazl` cluster.

## Summary: Deploying the Orders Application With High Availability Zonal Load Balancing (HAZL)

In this hands-on workshop, we deployed Buoyant Enterprise for Linkerd and demonstrated how to enable High Availability Zonal Load Balancing (HAZL). We also took a look at how HAZL works to keep network traffic in-zone where possible by exploring some different traffic, load and availability situations.

Thank you for taking a journey with HAZL and Buoyant!
