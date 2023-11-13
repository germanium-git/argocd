# ArgoCD

## Tips & Tricks

### App can't be deleted

Edit the namespace of argocd, check if there is a finalizer field in the spec, delete that field and the content of the field.

https://stackoverflow.com/questions/71164538/argocd-application-resource-stuck-at-deletion
