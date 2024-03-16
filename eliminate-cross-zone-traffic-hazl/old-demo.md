### Increase Number of Requests From the `orders-central` Requestor

General instructions on how to turn up requests

Scale the `orders-central` Deployment to 15 replicas on both clusters:

```bash
kubectl scale deploy orders-central -n orders --replicas=15 --context=hazl ; kubectl scale deploy orders-central -n orders --replicas=15 --context=topo
```

Give things a minute to develop, then head over to **Buoyant Cloud**.

### Monitor Traffic Using Buoyant Cloud

Let's take a look at what the increased traffic looks like in **Buoyant Cloud**. This will give us a more visual representation of the effect of **HAZL** on our traffic.

![Buoyant Cloud: Topology](images/orders-hazl-increased-central-load-bcloud.png)

We can see...

<<Explain what we're seeing here>>

### Decrease Number of Requests From the `orders-central` Requestor

General instructions on how to turn down requests

Scale the `orders-central` Deployment to 11 replica on both clusters:

```bash
kubectl scale deploy orders-central -n orders --replicas=1 --context=hazl ; kubectl scale deploy orders-central -n orders --replicas=1 --context=topo
```

Give things a minute to develop, then head over to **Buoyant Cloud**.

### Monitor Traffic Using Buoyant Cloud

Let's take a look at what the increased traffic looks like in **Buoyant Cloud**. This will give us a more visual representation of the effect of **HAZL** on our traffic.

![Buoyant Cloud: Topology](images/orders-hazl-decreased-central-load-bcloud.png)

We can see...

<<Explain what we're seeing here>>

### Increase Number of Requests From the `orders-west` Requestor

General instructions on how to turn up requests

Scale the `orders-west` Deployment to 25 replicas on both clusters:

```bash
kubectl scale deploy orders-west -n orders --replicas=25 --context=hazl ; kubectl scale deploy orders-west -n orders --replicas=25 --context=topo
```

Give things a minute to develop, then head over to **Buoyant Cloud**.

### Monitor Traffic Using Buoyant Cloud

Let's take a look at what the increased traffic looks like in **Buoyant Cloud**. This will give us a more visual representation of the effect of **HAZL** on our traffic.

![Buoyant Cloud: Topology](images/orders-hazl-increased-load-west-bcloud.png)

We can see...

<<Explain what we're seeing here>>

### Kill the `warehouse-oakland` Workload

General instructions on how to turn up requests

Scale the `warehouse-oakland` Deployment to 0 replicas on both clusters:

```bash
kubectl scale deploy warehouse-oakland -n orders --replicas=0 --context=hazl ; kubectl scale deploy warehouse-oakland -n orders --replicas=0 --context=topo
```

Give things a minute to develop, then head over to **Buoyant Cloud**.

### Monitor Traffic Using Buoyant Cloud

Let's take a look at what the increased traffic looks like in **Buoyant Cloud**. This will give us a more visual representation of the effect of **HAZL** on our traffic.

![Buoyant Cloud: Topology](images/orders-hazl-kill-oakland-bcloud.png)

We can see...

<<Explain what we're seeing here>>

### Restore the `warehouse-oakland` Workload

General instructions

Scale the `warehouse-oakland` Deployment to 1 replica on both clusters:

```bash
kubectl scale deploy warehouse-oakland -n orders --replicas=0 --context=hazl ; kubectl scale deploy warehouse-oakland -n orders --replicas=0 --context=topo
```

Give things a minute to develop, then head over to **Buoyant Cloud**.

### Monitor Traffic Using Buoyant Cloud

Let's take a look at what the increased traffic looks like in **Buoyant Cloud**. This will give us a more visual representation of the effect of **HAZL** on our traffic.

![Buoyant Cloud: Topology](images/orders-hazl-restore-oakland-bcloud.png)

We can see...

<<Explain what we're seeing here>>

### Reset the Orders Application to the Initial State on Both Clusters

General instructions

Re-apply the initial configuration of the `orders` application on both clusters:

```bash
kubectl apply -k orders --context=hazl ; kubectl apply -k orders-topo --context=topo
```

Give things a minute to develop, then head over to **Buoyant Cloud**.

### Monitor Traffic Using Buoyant Cloud

Let's take a look at what the increased traffic looks like in **Buoyant Cloud**. This will give us a more visual representation of the effect of **HAZL** on our traffic.

![Buoyant Cloud: Topology](images/orders-hazl-increased-load-bcloud.png)

We can see...

<<Explain what we're seeing here>>