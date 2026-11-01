# XWiki

Shared wiki for internal project documentation.

- **UI:** https://wiki.germanium.cz (LAN only, via `traefik-gateway-tls`)
- **ArgoCD app:** `xwiki` (namespace `xwiki`)

## Helm chart

Official chart from [xwiki-contrib/xwiki-helm](https://github.com/xwiki-contrib/xwiki-helm):

| | |
|---|---|
| Repository | `https://xwiki-contrib.github.io/xwiki-helm` |
| Chart | `xwiki` |
| Version | `1.7.3` |
| Image | `xwiki:17.10.14-postgres-tomcat` (17.10 LTS) |

> The chart's bundled Bitnami MySQL/MariaDB/PostgreSQL subcharts are disabled. A standalone
> PostgreSQL is deployed from `addons/postgresql.yaml` (same approach as paperless).
> With an external DB the chart can't pick the image variant, so `image.tag` and
> `initContainers.database.image` are set explicitly in `values.yaml`.

When bumping XWiki, keep the `-postgres-tomcat` suffix and update `appVersion` in `Chart.yaml`.

### Dependabot

- The `xwiki` chart version is tracked by the `helm` ecosystem (`apps/*/Chart.yaml`).
- The XWiki image tag is tracked by the `docker` ecosystem. `image.repository` in `values.yaml`
  exists only so Dependabot recognises the image (the chart reads `image.name`).
- Only the **LTS line** is proposed: the ignore range in `.github/dependabot.yml` skips non-LTS
  releases. After moving to a new LTS (e.g. 18.10), shift the range to the next gap (`>= 18.11, < 19.10`).
- `postgres` images are tracked for minor/patch only; major upgrades need a dump/restore.
- Before merging an XWiki bump, back up PostgreSQL (XWiki may migrate the schema on startup).

## Components

| Component | Source | Notes |
|---|---|---|
| XWiki | Helm chart | StatefulSet, Tomcat, port 8080 (Service `xwiki:80`) |
| PostgreSQL | `addons/postgresql.yaml` | `postgres:17-alpine`, UTF-8, StatefulSet |
| HTTPRoute | `addons/httproute-https.yaml` | `wiki.germanium.cz`, wildcard cert on the gateway |
| DB secret | `addons/xwiki-postgresql-sealedsecret.yaml` | SealedSecret `xwiki-postgresql` (`password`) |

## Persistent storage (`nfs-atlas`)

| Volume | Mount | Size |
|---|---|---|
| `xwiki-data` | `/usr/local/xwiki/data` (permanent directory: extensions, Solr index, logs) | 10Gi |
| PostgreSQL data | `/var/lib/postgresql/data` | 5Gi |

## First start

1. The first boot takes several minutes (JVM + DB schema creation).
2. Open https://wiki.germanium.cz. The Distribution Wizard runs once: create the admin
   user, then install the **XWiki Standard Flavor**.

## Exposing publicly

To publish via the Cloudflare Tunnel, change the HTTPRoute `parentRefs` to
`traefik-gateway-tls-tunnel` and add the `external-dns.alpha.kubernetes.io/cloudflare-proxied: "true"`
annotation (see `apps/paperless/addons/httproute-https.yaml`).

## REST API / automation

XWiki exposes a REST API at `https://wiki.germanium.cz/rest`. Create a dedicated user (e.g. `bot`)
with edit rights on the spaces it should manage, and authenticate with HTTP Basic auth.

```bash
# Create or update a page (XWiki 2.1 syntax)
curl -u bot:PASSWORD -X PUT -H 'Content-Type: application/xml' \
  https://wiki.germanium.cz/rest/wikis/xwiki/spaces/Projects/pages/WebHome \
  --data '<page xmlns="http://www.xwiki.org"><title>Projects</title><syntax>xwiki/2.1</syntax><content>Hello</content></page>'
```

## Re-sealing the DB secret

Rotating the password of an already initialised database also requires `ALTER USER xwiki PASSWORD ...`
inside PostgreSQL.

```bash
kubectl create secret generic xwiki-postgresql -n xwiki \
  --from-literal=password="$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)" \
  --dry-run=client -o yaml | kubeseal --format yaml > addons/xwiki-postgresql-sealedsecret.yaml
```

## Accessing PostgreSQL

```bash
kubectl port-forward svc/xwiki-postgres 5432:5432 -n xwiki
kubectl get secret xwiki-postgresql -n xwiki -o jsonpath='{.data.password}' | base64 -d
```
