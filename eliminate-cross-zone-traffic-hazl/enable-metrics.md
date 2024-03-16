### Enable Outgoing Metrics to Buoyant Cloud (OPTIONAL)

Enable outbound latency in the `buoyant-cloud-metrics` agent:

```bash
kubectl -n linkerd-buoyant edit cm/buoyant-cloud-metrics
```

Remove this block from the configmap:

```yaml
          # drop high-cardinality outbound latency histograms
          - source_labels:
            - __name__
            - direction
            regex: 'response_latency_ms_bucket;outbound'
            action: drop
```

Save the changes, then perform a `rollout restart` on the `buoyant-cloud-metrics` daemonset:

```bash
kubectl -n linkerd-buoyant rollout restart ds buoyant-cloud-metrics
```

Outbound metrics are now enabled, so we can track metrics from the `orders-*` deployments in Buoyant's Grafana dashboards.
