# cloudflared

Connector for the Cloudflare Tunnel `k8s-ingress` (tunnel ID `f14686c6-e006-4076-9b65-a84d93aa2e01`).
It forwards every `*.germanium.cz` request that reaches the tunnel to Traefik
(`https://traefik.traefik.svc.cluster.local:443`), which routes it by hostname (HTTPRoutes on
`traefik-gateway-tls-tunnel`).

| | |
|---|---|
| Namespace | `cloudflare` (shared with external-dns) |
| Replicas | 2, on different nodes, PodDisruptionBudget `minAvailable: 1` |
| Image | `cloudflare/cloudflared`, pinned, updated by Dependabot |
| Config | `config.yaml` (ConfigMap with hash suffix, a change restarts the pods) |
| Credentials | Secret `argo-tunnel-settings`, key `tunnel-config.json` (created by hand, **not in Git**; keep a copy in Bitwarden) |
| Tunnel and Access apps | Terraform, `germanium-git/cloudflare-zero-trust` |

Cloudflare supports a cloudflared version for one year after its release; older ones show as
"Unsupported" in the dashboard (Zero Trust → Networks → Tunnels → k8s-ingress).

## Exposing a site

1. HTTPRoute attached to `traefik/traefik-gateway-tls-tunnel`, with annotation
   `external-dns.kubernetes.io/cloudflare-proxied: "true"`. external-dns then publishes a proxied CNAME
   to the tunnel.
2. **A Cloudflare Access application for the hostname** in `cloudflare-zero-trust/access_applications.tf`.
   Without it the site is open to the internet.
3. On the LAN: a static entry on the SRX300 DNS proxy, `<name>.germanium.cz` → `172.31.1.34`.

## Recreating the credentials Secret

The credentials file comes from `cloudflared tunnel create` (or the dashboard); keep a copy in Bitwarden.

```bash
kubectl create secret generic argo-tunnel-settings -n cloudflare \
  --from-file=tunnel-config.json=<path to the credentials file>
```

## History

Until 2026-11-20 cloudflared ran from a Helm release `cloudflared` (chart 1.7.1, image 2025.8.1)
installed by hand, outside Argo CD and Dependabot.
