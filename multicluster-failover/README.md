# Multicluster Failover With Linkerd

This example will walk you through the process of configuring Linkerd in a
multicluster configuration with the linkerd-failover extension. Once this
architecture is in place, you will be able to use mirrored services as
failover services for your application traffic.

## Requirements

This example assumes that you have two Kubernetes clusters. We will be calling
these clusters `east` and `west`; if your clusters have other names, remember to
substitute the same cluster for `east` or `west` every time those names appear
in these instructions.

In addition, you will need following CLIs installed locally:

- [smallstep](https://smallstep.com/docs/step-cli/installation)
- [kubectl](https://kubernetes.io/docs/tasks/tools/#kubectl)
- [the latest version of Linkerd](https://linkerd.io/2.11/getting-started/#step-1-install-the-cli)

## Steps

### Step 1

Make sure that you can access your clusters from your local machine

- `kubectl get po -n kube-system -c east`
- `kubectl get po -n kube-system -c west`

### Step 2

Verify that Linkerd can be deployed to the clusters

- `linkerd check --pre --context east`
- `linkerd check --pre --context west`

### Step 3

Generate a common trust root and child certificates

#### Common trust root

```bash
step certificate create root.linkerd.cluster.local root.crt root.key \
  --profile root-ca --no-password --insecure
```

#### Leaf certificates for each cluster

```bash
step certificate create identity.linkerd.cluster.local east-issuer.crt \ 
east-issuer.key --profile intermediate-ca --not-after 8760h --no-password \
--insecure --ca root.crt --ca-key root.key
```

```bash
step certificate create identity.linkerd.cluster.local west-issuer.crt \ 
west-issuer.key --profile intermediate-ca --not-after 8760h --no-password \
--insecure --ca root.crt --ca-key root.key
```

### Step 4

Deploy Linkerd to each of the clusters with their respective certificates

#### east

```bash
linkerd install --context east\
  --identity-trust-anchors-file root.crt \
  --identity-issuer-certificate-file east-issuer.crt \
  --identity-issuer-key-file east-issuer.key |
  kubvectl apply -f -
```

#### west

```bash
linkerd install --context east\
  --identity-trust-anchors-file root.crt \
  --identity-issuer-certificate-file west-issuer.crt \
  --identity-issuer-key-file west-issuer.key |
  kubvectl apply -f -
```

### Step 5

Deploy linkerd-viz to each cluster

```bash
for ctx in west east; do
  linkerd --context=${ctx} viz install | \
    kubectl --context=${ctx} apply -f - || break
done
```

### Step 6

Deploy emojivoto to each cluster

```bash
for ctx in west east; do
  kubectl apply -f https://run.linkerd.io/emojivoto.yml -c ${ctx}
done
```

### Step 7

Deploy linkerd-failover to each cluster

```bash
for ctx in west east; do
  linkerd --context=${ctx} viz install | \
    kubectl --context=${ctx} apply -f - || break
done
```

### Step 8

Deploy linkerd-multicluster to each cluster

```bash
for ctx in west east; do
  echo "Installing on cluster: ${ctx} ........."
  linkerd --context=${ctx} multicluster install | \
    kubectl --context=${ctx} apply -f - || break
  echo "-------------"
done
```

### Step 9

Link the clusters

```bash
linkerd --context=east multicluster link --cluster-name east |
  kubectl --context=west apply -f -
```

### Step 10

Export a service

```bash
kubectl --context=east -n emojivoto label svc/web-svc mirror.linkerd.io/exported=true
```

### Step 11

Deploy the failover resources

```bash
kubectl apply \
  -f https://raw.githubusercontent.com/BuoyantIO/service-mesh-academy/main/multicluster-failover/failover-config/emoji-deploy-2.yml \
  -f https://raw.githubusercontent.com/BuoyantIO/service-mesh-academy/main/multicluster-failover/failover-config/emoji-svc-2.yml \
  -f https://raw.githubusercontent.com/BuoyantIO/service-mesh-academy/main/multicluster-failover/failover-config/emoji-failover.yml
```

### Step 12

Scale the primary service to 0 replicas

```bash
kubectl scale deploy emoji --replicas=0 -c west
```
