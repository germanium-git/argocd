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
