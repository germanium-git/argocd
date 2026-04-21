# gateway-api-demo

Demo application showcasing Kubernetes Gateway API features using Traefik as the gateway engine.

**Namespace:** `gw-api-demo`  
**URL:** https://gwapidemo.germanium.cz

## What it demonstrates

- **HTTP → HTTPS redirect** via `RequestRedirect` filter (HTTPRoute on port 80)
- **TLS termination** at the gateway using `germanium-cz-prod-tls` cert from the `default` namespace (cross-namespace reference via `ReferenceGrant`)
- **URL path rewrite** via `URLRewrite` filter — strips `/api` prefix before forwarding to the backend
- **DNS registration** via explicit `DNSEndpoint` CRD (external-dns `crd` source)

## Architecture

```
Internet
  │
  ▼
external-dns (DNSEndpoint) → gwapidemo.germanium.cz → 172.31.1.34 (MetalLB)
  │
  ▼
traefik-gateway (port 80)     → HTTPRoute: whoami-http-redirect  → 301 redirect to https
traefik-gateway-tls (port 443/8443) → HTTPRoute: whoami-https    → whoami pods
  │
  ├── /api/*  →  URLRewrite (strip /api prefix)  →  whoami:80
  └── /*      →  direct                          →  whoami:80
```

**Gateways** (namespace: `traefik`):
- `traefik-gateway` — HTTP listener (port 80), handles redirect
- `traefik-gateway-tls` — HTTPS listener (port 8443), TLS terminated with `germanium-cz-prod-tls`

**Backend:** `traefik/whoami:v1.10.3` — echoes request headers, method, path, and remote IP.

## Testing

### Basic HTTPS access
```bash
curl https://gwapidemo.germanium.cz/
```
Returns whoami output showing headers as received by the backend (path: `/`).

### HTTP → HTTPS redirect
```bash
curl -v http://gwapidemo.germanium.cz/
# Expect: 301 redirect to https://gwapidemo.germanium.cz/
```

### URL path rewrite
```bash
curl https://gwapidemo.germanium.cz/api/anything
```
The `/api` prefix is stripped — the backend receives the request at `/anything`, not `/api/anything`.
Verify in the whoami response: look for `RequestURI: /anything`.

```bash
curl https://gwapidemo.germanium.cz/api/
# Backend sees: RequestURI: /
```

### Direct path (no rewrite)
```bash
curl https://gwapidemo.germanium.cz/some/path
# Backend sees: RequestURI: /some/path
```

## Key manifests

| File | Purpose |
|------|---------|
| `deployment.yaml` | whoami deployment (2 replicas) + Service |
| `httproute-http.yaml` | HTTP→HTTPS redirect via Gateway `traefik-gateway` |
| `httproute-https.yaml` | HTTPS routing + URL rewrite via Gateway `traefik-gateway-tls` |
| `dnsendpoint.yaml` | Explicit DNS A record → 172.31.1.34 (external-dns CRD source) |
| `../traefik/addons/gateway-tls.yaml` | HTTPS Gateway with TLS config |
| `../traefik/addons/referencegrant.yaml` | Allows traefik ns to reference cert secret in default ns |
