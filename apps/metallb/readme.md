# MetalLB

Helm umbrella chart deploying MetalLB 0.16.1 on the orange K8s cluster in dual L2+BGP mode.

## Modes

| Pool | Range | Mode | Advertised via |
|---|---|---|---|
| `first-pool` | 172.31.1.30–172.31.1.49 | L2 | ARP (`L2Advertisement`) |
| `bgp-pool` | 10.100.0.1–10.100.0.254 | BGP | /32 host routes (`BGPAdvertisement`) |

## BGP

- MetalLB ASN: **64501** — SRX300 ASN: **65100**
- Peer: SRX300 at `172.31.1.1` (irb.777, trust zone)
- BGP neighbors (one per node): `172.31.1.50`, `172.31.1.51`, `172.31.1.52`
- Backend: `frrk8s` (default in 0.16.x — do **not** set `speaker.frr.enabled: true`)

## ArgoCD

CRD resources (`IPAddressPool`, `BGPPeer`, `BGPAdvertisement`, `L2Advertisement`) live in `templates/` so ArgoCD renders and manages them via Helm with prune + self-heal.

## SRX firewall note

The `Select-ISP` filter on `irb.777` does policy-based routing for all LAN traffic. Any new IP pool must have a `then accept` exemption term added **before** the `BeskydNET` catch-all term, otherwise LAN clients cannot reach it.

## Links

- [MetalLB Helm chart values](https://github.com/metallb/metallb/blob/main/charts/metallb/values.yaml)
- [BGP with MetalLB and pfSense](https://natarajmb.com/2025/02/kubernetes-services-over-bgp-with-metallb-and-pfsense/)
