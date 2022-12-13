# mTLS workshop

In the demo part of the workshop, we will deploy Linkerd to a cluster, inject
some example workloads and then verify mTLS between two parties (i.e a client
and a server) works correctly.

In this repository, you will find provisioning scripts: `install` will create a
k3d cluster and install Linkerd, `deploy` will curl, inject and deploy
`emojivoto`, an example application.

All manifests used in the demo are in the `/manifests` directory, for some
additional work after the workshop, check out the [homework
assignment](./HOMEWORK.md).

## Verifying TLS

To verify TLS, we'll make use of `tshark`. The easiest way to get this up and
running is through [linkerd's debug
sidecar](https://linkerd.io/2.11/tasks/using-the-debug-container/). You can
enable the debug sidecar with the following annotation
`config.linkerd.io/enable-debug-sidecar`. The annotation should go on the pod,
or in the pod template of the parent workload (e.g a deployment).

In the demo, we will verify the connection is secure by using two example
workloads: a [curl](manifests/curl.yaml) pod and an
[nginx](manifests/nginx-deploy.yaml) pod. The verification consists of three steps:

1. Inject the curl pod and exec into the container.

```sh
$ kubectl get deploy curl -o yaml \
| linkerd inject - \
| kubectl apply -f -

deployment "curl" injected

deployment.apps/curl configured

$ kubectl exec <curl-pod> -it -c curl -- bin/sh
/ $
```

2. Exec into the nginx debug sidecar (included in the manifest), _do not inject_ yet.

```sh
$ kubectl exec <nginx-pod> -it -c linkerd-debug -- bin/bash

# Run 'tshark' on port 80, you can choose 'any' interface
# or be more specific with 'eth0'. On port 80, filter for
# 'ssl'.
#
/ $ tshark -i any -d tcp.port==80,ssl
<tshark will start capturing packets>

# From a separate session where you exec'd into the
# curl pod, curl the nginx service to receive some
# traffic. 
#
/ $ curl http://nginx-deploy.default.svc.cluster.local:80
<response from nginx>


# Back in our tshark session, we can now inspect the packets.
# Notice the patterns in the traffic,
# after the 3-way handshake (SYN, SYN ACK, ACK),
# we can see the communication in plaintext.
# We can tell by looking at what 'curl' sends,
# the HTTP path, version and method.
#
<tshark output>:

  3 0.000047707   10.42.0.19 ? 10.42.0.24   TCP 76 44028 ? 80 [SYN] Seq=0 Win=42300 Len=0 MSS=1410 SACK_PERM=1 TSval=552641815 TSecr=0 WS=256
  4 0.000054174 fe:5b:47:39:3b:a5 ?              ARP 44 Who has 10.42.0.19? Tell 10.42.0.24
  5 0.000055599 fe:5b:47:39:3b:a5 ?              ARP 44 Who has 10.42.0.19? Tell 10.42.0.24
  6 0.000066154 06:ad:12:c1:48:3e ?              ARP 44 10.42.0.19 is at 06:ad:12:c1:48:3e
  7 0.000067045   10.42.0.24 ? 10.42.0.19   TCP 76 80 ? 44028 [SYN, ACK] Seq=0 Ack=1 Win=43338 Len=0 MSS=1410 SACK_PERM=1 TSval=1583396834 TSecr=552641815 WS=256
  8 0.000076891   10.42.0.19 ? 10.42.0.24   TCP 68 44028 ? 80 [ACK] Seq=1 Ack=1 Win=42496 Len=0 TSval=552641815 TSecr=1583396834
  9 0.000103333   10.42.0.19 ? 10.42.0.24   HTTP 174 GET / HTTP/1.1
 10 0.000105622   10.42.0.24 ? 10.42.0.19   TCP 68 80 ? 44028 [ACK] Seq=1 Ack=107 Win=43264 Len=0 TSval=1583396834 TSecr=552641815
 11 0.000205260   10.42.0.24 ? 10.42.0.19   TCP 306 HTTP/1.1 200 OK  [TCP segment of a reassembled PDU]
 12 0.000219695   10.42.0.19 ? 10.42.0.24   TCP 68 44028 ? 80 [ACK] Seq=107 Ack=239 Win=42496 Len=0 TSval=552641815 TSecr=1583396834
```

3. Inject nginx and follow the same steps from (2).

```sh
$ kubectl get deploy nginx-deploy -o yaml \ 
| linkerd inject - \
| kubectl apply -f -

deployment "nginx-deploy" injected

deployment.apps/nginx-deploy configured

# Here, we add grep -v to exclude any packets sent over loopback,
# since these packets will be in plaintext.
#
$ kubectl exec <nginx-pod> -it -c linkerd-debug -- bin/bash
/ $ tshark -i any -d tcp.port==80,ssl | grep -v 127.0.0.1

# Send a request from curl pod.
# Notice in this case, we no longer get the 'HTTP' protocol in the protocol
# column. Also, we can no longer see the HTTP method, path or protocol being
# used at all. Instead, we see the TCP handshake (starting with ClientHello ACK
# and ServerHello ACK). All other data is encrypted and appears simply as
# "Application Data".
#
 111 33.777715285   10.42.0.26 → 10.42.0.25   TCP 76 40596 → 80 [SYN] Seq=0 Win=42300 Len=0 MSS=1410 SACK_PERM=1 TSval=2319443406 TSecr=0 WS=256
  112 33.777722877   10.42.0.25 → 10.42.0.26   TCP 76 80 → 40596 [SYN, ACK] Seq=0 Ack=1 Win=43338 Len=0 MSS=1410 SACK_PERM=1 TSval=798484464 TSecr=2319443406 WS=256
  113 33.777729869   10.42.0.26 → 10.42.0.25   TCP 68 40596 → 80 [ACK] Seq=1 Ack=1 Win=42496 Len=0 TSval=2319443406 TSecr=798484464
  114 33.777787787   10.42.0.26 → 10.42.0.25   TLSv1 346 Client Hello
  115 33.777793040   10.42.0.25 → 10.42.0.26   TCP 68 80 → 40596 [ACK] Seq=1 Ack=279 Win=43264 Len=0 TSval=798484464 TSecr=2319443406
  116 33.777924193   10.42.0.25 → 10.42.0.26   TLSv1.3 1421 Server Hello, Change Cipher Spec, Application Data, Application Data, Application Data, Application Data, Application Data
  117 33.777936633   10.42.0.26 → 10.42.0.25   TCP 68 40596 → 80 [ACK] Seq=279 Ack=1354 Win=42496 Len=0 TSval=2319443406 TSecr=798484464
  118 33.778129936   10.42.0.26 → 10.42.0.25   TLSv1.3 1170 Change Cipher Spec, Application Data, Application Data, Application Data
  119 33.778146421   10.42.0.26 → 10.42.0.25   TLSv1.3 114 Application Data
```

### An easier way to verify mTLS using BCloud
---

The first method works well for demonstration purposes, but in a real,
production cluster, you might lack the necessary permissions to deploy an
uninjected workload with a debug sidecar container -- tshark, after all,
requires elevated privileges.

To verify uninjected workloads, you have a couple of options:

- Use tools, such as [ksniff](https://github.com/eldadru/ksniff). This adds the
  overhead of learning and running more tools, you might also get surprises if
  your account isn't authorized to do much in the cluster.
- Use k8s primitives, such as [ephemeral
  containers](https://kubernetes.io/docs/concepts/workloads/pods/ephemeral-containers/).
  This will require turning the relevant feature gates on, which is hard to do
  at runtime and is done prior to a cluster being provisioned.
- Inject a debug/network tool sidecar, exactly what we did in the demo.

To verify injected workloads, you can rely on the debug sidecar. However, once
a pod is injected with the debug sidecar, it has to be restarted for the
changes to take effect. Once you're done, you have to remember to take the
annotation out and again, restart your application. Constant rollouts may not
appeal to you, especially when you want to quickly troubleshoot an issue.

Luckily, we can solve both by installing [Buoyant
Cloud](https://buoyant.cloud).  You can install Buoyant cloud as a Linkerd
extension, or directly from the website after sign-up.

```sh
# Installing BCloud as an extension
#
# First, install cli integration.
#
curl -sL buoyant.cloud/install | sh

# Then, install BCloud Agent through
# cli extension.
#
linkerd buoyant install | kubectl apply -f -
```

---

# Recap

## Step 0: environment setup

## Step 1: install Linkerd
```sh

$ curl https://run.linkerd.io/install | sh -

```

## Step 2: curl & nginx deploy
```
$ less manifests/curl.yaml
$ less manifests/nginx-deploy.yaml

$ kubectl apply -f manifests/curl.yaml
$ kubectl apply -f manifests/nginx-deploy.yaml
```

## Step 3: verifying (no) mTLS!

```sh
$ kubectl exec curl -it -- bin/sh
$ kubectl exec nginx -it -c linkerd-debug -- bin/bash

/$ tshark -i any -d tcp.port==80,http # will decode packets to tcp port 80 as http
/$ tshark -s0 -i eth0 -w testcap.pcap 
    # start capture and save to file 
    # -s0 snaplen 0 => full packet is captured
/$ tshark -r testcap.pcap # show raw packet
/$ tshark -r testcap.pcap -V # show packet details
/$ tshark -r testcap.pcap -Px -Y http
   # -P: print summary of packet
   # -x: see ASCII dump (i.e contents of packet)
   # -Y http: filter only http packets
   # man tshark for more

```

## Step 4: deploy Linkerd + certs

```sh
$ kubectl get secret -n linkerd
```

## Step 5: are TLS'd yet?

```sh
# same steps as 3
```

## Step 6: bonus content

Buoyant Cloud to verify TLS!
