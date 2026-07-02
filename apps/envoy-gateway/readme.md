# envoy-gateway

Envoy Gateway installed as a second/third Gateway API engine alongside Traefik and
Istio, purely for evaluation.

**Namespace:** `envoy-gateway-system`
**GatewayClass:** `envoy-gateway` (controller name `gateway.envoyproxy.io/gatewayclass-controller`)

## How it works

- Two Helm dependencies: `gateway-helm` (control plane) and `gateway-crds-helm`
  (Envoy Gateway's own CRDs — `gateway.envoyproxy.io`, e.g. `EnvoyProxy`,
  `ClientTrafficPolicy`, `SecurityPolicy`).
- `gateway-helm`'s embedded `crds` subchart is disabled (`crds.enabled: false`) —
  it would otherwise install both the core Gateway API CRDs *and* Envoy Gateway's own
  CRDs unconditionally (they live in a Helm `crds/` folder, not gated by values).
  Instead, `gateway-crds-helm` is used with `crds.gatewayAPI.enabled: false` /
  `crds.envoyGateway.enabled: true`, so only Envoy Gateway's own CRDs come from this
  app — the core Gateway API CRDs come from `apps/gateway-api-crds`.
- Unlike Traefik/Istio, Envoy Gateway does **not** auto-create a default
  `GatewayClass` — `addons/gatewayclass.yaml` creates it explicitly.
- Envoy Gateway auto-provisions an Envoy proxy Deployment + Service (type
  `LoadBalancer`, via MetalLB) for every `Gateway` resource with
  `gatewayClassName: envoy-gateway` — there's no static gateway Deployment to look for.

## Addons

- `addons/gatewayclass.yaml` — the `envoy-gateway` `GatewayClass`.
- `addons/gateway.yaml` — smoke-test `Gateway` (HTTP listener, port 80), routed to by
  `apps/gateway-api-demo/httproute-envoy.yaml` (`gwapidemo-envoy.germanium.cz`).
- `addons/servicemonitor-envoy-gateway.yaml` — control-plane metrics (`envoy-gateway`
  Service, `/metrics` on port 19001).
- `addons/podmonitor-proxies.yaml` — data-plane metrics for any auto-provisioned
  Envoy proxy pod, matched via the `gateway.envoyproxy.io/owning-gateway-name` label
  (works across namespaces, so it covers future Gateways too), scraping
  `/stats/prometheus` on port 19001.
- `addons/grafana-dashboard.yaml` — official Envoy Gateway dashboards
  (`envoy-gateway-global.json`, `envoy-proxy-global.json`, vendored from the
  `envoyproxy/gateway` repo at the pinned chart version).

## Verifying

```bash
kubectl get pods -n envoy-gateway-system
kubectl get gatewayclass envoy-gateway
kubectl get gateway -n envoy-gateway-system envoy-gateway -o yaml   # check status.addresses got an IP
curl http://gwapidemo-envoy.germanium.cz/
```

If `external-dns` doesn't pick up the Gateway's address automatically (its
`gateway-httproute` source needs `status.addresses` populated), add
`external-dns.alpha.kubernetes.io/target: "<ip>"` on `addons/gateway.yaml`, the same
workaround already used on Traefik's Gateway.

## Upgrading

The chart version is pinned in `Chart.yaml`/`Chart.lock`. When bumping it, re-check
`gateway-crds-helm`'s values (`crds.gatewayAPI.channel`, currently `experimental` by
chart default) still lines up with the channel vendored in `apps/gateway-api-crds`.
