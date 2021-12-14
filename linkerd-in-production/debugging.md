kubectl get ev -n linkerd --sort-by="{.lastTimestamp}"

kubectl get logs <identity pod> -n linkerd identity
kubectl get logs <identity pod> -n linkerd linkerd-proxy
kubectl get logs <identity pod> -n linkerd linkerd-init

linkerd version
linkerd check
linkerd diagnostics proxy-metrics po/<identity pod> -n linkerd
linkerd identity -n linkerd -l linkerd.io/control-plane-component=identity
