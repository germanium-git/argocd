# NFS Atlas

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
