#!/usr/bin/env bash
# Renew the Slack bot token of the 'argocd' Slack app. The same token is sealed twice:
#   addons/argocd-notification-sealedsecret.yaml → argocd/argocd-notifications-secret (#argo)
#   ../kube-prometheus-stack/templates/alertmanager-slack-bot-sealedsecret.yaml → monitoring (#alerts-k8s)
# Walks you through the Slack UI, re-seals both copies, opens the PR and waits for the sync.
#
#   apps/argocd/renew-secrets.sh

source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/renew-common.sh"

renew_slack() {
  help "Argo CD notifications and Alertmanager both post as the argocd bot."
  TOTAL=6
  preflight_cluster
  need curl
  slack_bot_token_steps "argocd" "A0655N02BGW" \
    "Not the 'AlertManager' app: Alertmanager also posts with the argocd bot token."

  step "Paste the token"
  local token; read_slack_bot_token token
  seal_into apps/argocd/addons/argocd-notification-sealedsecret.yaml argocd argocd-notifications-secret slack-token "$token"
  seal_into apps/kube-prometheus-stack/templates/alertmanager-slack-bot-sealedsecret.yaml monitoring alertmanager-slack-bot token "$token"
  unset token
  APPS=(argocd kube-prometheus-stack)
  RESTARTS=("argocd|argocd-notifications-controller")

  finish_sealed slack-argocd "Renew Slack bot token of the argocd app (Argo CD + Alertmanager)"

  step "Verify"
  help "Alertmanager reads the token file on every send; no restart needed."
  do_ "The next sync notification should appear in Slack #argo"
  do_ "Test alert: apps/kube-prometheus-stack/readme.md (amtool alert add …) → #alerts-k8s"
  update_bitwarden "argocd Slack bot token"
  pause
  ok "argocd Slack bot token renewed."
}

MENU=("slack|Slack bot token (notifications + Alertmanager)|renew_slack")
renew_main "argocd: renew the Slack bot token" "$@"
