# Loki

Grafana Loki log aggregation stack deployed on the home Orange Pi 5 Kubernetes cluster.

## Deployment

- **ArgoCD application**: `loki` (namespace: `argocd`)
- **Deployed to namespace**: `logging`
- **Repo**: `https://github.com/germanium-git/argocd`, path `apps/loki`, branch `main`
- **Helm chart**: `grafana/loki` v6.44.0, wrapped in an umbrella chart at this directory
- **Deployment mode**: SingleBinary (single pod handles reads and writes)
- **Loki version**: 3.5.7 (appVersion in Chart.yaml)

To apply changes: commit and push to `main` — ArgoCD syncs automatically.
To force a sync without waiting: `kubectl annotate application loki -n argocd argocd.argoproj.io/refresh=hard`

## Cluster context

- **Nodes**: orange1 (control plane, 172.31.1.50), orange2 (172.31.1.51), orange3 (172.31.1.52)
- **kubeconfig**: `~/.kube/config-files/orange-backup.yaml`
- **SSH**: `ssh orange1`, `ssh orange2`, `ssh orange3` (keys in `~/.ssh/orangePiMac`)
- **loki-0 pod** runs on orange3

## Storage

- **PVC**: `storage-loki-0`, 10 Gi, storageClass `nfs-atlas` (cluster default)
- **Storage type**: filesystem (local, not object storage)
- **Retention**: 168h (7 days), defined in `limits_config.retention_period`

## Key configuration decisions

- **Log level `warn`**: set via `singleBinary.extraArgs: [-log.level=warn]` — Loki was flooding
  `/var/log` (zram-backed, 50 MB) on orange2/orange3 with verbose query execution info logs.
  Do not revert to `info` without increasing the zram log partition size first.
- **Schema**: tsdb store, v13, filesystem object store, index prefix `loki_index_`, from 2023-01-01.
  Changing the schema requires adding a new config entry with a future `from` date — never edit
  existing entries in place.
- **Resources**: 1 CPU / 1 Gi limit, 100m / 256 Mi request (on `singleBinary`).

## Migration history

- Originally deployed via direct `helm install` (grafana/loki chart, no ArgoCD).
- Migrated to ArgoCD in April 2026: Helm release secrets deleted, ArgoCD Application applied,
  existing PVC and resources adopted via ServerSideApply. No data loss.
- `application.yaml` in this directory is the ArgoCD Application manifest (already applied).

## Useful commands

```bash
# Tail logs (should be near-silent at warn level)
kubectl logs -n logging loki-0 --tail=50

# Check /var/log disk usage on orange2/orange3 (zram, 50 MB partition)
ssh orange2 "df -h /var/log"
ssh orange3 "df -h /var/log"

# Upgrade chart version (edit Chart.yaml, run helm dep update, commit & push)
helm dep update apps/loki/

# Helm upgrade directly (bypasses ArgoCD — use only for emergencies)
helm upgrade loki grafana/loki --version 6.44.0 --namespace logging \
  --reuse-values --kubeconfig ~/.kube/config-files/orange-backup.yaml
```
