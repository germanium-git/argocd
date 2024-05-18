# Postgres

## StorageClass

The storagClass `nfs-pgsql` is used in this case which allows the container run with the security context using the values below to chnage ownership of the nfs mounted volume.
SecurityContext parameters
- runAsUser: 1024
- runAsGroup: 100
- fsGroup: 100


### Synology as a NFS Server

See more information on the options and relevant UIDs and GIDs used on the box:
https://discourse.osmc.tv/t/using-nfs-with-synology/36776


## Access

Read write connection `pgsql-awx.pgsql.svc.cluster.local`

The following commands assume the name override to "awx" ending up with the name `pgsql-awx`. Replace with a relevant name if needed.
```
# Get password
export POSTGRES_PASSWORD=$(kubectl get secret --namespace pgsql pgsql-awx -o jsonpath="{.data.postgres-password}" | base64 -d)

# Spin up a clinet POD and run the command to access the database
kubectl run pgsql-postgresql-client \
    --rm --tty -i --restart='Never' --namespace pgsql \
    --image docker.io/bitnami/postgresql:16.2.0-debian-12-r18 \
    --env="PGPASSWORD=$POSTGRES_PASSWORD" \
    --command -- psql --host pgsql-awx -U postgres -d postgres -p 5432
```
