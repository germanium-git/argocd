# dnsutils

DaemonSet with `dig`, `nslookup`, `host` on every node, for debugging cluster DNS
(image `registry.k8s.io/e2e-test-images/jessie-dnsutils:1.7`, arm64). Moved from Flux (`orange-k8s`) in Nov 2026.

```bash
# pick the pod on a given node
kubectl get pods -l app=dnsutils -o wide
kubectl exec -it ds/dnsutils -- nslookup kubernetes.default
kubectl exec -it ds/dnsutils -- dig +search wiki.germanium.cz
kubectl exec -it <dnsutils-pod-on-node> -- cat /etc/resolv.conf
```
