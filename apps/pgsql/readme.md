# PostgreSQL (AWX)

> **Status: not in use.** This database served only AWX. It was removed from cluster `orange` on 2026-11-18
> and its data was deleted. Its Argo CD Application is not deployed, so changes here have no effect.

## Reinstall

1. Deploy the application: `kubectl apply -f apps/pgsql/application.yaml`
2. Sync `pgsql` manually in Argo CD (this app has no automatic sync).
3. Continue with the AWX steps in [`apps/awx-operator/readme.md`](../awx-operator/readme.md#reinstall).

## Overview

PostgreSQL for AWX, from plain manifests in `templates/` with the **official `postgres` image**
(migrated from the Bitnami chart / `bitnami/postgresql:latest` in Nov 2026 by dump & restore).

| | |
|---|---|
| Image | `postgres:18.6` (Debian, tracked by Dependabot `docker`; majors ignored) |
| StatefulSet | `postgres` (pod `postgres-0`) |
| Service | `pgsql-awx.pgsql.svc.cluster.local:5432` (old name kept, AWX config unchanged) |
| Database / user | `postgres` / `postgres` (only role), `en_US.UTF-8` |
| Password | SealedSecret `templates/pgsql-awx-sealedsecret.yaml` → Secret `pgsql-awx` key `postgres-password`; same value as `awx/awx-demo-postgres-configuration` |
| Storage | PVC `data-postgres-0`, 8Gi `nfs-atlas`, `PGDATA=/var/lib/postgresql/18/docker` |
| Argo CD | **manual sync** (database: sync deliberately) |

## Access

```bash
kubectl exec -it -n pgsql postgres-0 -- psql -U postgres
```

## Backup / restore

```bash
kubectl exec -n pgsql postgres-0 -- pg_dump -U postgres -d postgres -Fc > awx-$(date +%F).dump
kubectl exec -i -n pgsql postgres-0 -- pg_restore -U postgres -d postgres --clean --if-exists < awx-YYYY-MM-DD.dump
```

Stop AWX before restoring: `kubectl patch awx awx-demo -n awx --type merge -p '{"spec":{"replicas":0}}'`
(back with `"replicas":1`).

## Major upgrades (e.g. 18 → 19)

Not done in place: dump, deploy the new major on a new volume, restore (see the migration in PR history).
