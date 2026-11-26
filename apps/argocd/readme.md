# ArgoCD

## Helm

Source:

https://artifacthub.io/packages/helm/argo/argo-cd
https://github.com/argoproj/argo-helm


## Installation

### Sealed secret

There's one secret that contains the Slack API token that allows the notifier to send messages to Slack.
The secret is not created by Helm as the value of `notifications.secret.create` is set to false and the secrte has to be created by some other means.

```
kubectl create secret generic argocd-notifications-secret -n argocd \
    --from-literal=slack-token=xoxb-111111-2222222-33333333 \
    --dry-run=client -o yaml | kubeseal --format=yaml > argocd-notification-sealedsecret.yaml
```
Check the value of the secret.

```
kubectl get secret --namespace argocd argocd-notifications-secret -o jsonpath="{.data.slack-token}" | base64 -d
```

### Renewing the Slack token

Run `apps/argocd/renew-secrets.sh` from the repo root in your own terminal. It reads the token with
hidden input, so don't run it via Claude Code's `!`. It needs `kubectl`, `kubeseal` and `gh` logged in.

It walks you through the Slack UI (app **argocd** → OAuth & Permissions → reissue the token) and
checks the new token with Slack's `auth.test` API. It then re-seals it into
`addons/argocd-notification-sealedsecret.yaml` **and** into the Alertmanager copy
`../kube-prometheus-stack/templates/alertmanager-slack-bot-sealedsecret.yaml`, opens a PR and waits
until the new value is live. It also restarts `argocd-notifications-controller`.
The `argocd` app syncs manually: after the merge, sync it in the UI while the script is waiting.

## Web UI

Navigate to https://argocd.germanium.cz/

username: admin
Use the decoded secrte as the password:

```
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

## Notifications

Add the following annotations to each app for which the notifications should be generated in Slack. The value points to the respective slack channel.

notifications.argoproj.io/subscribe.on-deployed.slack=argo
notifications.argoproj.io/subscribe.on-health-degraded.slack=argo
notifications.argoproj.io/subscribe.on-sync-failed.slack=argo
notifications.argoproj.io/subscribe.on-sync-status-unknown.slack=argo
