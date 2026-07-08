# Home Assistant

## Helm Chart

https://github.com/pajikos/home-assistant-helm-chart

https://artifacthub.io/packages/helm/helm-hass/home-assistant/


All values
https://github.com/pajikos/home-assistant-helm-chart/blob/main/charts/home-assistant/values.yaml

## Networking

Traffic reaches this app through the Cloudflare Tunnel (`cloudflared`, namespace
`cloudflare`), not the MetalLB IP directly — its config forwards all
`*.germanium.cz` hostnames to Traefik's `websecure` entrypoint regardless of
host, and DNS for `homeassist.germanium.cz` is a CNAME to the tunnel
(`f14686c6-...cfargotunnel.com`), not `172.31.1.34`.

Routing uses Gateway API via the chart's native `httpRoute` support
(`home-assistant.httpRoute` in `values.yaml`) instead of an Ingress. The
HTTPRoute attaches to `traefik/traefik-gateway-tls-tunnel`
(`apps/traefik/addons/gateway-tls-tunnel.yaml`) rather than the regular
`traefik-gateway-tls` — external-dns only reads its `target` override
annotation from the Gateway object, never from HTTPRoute, so tunnel-routed
apps need a Gateway carrying that tunnel target, separate from the one
direct-IP apps (e.g. esphome) use. `traefik-gateway-tls-tunnel` is shared and
also intended for other Cloudflare-tunneled apps (n8n, paperless) when they
migrate off Ingress.

No HTTP (port 80) redirect route is needed: `cloudflared` only forwards to
Traefik's HTTPS entrypoint, and Cloudflare's edge already handles the
http→https upgrade before traffic reaches the tunnel.

The chart's own `ingress` is disabled (`home-assistant.ingress.enabled: false`).
