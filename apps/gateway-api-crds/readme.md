# gateway-api-crds

Single owner of the core Gateway API CRDs (`gateway.networking.k8s.io`), so that Traefik, Istio and
Envoy Gateway don't each install their own (possibly differing) copy and fight over ownership.

`addons/gateway-api-experimental-install.yaml` is vendored, unmodified, from the upstream
[kubernetes-sigs/gateway-api](https://github.com/kubernetes-sigs/gateway-api) release — currently
**v1.6.0**, **experimental channel** (a superset of the standard channel: adds `TLSRoute`,
`TCPRoute`, `UDPRoute`, `BackendTLSPolicy` and `ListenerSet`).

## Why experimental channel

`ListenerSet` and `TLSRoute` only exist in the experimental channel. Traefik's own bundled CRDs
(standard channel only) do not include them.

## Upgrading

Download the new release's `experimental-install.yaml` and overwrite the vendored file:

```bash
curl -sL https://github.com/kubernetes-sigs/gateway-api/releases/download/vX.Y.Z/experimental-install.yaml \
  -o apps/gateway-api-crds/addons/gateway-api-experimental-install.yaml
```

Check the release notes for breaking CRD changes before bumping.

## Consumers

- `apps/traefik` — `skipCrds: true` on its Helm source, relies on these CRDs.
- `apps/istio` — Istio's `base` chart does not bundle Gateway API CRDs, relies on these.
- `apps/envoy-gateway` — `gateway-crds-helm` dependency has `crds.gatewayAPI.enabled: false`, relies on these.
