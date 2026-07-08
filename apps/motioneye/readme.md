# motioneye

## Networking

Traffic reaches this app through the Cloudflare Tunnel (`cloudflared`, namespace
`cloudflare`), not the MetalLB IP directly. Its config forwards all
`*.germanium.cz` hostnames to Traefik's `websecure` entrypoint regardless of
host, so no tunnel-side configuration was needed to add this hostname.

Routing uses a hand-written Gateway API HTTPRoute
(`apps/motioneye/addons/httproute-https.yaml`, the chart has no native Gateway
API support) attached to `traefik/traefik-gateway-tls-tunnel`
(`apps/traefik/addons/gateway-tls-tunnel.yaml`) rather than the regular
`traefik-gateway-tls` — external-dns only reads its `target` override
annotation from the Gateway object, never from HTTPRoute, so tunnel-routed
apps need a Gateway carrying that tunnel target, separate from the one
direct-IP apps (e.g. esphome) use.

Before this migration, `motioneye.germanium.cz` was a DNS-only (non-proxied)
CNAME to `traefik.germanium.cz` (itself an A record to the MetalLB IP), and
the Ingress served plain HTTP with no TLS at all. The HTTPRoute's
`cloudflare-proxied` annotation makes external-dns flip that record to a
proxied CNAME pointing at the tunnel, same as `homeassist.germanium.cz`. This
also means motioneye is now **HTTPS-only** (TLS terminated at the shared
Gateway using the `germanium.cz` wildcard cert) — cloudflared only forwards to
Traefik's HTTPS entrypoint, so there is no plain-HTTP path anymore.

Note: motioneye serves continuous MJPEG camera streams. Cloudflare's proxy
has known rough edges with long-lived/streaming HTTP connections (idle
timeouts, buffering) for external viewers going through the tunnel. LAN
clients are unaffected since local DNS resolves this host straight to the
origin IP, bypassing Cloudflare entirely. Worth testing live view remotely
after cutover.

The chart's own `ingress` is disabled (`motioneye.ingress.enabled: false`).
