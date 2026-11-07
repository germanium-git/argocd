# Prometheus Operator CRDs

The `monitoring.coreos.com` CRDs (Prometheus, Alertmanager, ServiceMonitor, PodMonitor,
PrometheusRule, ...) from the [prometheus-operator-crds](https://github.com/prometheus-community/helm-charts/tree/main/charts/prometheus-operator-crds)
chart. They are **not** installed by `kube-prometheus-stack` (`crds.enabled: false` there).

## Why a separate app

Argo CD validates every rendered object against the CRD schemas **in the cluster** while comparing.
When a new kube-prometheus-stack uses a field the old CRDs don't know, the comparison fails
(`ComparisonError: ... field not declared in schema`) and nothing can be synced. This app contains
only CRDs, so it can always be compared and synced on its own.

## Upgrade order

1. Merge and **sync this app first** (Dependabot PR for `prometheus-operator-crds`).
2. Then merge and sync `kube-prometheus-stack`.

Keep the versions aligned: the chart major tracks the operator minor
(`32.0.x` = operator `v0.94.x`). Check the operator version used by kube-prometheus-stack with
`helm show chart prometheus-community/kube-prometheus-stack --version <v> | grep appVersion`.
CRDs newer than the operator are fine; older are not.

## Safety

The CRDs carry `argocd.argoproj.io/sync-options: Prune=false,Delete=false`: deleting a CRD deletes
all its custom resources, so Argo CD never removes them, not even when this app is deleted.

## Install

```bash
kubectl apply -f apps/prometheus-operator-crds/application.yaml
```
