# Backup (nightly restic backup of the orange cluster)

Full documentation, including restore runbooks: XWiki **Projects / Orange K8s / Backup and Restore**
(https://wiki.germanium.cz). Copies of the runbooks are kept in the `orange-k8s` repo under `backup-restore/`.

## What it does

CronJob `backup` in namespace `backup`, every night at 02:30 Europe/Prague, pinned to `orange1`
(the control-plane node, where etcd and `/etc/kubernetes/pki` live).

```
init etcd-snapshot  registry.k8s.io/etcd   etcdctl snapshot save (hostNetwork, healthcheck-client cert)
init etcd-verify    registry.k8s.io/etcd   etcdutl snapshot status
init collect        alpine/k8s             scripts/collect.sh  -> /staging (emptyDir)
main restic         restic/restic          scripts/restic.sh   -> orange1:/var/backups/restic
```

What is backed up:

| Item | How |
|---|---|
| etcd | snapshot, verified before use |
| Cluster certificates | copy of `/etc/kubernetes/pki` (includes CA keys; the repository is encrypted) |
| Sealed Secrets keys | `kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key` |
| Postgres (paperless, xwiki) | `pg_dump -Fc` per database plus `pg_dumpall --globals-only`, run in the database pod |
| SQLite (Home Assistant, n8n, JupyterHub, stash-bot) | consistent copies via SQLite's backup API (`scripts/sqlite_copy.py`) |
| Application volumes | NAS folders of all Bound PVs, NFS mounted read-only |

Left out on purpose: `monitoring/*`, `logging/*`, raw `*postgres*` data folders (covered by dumps),
motionEye recordings and the ESPHome build cache (`.esphome`).

Retention: 7 daily, 4 weekly, 6 monthly. On Sundays `restic check --read-data-subset=5%`.
Any failed step fails the job.

## Files

- `cronjob.yaml`: the CronJob.
- `rbac.yaml`: ServiceAccount `backup`; read PVs; read Sealed Secrets keys in `kube-system`;
  `pods/exec` only in `paperless` and `xwiki`.
- `scripts/`: packed into ConfigMap `backup-scripts` by `configMapGenerator`.
- `restic-sealedsecret.yaml`: restic repository password. The plain value is in Bitwarden,
  item **orange backup - restic password**. Without it no backup can be read.

## Common tasks

```bash
# Run a backup now
kubectl create job --from=cronjob/backup -n backup backup-manual-$(date +%s)
kubectl logs -n backup -f job/<name> --all-containers --prefix

# List snapshots (on orange1, password from Bitwarden)
sudo restic -r /var/backups/restic snapshots
```

The `registry.k8s.io/etcd` tag must match the cluster's etcd version; Dependabot ignores it.
Update it after a `kubeadm upgrade`.
