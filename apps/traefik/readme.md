# Traefik

Gateway API CRDs used to be bundled by this chart, but are now owned solely by
`apps/gateway-api-crds` (the Helm source here sets `skipCrds: true`) so that Istio
and Envoy Gateway can share the same CRDs without version conflicts. See
`apps/gateway-api-crds/readme.md`.

## Upgrading the chart

Because `skipCrds: true` is set, Argo CD does **not** install or upgrade Traefik's own CRDs
(`traefik.io`, `hub.traefik.io`). Before syncing a chart upgrade that ships CRD changes, apply them manually:

```
helm show crds traefik --repo https://traefik.github.io/charts --version <chart-version> \
  | kubectl apply --server-side --force-conflicts -f -
```

The chart is vendored in `charts/traefik-<version>.tgz`. A version bump must also replace that
tarball (`helm dependency update`), otherwise Argo CD keeps rendering the old chart.

# Password protection for the dashboard

The secret used in the middleware to protect from unauthorized access cosists of two parts, the <username>:<md5 encoded passord>

For example:
admin:$apr1$cpytdPSt$ThKHEIY7krGcL4AorTA7r.

To generate a password with a random salt the following command can be used:
```
openssl passwd -apr1 admin
$apr1$xWEQDX2M$1/mGx4pwRAlIA5cdPRQt31
```

And to check the current hashed password use the provided salt from teh secret (see the second part between $ signs).
```
openssl passwd -apr1 -salt cpytdPSt admin
$apr1$cpytdPSt$ThKHEIY7krGcL4AorTA7r.
```
