### Prerequisites

- BEL 2.19.1
- Cluster with both windows and Linux nodes

### Install Linkerd Windows CNI

```
helm upgrade -i -n windows-cni --create-namespace \
    linkerd-enterprise-windows-cni \
    --wait \
    oci://ghcr.io/buoyantio/charts/linkerd-enterprise-windows-cni \
    --devel
```

### Deploy client

```
kubectl create ns win-demo
kubectl apply -f client.yml
```

### Deploy Linux Server

```
kubectl create ns win-demo
kubectl apply -f client.yml
```

### Generate traffic to server

```
kubectl exec -c client --stdin --tty client -n win-demo -- sh
while sleep 1; do curl -s -w "\n" http:///server.win-demo.svc.cluster.local:80/who-am-i; done
```

### Deploy windows server

```
kubectl apply -f windows-server.yml
```

### Deploy auth policy
```
kubectl apply -f policy-server.yml
```