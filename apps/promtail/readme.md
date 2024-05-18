# Promtail

## Installation

### All values

https://github.com/grafana/helm-charts/blob/main/charts/promtail/values.yaml


### Listen to Syslog TCP

https://github.com/grafana/helm-charts/blob/6e6213c281b7558cb781cf6b3ca7573fe063f7d9/charts/promtail/README.md?plain=1#L194


UDP is unsuported :-(

workarounds:
https://github.com/byt3-m3/python_code_practice/blob/master/networking_scripts/sys_logger.py

https://www.youtube.com/watch?v=FmkLeX4Udm0&ab_channel=CBax


How to send message to syslog server?
https://www.techiecorner.com/1496/how-to-send-message-to-syslog-server/

TCP version:
❯ nc -w0 -t 172.31.1.40 514 <<< "testing again from my home machine"