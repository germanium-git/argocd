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

## Incident 2026-11-23: UGOS share permissions broke NFS access

### What happened

On 2026-11-23 at 17:14, someone saved the permissions of the `nfs` shared folder in UGOS (Files →
`nfs` → Properties → Permissions → Confirm) while logged in as `vojta`. UGOS applied them to every
subfolder and file. From then on:

- Pods that don't run as root and aren't uid 1000/1002 lost access entirely. Postgres (uid 70) in
  paperless and xwiki and Loki (uid 10001) were affected. Fixed in Git by running them with
  `runAsGroup: 1000` (PRs #211–#213): the share ACL grants `k8s-nfs-group` (gid 1000), and the NAS's
  nfsd runs with `manage-gids`, so the group has to be the primary group. `supplementalGroups` and
  `fsGroup` are ignored.
- Even with gid 1000, access failed **intermittently**: the nightly backup failed on 2026-11-24 and
  2026-11-26, and both Postgres servers threw `Permission denied` for minutes at a time.

### Root cause

UGOS marks every file and folder it manages with a hidden flag: bit `0x02` in the second byte of the
`ug.archive_bit` extended attribute, e.g. `0x40020000`. `ls -l` on the NAS shows it as a `+` after
the mode. A flagged entry takes its permissions from the ACL on the share folder, so the NAS has to
look up through the parent folders to find that ACL. Over NFS (export uses `no_subtree_check`), a file
whose inode was evicted from the NAS's cache is opened without its parent path, so the ACL can't be
resolved and access is **denied for everyone except root**. Any local access on the NAS reconnects the
file and makes it work again. That is why it looked random. New files created inside a flagged
folder inherit the flag.

Proven with `echo 2 > /proc/sys/vm/drop_caches` on the NAS: flagged files failed immediately, and
files without the flag worked with any mode (`700` or `777`) and any owner. Changing modes or owners
(`chmod 777`, `chown k8s-orange`) does **not** help, and chown would break Postgres anyway, because it
refuses to start when its data directory belongs to another user.

While an entry is flagged, `stat` on the NAS shows modes made up by UGOS (e.g. `000`), not the real
ones.

### Fix applied on 2026-11-26

The flag was cleared from every folder under `/volume1/nfs` with [`tools/unflag.py`](tools/unflag.py),
run as root on the NAS. The script also gives the owner rw (+x on dirs). Before changing anything it
saves each entry's old flag value and mode to `/root/acl-pilot/` on the NAS.

The share root `/volume1/nfs` still carries its flag (`0x00030000`) and the ACL from the UGOS UI.

### If it happens again

Symptoms: `KubeJobFailed` for the `backup` job, `Permission denied` in a Postgres or Loki log, while
the same file can be read on the NAS.

```bash
# On the NAS (ssh -i ~/.ssh/orangePiMac petr@172.31.1.6)

# 1. Find flagged entries (2nd byte has bit 0x02). Prints the count per top-level folder.
sudo find /volume1/nfs -mindepth 1 -xdev -print0 \
  | sudo xargs -0 getfattr -n ug.archive_bit -e hex --absolute-names 2>/dev/null \
  | awk -F'[ =]' '/^# file:/{f=$3} /^ug.archive_bit=0x..[0-9a-f][2367abef]/{split(f,a,"/"); n[a[4]]++} END{for(k in n) print n[k], k}'

# 2. Quick relief until step 3 is done: a local stat of every file reconnects them (takes ~0.2 s)
sudo find /volume1/nfs -xdev -printf '%m\n' >/dev/null

# 3. Clear the flag in each affected folder (copy tools/unflag.py to the NAS first if it isn't there)
sudo python3 /root/acl-pilot/unflag.py <folder name under /volume1/nfs>
# or every folder:
cd /volume1/nfs && for d in */; do sudo python3 /root/acl-pilot/unflag.py "${d%/}"; done

# 4. Verify: this must NOT break anything (no re-warm afterwards)
sync; echo 2 | sudo tee /proc/sys/vm/drop_caches
```

Then restart any Postgres pod that logged errors, delete the failed backup job
(`kubectl -n backup delete job <name>`) and run one by hand
(`kubectl -n backup create job --from=cronjob/backup backup-manual-$(date +%Y%m%d)`).

To undo a run: `sudo setfattr --restore=/root/acl-pilot/<folder>.<timestamp>.xattr`.

### Keep in mind

- **New PVCs inherit the flag** from the share root. Run `unflag.py` on a new PVC's folder once it
  has been created.
- **Don't press Confirm on the `nfs` folder's Properties in UGOS.** Close the dialog with Cancel.
  Confirming applies the permissions to all subfolders again and brings the flag back everywhere.
- Changing the NFS rule's Squash setting doesn't help: admin and guest are also checked against the
  ACL; only root is exempt.

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
