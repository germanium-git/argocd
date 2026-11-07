# Prometheus stack

## Upgrading (read first)

The Prometheus Operator CRDs are **not** part of this app (`crds.enabled: false`). They live in the
separate Argo app [`prometheus-operator-crds`](../prometheus-operator-crds/readme.md).

Upgrade order:

1. Merge and **sync `prometheus-operator-crds` first** (its Dependabot PR). Its version must match or be
   newer than the operator used by the new kube-prometheus-stack: CRD chart major = operator minor,
   e.g. `32.0.x` = `v0.94.x`. Check with
   `helm show chart prometheus-community/kube-prometheus-stack --version <v> | grep appVersion`.
2. Then merge and sync **kube-prometheus-stack**, with **prune** enabled (renamed/split PrometheusRules
   would otherwise run twice and produce duplicate series).

If the CRDs are older than the chart expects, Argo CD can't even compare the app:
`ComparisonError: ... field not declared in schema`. Fix: sync `prometheus-operator-crds`, then refresh.

Other notes:

- Grafana's admin credentials come from the SealedSecret `templates/grafana-admin-sealedsecret.yaml`
  (`grafana.admin.existingSecret`). Newer charts have no default password and would otherwise generate a
  random one on every render (permanent OutOfSync, rotating password).
- Grafana has no persistent storage: dashboards are loaded from ConfigMaps labelled `grafana_dashboard=1`;
  anything created or starred in the UI is lost on restart.
- After an upgrade check: all targets up, no rule errors, only `Watchdog`/`InfoInhibitor` firing
  (`kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090` → `/targets`, `/rules`, `/alerts`).

```
kubectl create secret generic alertmanager-slack-notification -n monitoring \
    --from-literal=slack_webhook=https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX \
    --dry-run=client -o yaml | kubeseal --format=yaml > prometheus-slack-sealedsecret.yaml
```

## Helm

All values - https://github.com/prometheus-community/helm-charts/blob/main/charts/kube-prometheus-stack/values.yaml


## Grafana

```
kubectl get secret --namespace monitoring grafana-admin -o jsonpath="{.data.admin-user}" | base64 -d
kubectl get secret --namespace monitoring grafana-admin -o jsonpath="{.data.admin-password}" | base64 -d
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
