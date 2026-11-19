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
init rclone-bin     rclone/rclone          copies the rclone binary and config to /tools
main restic         restic/restic          scripts/restic.sh   -> orange1:/var/backups/restic
                                                                -> restic copy to Google Drive
```

Off-site: `restic copy` sends the new snapshots to `rclone:gdrive:orange-backup/restic` (Google Drive,
folder `orange-backup`, OAuth scope `drive.file`, so rclone sees only its own files). Same password,
same retention. The job fails if that repository is over 15 GB. Drive trash is bypassed, so pruned
data really frees the quota.

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

Retention: 7 daily, 4 weekly, 6 monthly, in both repositories. On Sundays
`restic check --read-data-subset=5%` on both.
Any failed step fails the job.

## Files

- `cronjob.yaml`: the CronJob.
- `rbac.yaml`: ServiceAccount `backup`; read PVs; read Sealed Secrets keys in `kube-system`;
  `pods/exec` only in `paperless` and `xwiki`.
- `scripts/`: packed into ConfigMap `backup-scripts` by `configMapGenerator`.
- `restic-sealedsecret.yaml`: restic repository password. The plain value is in Bitwarden,
  item **orange backup - restic password**. Without it no backup can be read.
- `rclone-sealedsecret.yaml`: `rclone.conf` with the Google Drive token. Plain copy in Bitwarden,
  Secure Note **orange backup - rclone config**; the OAuth client (Google Cloud project `orange-backup`)
  is in **orange backup - google oauth client**.
- `.gitattributes`: keeps the scripts LF on Windows checkouts (CRLF breaks them in the containers).

## Common tasks

```bash
# Run a backup now
kubectl create job --from=cronjob/backup -n backup backup-manual-$(date +%s)
kubectl logs -n backup -f job/<name> --all-containers --prefix

# Look into the repository: helper pod on orange1 with the repository mounted read-only
# (restic needs --no-lock for that). It stops by itself after an hour.
kubectl run restic-shell -n backup --restart=Never --image=restic/restic:0.19.1 \
  --overrides="$(cat apps/backup/tools/restic-shell.json)"
kubectl exec -n backup restic-shell -- restic --no-lock --no-cache snapshots
kubectl exec -n backup restic-shell -- restic --no-lock --no-cache ls latest /staging/data
kubectl exec -n backup restic-shell -- restic --no-lock --no-cache restore latest --target /restore --include <path>
kubectl cp backup/restic-shell:/restore/<path> ./<file>
kubectl delete pod -n backup restic-shell
```

`tools/` is not part of the kustomization, so Argo CD doesn't deploy it.

The `registry.k8s.io/etcd` tag must match the cluster's etcd version; Dependabot ignores it.
Update it after a `kubeadm upgrade`.
