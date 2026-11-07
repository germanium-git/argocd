# ArgoCD

## Tips & Tricks

### App can't be deleted

Edit the namespace of argocd, check if there is a finalizer field in the spec, delete that field and the content of the field.

https://stackoverflow.com/questions/71164538/argocd-application-resource-stuck-at-deletion

## Sync policy

Apps sync **automatically** (`syncPolicy.automated` with `prune` + `selfHeal`): a merge to `main` is
deployed within ~3 minutes, and manual `kubectl` changes to managed objects are reverted.
Review Dependabot PRs before merging: merging = deploying.

Manual sync on purpose:

| App | Why |
|---|---|
| `argocd` | Argo CD manages itself; a bad change could break the tool needed to fix it. |
| `pgsql` | Runs `bitnami/postgresql:latest` with PG 18 data; an unexpected pod restart may pull a different image. |

Application specs (`apps/*/application.yaml`) are **not** managed by Argo CD (no app-of-apps):
after changing one, apply it with `kubectl apply -f apps/<app>/application.yaml`.
