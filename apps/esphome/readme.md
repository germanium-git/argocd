# ESPHome

https://artifacthub.io/packages/helm/alekc/esphome

https://gitlab.com/alexander-chernov/helm/home-assistant


## Installation 

Everything is delivered through the `esphome` Argo CD Application (multi-source:
Helm chart from `apps/esphome` + raw manifests from `apps/esphome/addons`). Nothing
in this app needs to be applied manually anymore.

### Networking

Traffic is routed via Gateway API instead of an Ingress:

- `addons/httproute-http.yaml` — HTTP (port 80) on the shared `traefik/traefik-gateway`,
  redirects to HTTPS.
- `addons/httproute-https.yaml` — HTTPS on the shared `traefik/traefik-gateway-tls`,
  routes to the `esphome` Service (port 6052). TLS is terminated at that shared
  Gateway using the `germanium.cz` wildcard cert — it already covers
  `esphome.germanium.cz`.
- `addons/esphome-certificate-prod.yaml` / `-staging.yaml` — esphome's own
  cert-manager `Certificate`s, kept for parity with the previous Ingress setup.
  They are no longer consumed by routing (the shared wildcard cert handles TLS),
  but are still Argo-managed so they keep renewing.

The chart's own `ingress` is disabled (`esphome.ingress.enabled: false` in
`values.yaml`).

### Persistent storage

Update from October 2025 - the persistent storage does not longer utilize the local storage on the node orange3 but it uses the nfs-share and pvc provisioend as part of the storage-class nfs-atlas.
The container still needs to be run as root to avoid the problems as mentioned below:

The following two issues were observed when the container was run as nonRoot:

- First, from the logs "WARNING Cannot use icmplib because privileges are insufficient" causing the ping probes to be discarded and the remote device's status could not to come online in the portal.
- Second, more serious, the error "PermissionError: [Errno 13] Permission denied: '/.platformio'" received when compiling the image.


### The older approach with the local storage (obsolete)

Don't use this
```
k apply -f .\storage-class.yaml
k apply -f .\persistent-volume.yaml
```

## How to access

esphome.germanium.cz
