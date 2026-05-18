# paperless-ngx

Document management system with OCR, indexing, and full-text search.

- **UI:** https://paperless.germanium.cz
- **ArgoCD app:** `paperless` (namespace `paperless`)

## Helm chart

Fetched from the [gabe565 Helm repository](https://charts.gabe565.com):

| | |
|---|---|
| Chart | `paperless-ngx` |
| Version | `0.24.1` |
| App version | `2.14.7` |
| ArtifactHub | https://artifacthub.io/packages/helm/gabe565/paperless-ngx |

All chart values are in `values.yaml`. The full list of available values is documented in the chart's upstream `values.yaml` on [GitHub](https://github.com/gabe565/charts/blob/main/charts/paperless-ngx/values.yaml).

> The bundled bitnami PostgreSQL and redis subcharts are disabled (`postgresql.enabled: false`, `redis.enabled: false`) because those chart versions reference image tags that Bitnami has removed from Docker Hub. Standalone replacements are deployed via the addons directory instead.

## Components

| Component | Source | Notes |
|---|---|---|
| paperless-ngx | Helm chart (gabe565) | Main application |
| PostgreSQL | `addons/postgresql.yaml` | `postgres:16-alpine`, StatefulSet, 5Gi PVC on `nfs-atlas` |
| Redis | `addons/redis.yaml` | `redis:7-alpine`, Deployment |
| TLS certificate | `addons/paperless-certificate-prod.yaml` | cert-manager, Let's Encrypt prod, `paperless.germanium.cz` |
| Secrets | `addons/paperless-sealedsecret.yaml` | Two SealedSecrets (see below) |

## Persistent storage

All volumes use the `nfs-atlas` storage class.

| Volume | Mount | Size |
|---|---|---|
| `data` | `/usr/src/paperless/data` | 10Gi |
| `media` | `/usr/src/paperless/media` | 20Gi |
| `export` | `/usr/src/paperless/export` | 5Gi |
| `consume` | `/usr/src/paperless/consume` | 5Gi |
| PostgreSQL data | `/var/lib/postgresql/data` | 5Gi |

## Secrets

Two SealedSecrets are deployed from `addons/paperless-sealedsecret.yaml`.

### `paperless-secrets`

Injected into the paperless-ngx container via `envFrom`.

| Key | Description |
|---|---|
| `PAPERLESS_SECRET_KEY` | Django secret key (random 32+ char string) |
| `PAPERLESS_ADMIN_PASSWORD` | Password for the `admin` UI user |

### `paperless-postgresql`

Used by the standalone PostgreSQL StatefulSet.

| Key | Description |
|---|---|
| `postgres-password` | PostgreSQL superuser (`postgres`) password |
| `password` | Password for the `paperless` database user |

The paperless-ngx app reads the database password directly from this secret via `secretKeyRef` (`key: password`).

## Login

- **URL:** https://paperless.germanium.cz
- **Username:** `admin`
- **Password:** value of `PAPERLESS_ADMIN_PASSWORD` from the `paperless-secrets` sealed secret

To reset the admin password:
```bash
kubectl exec -n paperless -it \
  $(kubectl get pod -n paperless -l app.kubernetes.io/name=paperless-ngx -o name) \
  -- python manage.py changepassword admin
```

## Accessing PostgreSQL

The `paperless-postgres` service is `ClusterIP` — only reachable from inside the cluster. Use `kubectl port-forward` to connect from your machine:

```bash
kubectl port-forward svc/paperless-postgres 5432:5432 -n paperless
```

Then connect with any PostgreSQL client:

| | |
|---|---|
| Host | `localhost` |
| Port | `5432` |
| Database | `paperless` |
| Username | `paperless` |
| Password | value of `password` key in the `paperless-postgresql` secret |

To retrieve the password:
```bash
kubectl get secret paperless-postgresql -n paperless -o jsonpath='{.data.password}' | base64 -d
```

## Re-sealing secrets

To rotate or recreate the secrets, run the following commands against the cluster and paste the output into `addons/paperless-sealedsecret.yaml`:

```bash
# App secrets
kubectl create secret generic paperless-secrets \
  --namespace paperless \
  --from-literal=PAPERLESS_SECRET_KEY="$(openssl rand -hex 32)" \
  --from-literal=PAPERLESS_ADMIN_PASSWORD="your-password" \
  --dry-run=client -o yaml | kubeseal --format yaml > paperless-admin-password.yaml

# PostgreSQL secrets (username for both DB connections is 'paperless')
kubectl create secret generic paperless-postgresql \
  --namespace paperless \
  --from-literal=postgres-password="your-postgres-superuser-password" \
  --from-literal=password="your-paperless-db-password" \
  --dry-run=client -o yaml | kubeseal --format yaml > paperless-postgresql-passwords.yaml
```

Use the value of the above rendered yaml files in addons/paperless-sealedsecret.yaml.
