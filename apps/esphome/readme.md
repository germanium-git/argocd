# ESPHome

https://artifacthub.io/packages/helm/alekc/esphome

https://gitlab.com/alexander-chernov/helm/home-assistant


## Installation 

### Certificate

```
k apply -f .\esphome-certificate-prod.yaml
k apply -f .\esphome-certificate-staging.yaml

```

### Persistent storage

```
k apply -f .\storage-class.yaml
k apply -f .\persistent-volume.yaml
```

## How to access

esphome.germanium.cz
