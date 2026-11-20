# smartctl-exporter

Helm umbrella chart for [prometheus-smartctl-exporter](https://github.com/prometheus-community/smartctl_exporter).
A privileged DaemonSet reads the SMART data of each node's NVMe disk and exposes it to Prometheus
(ServiceMonitor and PrometheusRule labelled `release: kube-prometheus-stack`). Alerts go to Slack
`#alerts-k8s` like all other warning and critical alerts.

## Alerts

| Alert | Fires when | Severity |
|---|---|---|
| `NvmeWearHigh` | `Percentage Used` ≥ 80% | warning |
| `NvmeWearCritical` | `Percentage Used` ≥ 95% | critical |
| `NvmeHealthMissing` | a node reports no NVMe data for 1 hour | warning |
| `SmartCTLDeviceAvailableSpareUnderThreshold` | spare blocks below the vendor threshold | warning |
| `SmartCTLDeviceMediaErrors`, `SmartCTLDeviceCriticalWarning`, `SmartCTLDeviceStatus` | the disk reports errors | critical |
| `SmartCTLDDeviceTemperature` | above 60 °C | warning |

`SmartCTLDInterfaceSlow` is disabled: the Orange Pi M.2 slot has fewer PCIe lanes than the disks support.

`Percentage Used` is the vendor's estimate of rated write endurance consumed. Reaching 100% is not a
failure, but the disk is then out of its guaranteed life. The figure that shows real degradation is
`Available Spare`.

## Baseline (2026-11-20)

| Node | Disk | Used | Written | Power-on hours |
|---|---|---|---|---|
| orange1 | Samsung MZALQ256HAJD | 45% | 13.7 TB | 24,757 |
| orange2 | Samsung MZAL4256HBJD | 4% | 8.2 TB | 6,520 |
| orange3 | Samsung MZAL4256HBJD | 3% | 5.4 TB | 6,386 |

orange1 wears fastest because etcd writes about 7 GiB a day there; the nightly backup adds about 0.3 GiB.

## Useful queries

```promql
smartctl_device_percentage_used                       # wear per node
rate(smartctl_device_data_units_written[1d]) * 512000 * 86400   # bytes written per day
```

## Install

Not part of an app-of-apps: after the first merge, `kubectl apply -f apps/smartctl-exporter/application.yaml`.
