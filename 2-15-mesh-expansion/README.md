<!--
SPDX-FileCopyrightText: 2024 Buoyant Inc.
SPDX-License-Identifier: Apache-2.0

SMA-Description: Using Linkerd 2.15 to expand a service mesh to workloads outside of Kubernetes
-->

# Mesh Expansion with Linkerd

Mesh expansion is all about being able to have workloads in a Kubernetes
cluster using a service mesh - Linkerd, in our case! - to communicate with
workloads outside the cluster securely, reliably, and with good observability.

To make this happen, there are several important details to make certain of:

1. The Linkerd control plane needs to be running in the Kubernetes cluster.

2. The Linkerd proxy needs to be running beside each external workload, and
   the proxy needs to intercept network communications to and from the
   workload.

   At the moment, this means that the external workloads need to be running on
   Linux, so that we can use the same packet-filtering tricks to intercept
   network traffic that Linkerd uses in Kubernetes.

3. Each external workload needs a SPIFFE identity, which it will get by having
   its Linkerd proxy talk to a SPIRE agent that's also running next to it.

4. All the SPIRE identities for the external workloads need to be part of a
   trust hierarchy under the trust anchor that the Linkerd control plane is
   using. This implies that the SPIRE agents need to talk to a SPIRE server
   configured to issue keys ultimately signed by the Linkerd trust anchor.

5. The external workloads need to have IP connectivity to Pods in the
   Kubernetes cluster, so that the proxies can connect to the Linkerd control
   plane.

6. The external workloads need to be able to resolve DNS names for Services in
   the Kubernetes cluster.

The way we actually demonstrate doing this here is by building a Docker image
which contains what we need, then running it on the Linux host with `podman`.
It's not strictly necessary to run everything in a container, it just makes it
a _lot_ easier to delivery everything you need and to manage the host's Linux
configuration without accidentally screwing it up.

## THIS IS NOT A PRODUCTION SETUP.

**What you find in this directory is a _demo_ setup, NOT A PRODUCTION SETUP.**

In this directory, you'll find `Dockerfile.demo-external-base`, which will
build an image that's suitable as a base for your own **experimentation**.
**DO NOT USE THIS DOCKERFILE FOR PRODUCTION** or, really, for any real-world
scenario.

`Dockerfile.demo-external-base` includes:

- the Linkerd proxy, copied from your chosen version of Linkerd (currently
  `edge-24.2.5`);
- a SPIRE agent, installed from the SPIRE project's release tarball;
- bootstrap code from `bin/bootstrap`, along with its helper scripts; and
- **a SPIRE server**, which is the biggest reason that this is not suitable
  for real-world use.

In real-world use, the Linkerd proxy would talk to the local SPIRE agent,
which would in turn talk to a properly-configured SPIRE server elsewhere.
Here, we're just running a SPIRE server in the same container as the SPIRE
agent, setting it up to expect to find the trust anchor's public and private
keys in `/opt/spire/certs` so that it can use them to create SPIFFE
identities. **This is a terrible idea in the real world**, but it allows us to
run the demo without getting mired in details of setting up SPIRE.

**Do not do this in any real-world scenario.**

## How `Dockerfile.demo-external-base` works

`bootstrap` sets everything in motion: it's the entrypoint for the
container. It expects certain things set up for it:

- Environment variables `WORKLOAD_NAME` and `WORKLOAD_NAMESPACE` should be set
  to the name and namespace that Kubernetes workloads will use to reach your
  workload (this will match the name and namespace of the ExternalWorkload
  resource you create later). These are used to set up the SPIFFE identity for
  the workload.

- Environment variable `NODE_NAME` should be set to a meaningful name that
  identifies the Linux system running the external workload. This is primarily
  for the use of humans later; setting it to `$(hostname)` is often a simple
  option.

- The trust anchor's public and private keys should be mounted into
  `/opt/spire/certs` in the container. This is how the SPIRE server gets the
  key information that it needs to sign SPIFFE identities.

- The container needs to be able to resolve Kubernetes Service names. Using
  `--dns` to point the container's DNS to a `kube-dns` Service, or a `dnsmasq`
  forwarder that relays `svc.cluster.local` requests to `kube-dns`, is a
  fairly straightforward way to do this.

- The host running the container needs to be able to route directly to Pod IP
  addresses:

  ```bash
  NODE_IP=$(kubectl get nodes  -ojsonpath='{.items[0].status.addresses[0].address}')
  POD_CIDR=$(kubectl get nodes  -ojsonpath='{.items[0].spec.podCIDR}')
  ip route add $POD_CIDR via $NODE_IP
  ```

  This is the only bit of setup we'll be doing on the host itself, rather
  than in the container.

- Finally, you'll need the actual workload in `/workload/start`.

`bootstrap` starts by making sure that all the environment variables are set and that the trust anchor's keys are present, then:

- It starts the SPIRE server and generates an authorization token for the
  SPIRE agent to use.
- It starts the SPIRE agent, passing it the authorization token.
- It uses the SPIRE server to generate a SPIFFE identity for the workload.
- It then starts the workload running in the background.
- It uses `iptables` to intercept network traffic to and from the workload,
  redirecting it to the Linkerd proxy.
- Finally, it starts the Linkerd proxy running.

When the proxy dies, the container will exit.

## Using `Dockerfile.demo-external-base`

`Dockerfile.demo-external-base` is meant to be used as a base image for your
own builds. Buoyant publishes `ghcr.io/buoyantio/demo-external-base:0.2.0` to
make this relatively painless: all you really need to do is to `COPY` your
workload into the image as `/workload/start`.

For example, if your workload has been compiled into a binary called
`my-workload` that listens on port 8000, you might have a `Dockerfile` like
this:

```Dockerfile
ARG BASE=ghcr.io/buoyantio/demo-external-base:0.2.0

FROM $BASE as final
COPY my-workload /workload/start
```

and that is sufficient. If you build this into an image tagged
`my-external-workload:latest`, you might run

```bash
podman run -it --rm --name my-external-workload \
   --dns=some-dns-server \
   --cap-add=NET_ADMIN \
   -v /path/to/trust-anchor-certs:/opt/spire/certs \
   -e WORKLOAD_NAME=my-external-workload \
   -e WORKLOAD_NAMESPACE=default \
   -e NODE_NAME=$(hostname) \
   -p 8000:8000 \
   my-external-workload:latest
```
