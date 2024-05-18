# Prometheus stack

```
kubectl create secret generic alertmanager-slack-notification -n monitoring \
    --from-literal=slack_webhook=https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX \
    --dry-run=client -o yaml | kubeseal --format=yaml > prometheus-slack-sealedsecret.yaml
```


## Grafana

```
kubectl get secret --namespace monitoring prometheus-stack-grafana -o jsonpath="{.data.admin-user}" | base64 -d
kubectl get secret --namespace monitoring prometheus-stack-grafana -o jsonpath="{.data.admin-password}" | base64 -d
```

### values.yaml
https://github.com/prometheus-community/helm-charts/blob/main/charts/kube-prometheus-stack/values.yaml


## Issues

### Prometheus rule failing with "many-to-many matching not allowed"

https://stackoverflow.com/questions/61900588/prometheus-rule-failing-with-many-to-many-matching-not-allowed

Delete the service service="prometheus-stack-kube-prom-kubelet" namespace="kube-system

### Prometheus Target down - Kubernetes proxy
Update the config map with `metricsBindAddress: 0.0.0.0:10249`
https://stackoverflow.com/questions/60734799/all-kubernetes-proxy-targets-down-prometheus-operator

## Metrics to scrape

Check the metrics by curl from another POD (for instance by running `kubectl run tmp-shell --rm -i --tty --image nicolaka/netshoot`).

```
curl http://traefik.traefik-v2.svc.cluster.local/metrics
curl http://loki.logging.svc.cluster.local:3100/metrics
curl http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090/metrics

```

Check the Prometheus object from the monitoring.coreos.com/v1 API to identify the proper selectors for ServiceMonitor.
```
 spec:
   serviceMonitorSelector:
     matchLabels:
       release: kube-prometheus-stack
```

Create a ServiceMonitor with the proper lables matching the requiremnts.
```
labels:
   release=kube-prometheus-stack
```

Check if Promethgeus sees the new ServiceMonitors as valid targets - http://prometheus.germanium.cz:9090/targets
