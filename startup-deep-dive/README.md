# What really happens at startup: a deep dive into Linkerd, init containers, CNI plugins, and more

This is the README and executable code(!) for the Service Mesh Academy on 17 November 2022. Things in Markdown comments, like the `@import` below, are safe to ignore when reading this later.

<!-- @import demo-tools.sh -->

OK, let's get this show on the road. Non-comment things after the `@SHOW`
directive below are what got shown during the SMA live demo.

<!-- @SHOW -->

## Install Linkerd CLI

We're going to start by explicitly installing Linkerd `edge-22.11.1`,
so that we can take full advantage of the CNI validator that will be
released in Linkerd `stable-2.13`.

```bash
curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install-edge | \
    LINKERD2_VERSION=edge-22.11.1 sh
```

Let's make sure that worked correctly.

```bash
linkerd-edge-22.11.1 version
```

<!-- @wait_clear -->

## Using an Init Container

We'll start by doing a fairly normal cluster creation and install, using an
init container. This will, we hope, be the happy path.

Note that we explicitly tell `k3d` _not_ to deploy Traefik -- it just doesn't
make sense, since we're about to install Linkerd.

```bash
k3d cluster delete startup-init
# -p "80:80@loadbalancer" -p "443:443@loadbalancer"
k3d cluster create startup-init \
    --k3s-arg '--no-deploy=traefik@server:*;agents:*'
```

<!-- @wait_clear -->
Once that's done, let's look around a bit to see what's running.

```bash
kubectl get ns
## NAME              STATUS   AGE
## default           Active   5m20s
## kube-system       Active   5m20s
## kube-public       Active   5m20s
## kube-node-lease   Active   5m20s
```

`default` and `kube-system` are, of course, the usual suspects. The other
two here are because we're running `k3d`.

```bash
kubectl get pods -n kube-system
## NAME                                      READY   STATUS    RESTARTS   AGE
## coredns-b96499967-rgt47                   1/1     Running   0          47s
## local-path-provisioner-7b7dc8d6f5-dnvgh   1/1     Running   0          47s
## metrics-server-668d979685-7swdn           1/1     Running   0          47s
```

These are also typical for a `k3d` cluster.

<!-- @wait_clear -->
OK, let's make sure that Linkerd will be happy with our cluster.

```bash
linkerd-edge-22.11.1 check --pre
```

<!-- @wait_clear -->
So far so good. Next up, let's go ahead and install Linkerd.

All of this is straight out of the Linkerd quickstart so far. We're
not doing anything odd in the slightest (yet).

```bash
linkerd-edge-22.11.1 install --crds | kubectl apply -f -
linkerd-edge-22.11.1 install | kubectl apply -f -
```

Once installed, we of course want to check everything.

```bash
linkerd-edge-22.11.1 check
```

<!-- @wait_clear -->
What does our cluster look like now that Linkerd is running?

```bash
kubectl get ns
## NAME              STATUS   AGE
## default           Active   5m20s
## kube-system       Active   5m20s
## kube-public       Active   5m20s
## kube-node-lease   Active   5m20s
## linkerd           Active   63s
```

The only difference here is the addition of the `linkerd` namespace. That
makes sense; we just installed Linkerd.

```bash
kubectl get pods -n kube-system
## NAME                                      READY   STATUS    RESTARTS   AGE
## coredns-b96499967-rgt47                   1/1     Running   0          5m6s
## local-path-provisioner-7b7dc8d6f5-dnvgh   1/1     Running   0          5m6s
## metrics-server-668d979685-7swdn           1/1     Running   0          5m6s
```

We don't expect anything different in `kube-system`, and we don't
see anything different. So that's good.

```bash
kubectl get pods -n linkerd
## NAME                                      READY   STATUS    RESTARTS   AGE
## linkerd-identity-7496d986db-lbqs4         2/2     Running   0          67s
## linkerd-destination-6d84dd45b8-46xlk      4/4     Running   0          67s
## linkerd-proxy-injector-7547777654-2szmq   2/2     Running   0          67s
```

These are the usual suspects for a Linkerd installation.

<!-- @wait_clear -->
Let's go ahead and install an application, too, so that we have something
to mess with. This is from the emojivoto quickstart.

```bash
kubectl create ns emojivoto
kubectl annotate ns emojivoto linkerd.io/inject=enabled
kubectl apply -f https://run.linkerd.io/emojivoto.yml
kubectl wait --timeout=90s --for=condition=available \
        deployment --all -n emojivoto
```

OK, emojivoto is running. What's running in its namespace?

```bash
kubectl get pods -n emojivoto
## NAME                        READY   STATUS    RESTARTS   AGE
## voting-5f5b555dff-t968b     2/2     Running   0          106s
## vote-bot-786d75cf45-5md5f   2/2     Running   0          106s
## emoji-78594cb998-sbvl7      2/2     Running   0          106s
## web-68cc8bc689-j4ph2        2/2     Running   0          106s
```

Note that all these pods have two containers. Let's take a closer look at
the `emoji` pod.

```bash
POD=$(kubectl get pods -n emojivoto -l 'app=emoji-svc' -o jsonpath='{ .items[0].metadata.name }')
#@print "# Found emoji-svc pod ${POD}"

kubectl get pod -n emojivoto ${POD} \
    -o jsonpath='{ range .spec.containers[*]}{.name}{"\n"}{end}'
## linkerd-proxy
## emoji-svc
```

As promised by `proxy-await` being set by default, the first container
is `linkerd-proxy`, which is the Linkerd sidecar. After that comes the
application container, `emoji-svc`.

Let's check out the lifecycle hooks.

```bash
kubectl get pod -n emojivoto ${POD} \
    -o jsonpath='{ range .spec.containers[*]}{.name}{" lifecycle:\n"}{.lifecycle }{"\n\n"}{end}'
## linkerd-proxy lifecycle:
## {"postStart":{"exec":{"command":["/usr/lib/linkerd/linkerd-await","--timeout=2m"]}}}
##
## emoji-svc lifecycle:
##
```

Sure enough, we see the `postStart` hook that we need for `proxy-await`
for the `linkerd-proxy` container, but nothing for the `emoji-svc`
container.

Another (minor) note: you'll need to look for the `postStart` hook if
you want to verify that `proxy-await` is active. There's nothing in the
environment or anything that shows up other than that:

```bash
kubectl get pod -n emojivoto ${POD} -o yaml | grep -i await
##          - /usr/lib/linkerd/linkerd-await
```

<!-- @wait_clear  -->

One important note: we didn't see anything about an init container in
the container list, did we? That's because it's not in `spec.containers`:
it's in `spec.initContainers`. So let's look at that.

```bash
kubectl get pod -n emojivoto ${POD} \
    -o jsonpath='{ range .spec.initContainers[*]}{.name}{"\n"}{end}'
## linkerd-init
```

We do see an init container; good. We should also be able to check out
whether it succeeded by looking into `.status.initContainerStatuses`.

```bash
kubectl get pod -n emojivoto ${POD} \
    -o jsonpath='{ range .status.initContainerStatuses[*]}{.name}{": "}{.state.terminated.reason}{", "}{.state.terminated.exitCode}{"\n"}{end}'
## linkerd-init: Completed, 0
```

So that's the happy path for the init container. Let's switch to a CNI.

<!-- @wait_clear -->

## Using the CNI plugin

We'll create a new `k3d` cluster to try out the CNI. Again, we explicitly
tell `k3d` _not_ to deploy Traefik, since we'll be using Linkerd.

```bash
k3d cluster delete startup-cni
# -p "80:80@loadbalancer" -p "443:443@loadbalancer"
k3d cluster create startup-cni \
    --k3s-arg '--no-deploy=traefik@server:*;agents:*'
```

Once that's done, we then install the Linkerd CNI extension. **This
extension must be installed before installing Linkerd itself**, and in
fact it is the **only** extension where that's possible.

```bash
linkerd-edge-22.11.1 install-cni | kubectl apply -f -
```

Note that we now have a new `linkerd-cni` namespace:

```bash
kubectl get namespace
## NAME              STATUS   AGE
## default           Active   15s
## kube-system       Active   15s
## kube-public       Active   15s
## kube-node-lease   Active   15s
## linkerd-cni       Active   2s
```

in which is running the Linkerd CNI DaemonSet:

```bash
kubectl get -n linkerd-cni daemonset
## NAME          DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR            AGE
## linkerd-cni   1         1         0       1            0           kubernetes.io/os=linux   4s
```

<!-- @wait_clear -->

After setting up the Linkerd CNI plugin, we can install Linkerd. Note the
`--linkerd-cni-enabled` flag on `linkerd install`!

```bash
linkerd-edge-22.11.1 install --crds | kubectl apply -f -
linkerd-edge-22.11.1 install --linkerd-cni-enabled | kubectl apply -f -
linkerd-edge-22.11.1 check
```

<!-- @SHOW -->

Something is wrong. What's up with our Linkerd pods?

```bash
kubectl get pods -n linkerd
## NAME                                     READY   STATUS                  RESTARTS      AGE
## linkerd-identity-5ff8bd9464-scswh        0/2     Init:CrashLoopBackOff   3 (29s ago)   113s
## linkerd-destination-695f674c6b-pmv47     0/4     Init:CrashLoopBackOff   3 (29s ago)   113s
## linkerd-proxy-injector-6f945494d-vjwrm   0/2     Init:CrashLoopBackOff   3 (25s ago)   113s
```

That's not good. Let's look a little deeper into the destination
controller to see if we can find anything.

```bash
POD=$(kubectl get pods -n linkerd -l 'linkerd.io/control-plane-component=destination' -o jsonpath='{ .items[0].metadata.name }')
#@print "# Found destination controller pod ${POD}"

kubectl logs -n linkerd ${POD}
## Defaulted container "linkerd-proxy" out of: linkerd-proxy, destination, sp-validator, policy, linkerd-network-validator (init)
## Error from server (BadRequest): container "linkerd-proxy" in pod "linkerd-destination-695f674c6b-pmv47" is waiting to start: PodInitializing
```

"Waiting to start: PodInitializing" means that the init container hasn't
completed yet. What does it say?

```bash
kubectl logs -n linkerd ${POD} -c linkerd-network-validator
## 2022-11-17T16:06:24.074377Z  INFO linkerd_network_validator: Listening for connections on 0.0.0.0:4140
## 2022-11-17T16:06:24.074403Z DEBUG linkerd_network_validator: token="rI32HVkfyqilbDlcxICwEAWbqTxSM0l7iBdY9xnPInzVSTqJxdXymmCaMLRwa7U\n"
## 2022-11-17T16:06:24.074409Z  INFO linkerd_network_validator: Connecting to 1.1.1.1:20001
## 2022-11-17T16:06:34.077112Z ERROR linkerd_network_validator: Failed to validate networking configuration timeout=10s
```

So... our CNI is just broken; the validator is doing its job and
showing us that something is wrong.

<!-- @wait_clear -->

Actually going through the debugging exercise is a little bit much for
this talk, so we'll skip to the punchline: `k3d`, as it happens, uses
`flannel` by default for its network layer. This is fine, except that
it installs `flannel` in a way that doesn't work with Linkerd's
standard CNI plugin install paths. So we have two options:

1. Tweak the Linkerd install paths to work with `k3d`'s `flannel`
   install, or

2. Install some other CNI when we set up `k3d`.

Either of these options will work. We'll just tweak the install paths
(option 1) at the moment, and save playing with entirely different CNI
layers for a different workshop.

<!-- @wait_clear -->

So. Let's delete and recreate our cluster...

```bash
k3d cluster delete startup-cni
# -p "80:80@loadbalancer" -p "443:443@loadbalancer"
k3d cluster create startup-cni \
    --k3s-arg '--no-deploy=traefik@server:*;agents:*'
```

...and then reinstall the Linkerd CNI extension, this time with the
arguments that override the install paths as needed to actually work:
(Obviously we could do this with Helm as well.)

```bash
linkerd-edge-22.11.1 install-cni \
    --dest-cni-net-dir "/var/lib/rancher/k3s/agent/etc/cni/net.d/" \
    --dest-cni-bin-dir "/bin" | kubectl apply -f -
```

OK, let's see if Linkerd comes up this time:

```bash
linkerd-edge-22.11.1 install --crds | kubectl apply -f -
linkerd-edge-22.11.1 install --linkerd-cni-enabled | kubectl apply -f -
linkerd-edge-22.11.1 check
```

<!-- @wait_clear -->

Much better! Once again, we have a `linkerd` namespace with the usual
suspects running in it:

```bash
kubectl get namespace
## NAME              STATUS   AGE
## default           Active   2m57s
## kube-system       Active   2m57s
## kube-public       Active   2m57s
## kube-node-lease   Active   2m57s
## linkerd-cni       Active   2m45s
## linkerd           Active   2m10s

kubectl get pods -n linkerd
## NAME                                      READY   STATUS    RESTARTS   AGE
## linkerd-identity-6548449996-tvjbp         2/2     Running   0          107s
## linkerd-proxy-injector-758c5896b8-pb25z   2/2     Running   0          107s
## linkerd-destination-699f8b87db-dckh7      4/4     Running   0          107s
```

<!-- @wait_clear -->

Let's reinstall emojivoto too.

```bash
kubectl create ns emojivoto
kubectl annotate ns emojivoto linkerd.io/inject=enabled
kubectl apply -f https://run.linkerd.io/emojivoto.yml
kubectl wait --timeout=90s --for=condition=available \
        deployment --all -n emojivoto
```

OK, emojivoto is now running in our CNI cluster. What's running in its
namespace?

```bash
kubectl get pods -n emojivoto
## NAME                        READY   STATUS    RESTARTS   AGE
## voting-5f5b555dff-ht2q2     2/2     Running   0          24s
## emoji-78594cb998-kjnsr      2/2     Running   0          24s
## web-68cc8bc689-l775g        2/2     Running   0          24s
## vote-bot-786d75cf45-tcj52   2/2     Running   0          24s
```

Again, these pods all have two containers – presumably the sidecar and
the actual application container? Last time we just looked at the emoji
workload, but let's just look at all of them this time:

```bash
kubectl get pods -n emojivoto \
    -o jsonpath='{ range .items[*] }{ .metadata.name }{": "}{ range .spec.containers[*] }{ .name }{" "}{ end }{"\n"}{ end }'
## voting-5f5b555dff-ht2q2: linkerd-proxy voting-svc
## emoji-78594cb998-kjnsr: linkerd-proxy emoji-svc
## web-68cc8bc689-l775g: linkerd-proxy web-svc
## vote-bot-786d75cf45-tcj52: linkerd-proxy vote-bot
```

Right: one sidecar, coming first again, and one application container.
Let's check out the lifecycle hooks (here we'll just do a single pod
again, the output is pretty messy otherwise):

```bash
POD=$(kubectl get pods -n emojivoto -l 'app=emoji-svc' -o jsonpath='{ .items[0].metadata.name }')
#@print "# Found emoji-svc pod ${POD}"

kubectl get pod -n emojivoto ${POD} \
    -o jsonpath='{ range .spec.containers[*]}{.name}{" lifecycle:\n"}{.lifecycle }{"\n\n"}{end}'
## linkerd-proxy lifecycle:
## {"postStart":{"exec":{"command":["/usr/lib/linkerd/linkerd-await","--timeout=2m"]}}}
##
## emoji-svc lifecycle:
##
```

So we still see the `proxy-await` `postStart` hook for the `linkerd-proxy`
container, with nothing for the `emoji-svc` container. That `postStart`
is still very relevant in the CNI world.

How about init containers?

```bash
kubectl get pods -n emojivoto -o jsonpath='{ range .items[*] }{ .metadata.name }{": "}{ range .spec.initContainers[*] }{ .name }{" "}{ end }{"\n"}{ end }'
## voting-5f5b555dff-ht2q2: linkerd-network-validator
## emoji-78594cb998-kjnsr: linkerd-network-validator
## web-68cc8bc689-l775g: linkerd-network-validator
## vote-bot-786d75cf45-tcj52: linkerd-network-validator
```

Aha! This time around, it's not the `proxy-init` container, but the
`linkerd-network-validator`, which is there to check that the CNI is
set up correctly.

(If we didn't install `edge-22.11.1` or newer, we'd see `noop` here: on
older releases, there's an init container that does... nothing. Having
the validator is much better.)

<!-- @wait_clear -->

So there we go: we've taken a quick look at some of what's under the hood
when Linkerd starts running using the init container and the CNI plugin,
including seeing things break when the CNI is unhappy. There's a lot more
to explore here, but hopefully this will serve as a good starting point.

<!-- @wait -->
<!-- @show_slides -->
