# NFS Atlas

## Reclaim policy: Retain

Volumes use reclaim policy `Retain` (set on 2026-11-19, after a PVC deletion had wiped data). Deleting a PVC
no longer deletes its data: the PV becomes `Released` and its folder stays on the NAS until it's removed by hand.

Changing StorageClass settings needs the StorageClass to be recreated, because its parameters can't be edited:

```bash
kubectl delete storageclass nfs-atlas   # existing PVs and PVCs are not affected
# Argo CD (selfHeal) recreates it from Git within a few minutes
```

### Cleaning up a released volume

Only do this when the data is no longer needed.

```bash
# 1. List released volumes and their NAS folders
kubectl get pv -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,CLAIM:.spec.claimRef.name,PATH:.spec.nfs.path | grep Released
# 2. Delete the folder on the NAS (UGOS file manager, or as root on the NAS)
# 3. Delete the PV record
kubectl delete pv <name>
```

The provisioner runs as `k8s-orange` (uid 1002), so it can't delete files that apps wrote as other users,
such as Postgres (uid 999). Delete those folders on the NAS itself.

Full backup and restore documentation: XWiki, *Projects / Orange K8s / Backup and Restore*.

## Helm
https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner/blob/master/charts/nfs-subdir-external-provisioner/values.yaml

## User & Group

k8s-orange


```bash
# Group
petr@atlas:/volume1$ cat /etc/group | grep 1000
k8s-nfs-group:x:1000:k8s-orange

# User
petr@atlas:/volume1$ cat /etc/passwd | grep 1002
k8s-orange:x:1002:100:UGREEN USER:/home/k8s-orange:/usr/sbin/nologin
```

```bash
# PVC ownership
petr@atlas:/volume1$ ls -al nfs/
total 16
drwxrwxrwx  3 root       root          4096 Aug 27 10:59 .
drwxr-xr-x 17 root       root          4096 Aug 27 06:10 ..
drwxrwxrwx  2 k8s-orange k8s-nfs-group 4096 Aug 27 10:59 nfs-atlas-atlas-nfs-test-pvc-pvc-bbfab9b4-ca2e-44c6-9622-85cfbc82fe70
```
