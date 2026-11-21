# Telegraf (SNMP → InfluxDB Cloud)

Polls SNMP and writes to **InfluxDB Cloud 2** (`https://westeurope-1.azure.cloud2.influxdata.com`, org ID
`15297d32235a99a0`, bucket `Network`, 30-day retention). The bucket and the write-only `telegraf` token are managed
in `germanium-git/influxdb-cloud` (Terraform). Until Nov 2026 it wrote to the self-hosted InfluxDB on apollo
(`germanium-git/temp-monitor`). Moved here from Flux (`orange-k8s`) in Nov 2026.

| Agent | Device | Data |
|---|---|---|
| `172.31.1.1:161` (v2c) | SRX300 | `IF-MIB::ifXTable` per `ifName` |
| `172.31.1.197:161` (v1) | Dell switch | `IF-MIB::ifXTable` per `ifIndex` |
| `192.168.1.1:161` (v2c) | RUT240 LTE modem | signal, operator, cell, SINR/RSRP/RSRQ, bytes |

## Layout

- `telegraf.conf` → ConfigMap `telegraf-config-<hash>`; `mibs/` → ConfigMap `telegraf-mibs-<hash>` mounted at
  `/usr/share/snmp/mibs` (gosmi translator). Only the MIBs the config needs (IF-MIB and its imports) are kept;
  `sysName.0` is read via `SNMPv2-MIB` (same OID as RFC1213-MIB). Adding a MIB: drop it in `mibs/` and list it
  in `kustomization.yaml`. No hostPath / per-node copies any more.
- `telegraf-sealedsecret.yaml` → Secret `telegraf-secrets` (`INFLUXDB_TOKEN`, the write-only `telegraf` token from
  `germanium-git/influxdb-cloud`). Re-seal straight from the Terraform output (the token is never printed), run in
  this directory:
  ```bash
  (cd ../../../influxdb-cloud && terraform output -json writer_tokens) | jq -r .telegraf \
    | { read -r T; kubectl create secret generic telegraf-secrets -n telegraf --from-literal=INFLUXDB_TOKEN="$T" --dry-run=client -o yaml; } \
    | kubeseal --format yaml > telegraf-sealedsecret.yaml
  ```
- TLS to InfluxDB Cloud is verified (`insecure_skip_verify = false`).

## Monitoring

`inputs.internal` + `outputs.prometheus_client` (`:9273`, `internal_*` only, not sent to InfluxDB),
scraped by PodMonitor `telegraf`. Alerts (PrometheusRule `telegraf`):

- `TelegrafInfluxDBWriteErrors` – writes to InfluxDB failing for 15 min (InfluxDB was silently down
  for 6.5 months in 2026 because nothing alerted)
- `TelegrafSNMPGatherErrors` – an SNMP agent not answering for 30 min
- `TelegrafDown` – no telegraf target up for 10 min

## Test a config change

```bash
kubectl exec -n telegraf deploy/telegraf-deployment -- telegraf --config /etc/telegraf/telegraf.conf --test
```
