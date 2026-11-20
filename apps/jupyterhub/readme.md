# Jupyterhub

https://artifacthub.io/packages/helm/jupyterhub/jupyterhub

https://github.com/jupyterhub/zero-to-jupyterhub-k8s/blob/main/jupyterhub/values.yaml

## Access

| | |
|---|---|
| URL | https://jupyter.germanium.cz (HTTPRoute `templates/httproute.yaml` on `traefik-gateway-tls-tunnel`) |
| LAN | SRX300 DNS proxy entry `jupyter.germanium.cz` -> 172.31.1.34 (Traefik) |
| Remote | Cloudflare tunnel, behind the Access app `jupyter` (cloudflare-zero-trust) |
| `proxy-public` | ClusterIP; no LoadBalancer IP any more |

## Login (NativeAuthenticator)

- Users sign up at `/hub/signup`; new accounts wait for approval by the admin at `/hub/authorize`.
- Admin: `petr` (`hub.config.Authenticator.admin_users`), approved automatically.
- Passwords: at least 12 characters, common passwords rejected; an account is blocked for 10 minutes
  after 5 failed logins. Stored hashed in the hub database (PVC `hub-db-dir`).
- Forgotten password: the admin can't read it; delete and re-create the user (admin panel `/hub/admin`)
  or let the user change it at `/hub/change-password` while logged in.
- Each user gets a volume `claim-<username>` (nfs-atlas, Retain).

## Changing hub settings: restart the hub by hand

**After any change to `hub.config` or other hub settings in `values.yaml`, run:**

```bash
kubectl rollout restart deploy/hub -n jhub
```

Argo CD updates the Secret `hub` with the new settings, but the hub only reads it at startup, and
nothing restarts it: `application.yaml` makes Argo CD ignore the hub Deployment's
`checksum/secret` annotation. That is on purpose: z2jh generates the hub's secrets with Helm
`lookup`, which Argo CD doesn't support, so every render produces new random values and a new
checksum. Without the ignore, every sync would restart the hub and log everyone out.

Symptoms of a forgotten restart (2026-11-20): the signup page returned 404 because the old
DummyAuthenticator was still running, and user pods stayed `Pending` with no events because the
running hub still sent them to the removed user scheduler.

Running notebook servers keep running through a hub restart.

## Notes

- The user scheduler is disabled (`scheduling.userScheduler.enabled: false`, argocd PR #189):
  it packs pods for autoscaling clusters, which this cluster isn't, and its leader election cost
  etcd writes on orange1. User pods use the default scheduler.
