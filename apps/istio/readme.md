# istio

Istio installed in **Gateway API mode only** — no service mesh, no sidecar injection,
no `istio-ingressgateway` workload. This is purely an evaluation of Istio as a second
Gateway API engine alongside Traefik.

**Namespace:** `istio-system`
**GatewayClass:** `istio` (controller name `istio.io/gateway-controller`)

## How it works

- `base` + `istiod` charts only (no `gateway`/ingressgateway chart, no injection labels on any namespace).
- Istio's Gateway API deployment controller (enabled by default) auto-provisions a
  Deployment + Service (type `LoadBalancer`, via MetalLB) for every `Gateway` resource
  with `gatewayClassName: istio` — there's no static gateway Deployment to look for.
- The `istio` `GatewayClass` is created automatically by istiod at startup, once the
  Gateway API CRDs are present (from `apps/gateway-api-crds`). Verify with
  `kubectl get gatewayclass istio`.
- Istio's `base` chart does **not** bundle Gateway API CRDs — it depends entirely on
  `apps/gateway-api-crds`.

## Addons

- `addons/gateway.yaml` — smoke-test `Gateway` (HTTP listener, port 80), routed to by
  `apps/gateway-api-demo/httproute-istio.yaml` (`gwapidemo-istio.germanium.cz`).
- `addons/servicemonitor-istiod.yaml` — control-plane metrics (istiod `/metrics` on
  port 15014).
- `addons/podmonitor-gateways.yaml` — data-plane metrics for any auto-provisioned
  gateway proxy pod, matched via the `istio.io/gateway-name` label (works across
  namespaces, so it covers future Gateways too).
- `addons/grafana-dashboard.yaml` — official "Istio Control Plane Dashboard"
  (grafana.com ID 7645).

## Verifying

```bash
kubectl get pods -n istio-system
kubectl get gatewayclass istio
kubectl get gateway -n istio-system istio-gateway -o yaml   # check status.addresses got an IP
curl http://gwapidemo-istio.germanium.cz/
```

If `external-dns` doesn't pick up the Gateway's address automatically (its
`gateway-httproute` source needs `status.addresses` populated), add
`external-dns.alpha.kubernetes.io/target: "<ip>"` on `addons/gateway.yaml`, the same
workaround already used on Traefik's Gateway.
