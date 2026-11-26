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

## Alerting (Slack)

Alerts of severity `warning` or `critical`, from all namespaces, go to Slack **#alerts-k8s**
(`kube-prometheus-stack.alertmanager.config` in `values.yaml`). `Watchdog` and `InfoInhibitor` go nowhere.

- Sent with the Argo CD notifications bot (`argocd`) through `chat.postMessage`. The bot must be a member
  of the channel (`/invite @argocd`).
- Token: SealedSecret `templates/alertmanager-slack-bot-sealedsecret.yaml`, mounted through
  `alertmanagerSpec.secrets` at `/etc/alertmanager/secrets/alertmanager-slack-bot/token`. It is a copy of
  `slack-token` in `argocd/argocd-notifications-secret`; re-seal it if that token changes:
  ```
  kubectl get secret argocd-notifications-secret -n argocd -o jsonpath='{.data.slack-token}' | base64 -d \
    | kubectl create secret generic alertmanager-slack-bot -n monitoring --from-file=token=/dev/stdin \
        --dry-run=client -o yaml | kubeseal --format yaml > templates/alertmanager-slack-bot-sealedsecret.yaml
  ```
  When you renew the token with `apps/argocd/renew-secrets.sh`, it re-seals this copy too.
- `inhibit_rules` come from the chart defaults; only `route` and `receivers` are set here.
- Test: `kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093`, then
  `amtool alert add TestAlert severity=warning namespace=test --annotation=summary="test" --alertmanager.url=http://localhost:9093`.
- Backup alerts (`BackupNotSucceeded`, ...) are defined in `apps/backup/prometheusrule.yaml`.

The earlier webhook setup (`AlertmanagerConfig` for the `monitoring` namespace only, secret
`alertmanager-slack-notification`) was removed in favour of this.

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

### arm64

The nodes are **arm64**. Before merging an upgrade, check that the new operator / config-reloader images have an
arm64 manifest, e.g.
`crane manifest quay.io/prometheus-operator/prometheus-operator:<tag> | grep architecture`
(93.0.0 / operator v0.95.1 was amd64-only: prometheus-operator#8953; skipped in `.github/dependabot.yml`).
