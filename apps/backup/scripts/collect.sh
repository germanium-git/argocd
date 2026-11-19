#!/bin/bash
# Collects everything the nightly backup needs into /staging, for restic to pick up.
#   /staging/data/       etcd snapshot, cluster certs, Sealed Secrets keys, Postgres dumps, SQLite copies
#   /staging/paths.txt   NAS folders of the application volumes to back up
# Any failure stops the job, so a broken backup is never reported as a success.
set -euo pipefail

S=/staging
D=$S/data
mkdir -p "$D/etcd" "$D/pki" "$D/sealed-secrets" "$D/postgres" "$D/sqlite" "$S/tmp"
log() { echo "$(date -u +%FT%TZ) collect: $*"; }
fail() { log "ERROR: $*"; exit 1; }

# 1. etcd snapshot, written and verified by the earlier init containers
[ -s "$S/etcd-snapshot.db" ] || fail "etcd snapshot missing"
mv "$S/etcd-snapshot.db" "$D/etcd/snapshot.db"
log "etcd: $(du -k "$D/etcd/snapshot.db" | cut -f1) KiB"

# 2. Cluster certificates, including the CA private keys (the restic repository is encrypted)
cp -a /host-pki/. "$D/pki/"
log "pki: $(find "$D/pki" -type f | wc -l) files"

# 3. Sealed Secrets keys: without them, the SealedSecrets in Git can't be decrypted after a rebuild
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml > "$D/sealed-secrets/keys.yaml"
keys=$(kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o name | wc -l)
[ "$keys" -gt 0 ] || fail "no Sealed Secrets keys found"
log "sealed-secrets: $keys keys"

# 4. Postgres: dumps made by each server's own pg_dump, so no database password leaves its namespace
for target in paperless/paperless-postgres-0 xwiki/xwiki-postgres-0; do
  ns=${target%/*}
  pod=${target#*/}
  dbs=$(kubectl exec -n "$ns" "$pod" -- sh -c \
    'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "select datname from pg_database where datallowconn and not datistemplate"')
  for db in $dbs; do
    out="$D/postgres/$ns-$db.dump"
    kubectl exec -n "$ns" "$pod" -- sh -c "pg_dump -U \"\$POSTGRES_USER\" -d '$db' -Fc" > "$out"
    [ "$(head -c 5 "$out")" = "PGDMP" ] || fail "dump $out is not a valid pg_dump file"
    log "postgres: $ns/$db $(du -k "$out" | cut -f1) KiB"
  done
  # Roles and their permissions, needed when restoring into a fresh server
  kubectl exec -n "$ns" "$pod" -- sh -c 'pg_dumpall -U "$POSTGRES_USER" --globals-only' > "$D/postgres/$ns-globals.sql"
done

# 5. Application volumes: NAS folders of bound PVs, minus the ones that are skipped on purpose
#    - monitoring, logging: metrics and logs, replaceable and large
#    - *postgres*: raw database files, covered by the dumps above
#    - motioneye-lib: camera recordings
kubectl get pv -o jsonpath='{range .items[?(@.status.phase=="Bound")]}{.spec.claimRef.namespace}{" "}{.spec.claimRef.name}{" "}{.spec.nfs.path}{"\n"}{end}' |
  while read -r ns pvc path; do
    case "$ns/$pvc" in
      monitoring/*|logging/*|*postgres*|*motioneye-lib*) continue ;;
    esac
    [ -n "$path" ] || continue
    dir="/nfs/${path#/volume1/nfs/}"
    [ -d "$dir" ] || fail "volume folder $dir for $ns/$pvc not found"
    echo "$dir"
  done > "$S/paths.txt"
log "volumes: $(wc -l < "$S/paths.txt") folders"

# 6. SQLite: consistent copies of the databases inside those volumes
python3 /scripts/sqlite_copy.py "$S/paths.txt" "$D/sqlite" "$S/tmp"

log "done, staged $(du -sk "$D" | cut -f1) KiB"
