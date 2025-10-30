# AWX-operator

## Releases
https://github.com/ansible/awx-operator/releases

https://github.com/ansible-community/awx-operator-helm/blob/main/charts/awx-operator/values.yaml

## Postgres

### External database

There is an option to use an external Postgres database by defining the value `postgres.enabled: true`

More information can be found at [database-configuration.md](https://github.com/ansible/awx-operator/blob/devel/docs/user-guide/database-configuration.md#database-configuration)

To use an external Postgres create a secret in which password and other connection details for the external database are provided.
```
cat secrets.yaml| kubeseal --format=yaml > sealedsecret.yaml
```

### Internal database

Does not work on my cluster due to the constreints with unsupported securityContext for postgres container which can't chnage ownership of NFS mounted PVC.

https://github.com/ansible/awx-operator/pull/1728


## Additional Kubernetes Resources

The [AWX.extraDeploy] (https://github.com/ansible/awx-operator/blob/devel/.helm/starter/README.md#additional-kubernetes-resources) section allows the creation of additional Kubernetes resources.


## AWX Server
Create the AWS server by applying the manifest from awx-demo.yaml
