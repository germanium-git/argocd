# shellcheck shell=bash
# Shared helpers for the guided secret renewal scripts (apps/*/renew-secrets.sh).
# Source it; don't run it.
#
# For a SealedSecret: re-seal only the renewed key in place (kubeseal --raw), open a PR,
# wait until Argo CD has synced the new value into the cluster, restart the workloads
# that read it at startup.
#
# Secret values are read without echo, passed on stdin and compared with the cluster
# only as SHA-256 hashes. They are never printed, put on a command line or written to disk.

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ZONE="germanium.cz"
SYNC_TIMEOUT=900 # seconds to wait for Argo CD to deliver the new value

# ---------- output helpers ----------
if [[ -t 1 ]]; then
  B=$'\e[1m'; DIM=$'\e[2m'; C=$'\e[36m'; G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; N=$'\e[0m'
else
  B=""; DIM=""; C=""; G=""; Y=""; R=""; N=""
fi

STEP=0
TOTAL=0

title() { printf '\n%s══ %s ══%s\n' "$B$C" "$1" "$N"; }
step() { STEP=$((STEP + 1)); printf '\n%s[Step %d/%d] %s%s\n' "$B" "$STEP" "$TOTAL" "$1" "$N"; }
help() { printf '%s  ℹ %s%s\n' "$DIM" "$1" "$N"; }
do_() { printf '  %s→%s %s\n' "$C" "$N" "$1"; }
ok() { printf '  %s✔ %s%s\n' "$G" "$1" "$N"; }
warn() { printf '  %s⚠ %s%s\n' "$Y" "$1" "$N"; }
fail() { printf '  %s✖ %s%s\n' "$R" "$1" "$N"; }
die() { fail "$1"; exit 1; }

pause() { read -rp "  ${DIM}Press Enter when done (Ctrl+C to abort)…${N} " _; }

confirm() { # confirm "question" [default y|n]
  local ans def="${2:-y}" hint="[Y/n]"
  [[ $def == n ]] && hint="[y/N]"
  read -rp "  $1 $hint " ans
  ans="${ans:-$def}"
  [[ $ans =~ ^[Yy] ]]
}

read_secret() { # read_secret VAR "prompt" [required-prefix]  (no echo)
  local _v
  while true; do
    read -rsp "  $2: " _v; echo
    _v="${_v#"${_v%%[![:space:]]*}"}"; _v="${_v%"${_v##*[![:space:]]}"}" # trim
    if [[ -z $_v ]]; then warn "Empty value, paste it again."; continue; fi
    if [[ -n ${3:-} && $_v != "$3"* ]]; then
      warn "Expected a value starting with '$3'. Copy it again."; continue
    fi
    break
  done
  printf -v "$1" '%s' "$_v"
}

open_url() {
  do_ "Open: ${B}$1${N}"
  if command -v wslview >/dev/null; then wslview "$1" >/dev/null 2>&1 || true
  elif command -v xdg-open >/dev/null; then xdg-open "$1" >/dev/null 2>&1 || true
  elif command -v open >/dev/null; then open "$1" >/dev/null 2>&1 || true
  fi
}

sha() { printf '%s' "$1" | sha256sum | cut -d' ' -f1; }

# curl with a secret header that never appears on the command line
curl_auth() { # curl_auth "Header: value" curl-args...
  local hdr="$1"; shift
  curl -fsS -o /dev/null --max-time 20 -H @<(printf '%s\n' "$hdr") "$@"
}

update_bitwarden() {
  do_ "Update the item in ${B}Bitwarden${N}${1:+: $1} (new value, today's date in the notes)"
}

# ---------- preflight ----------
need() { command -v "$1" >/dev/null || die "$1 is not installed."; }

preflight_gh() {
  need gh
  gh auth status >/dev/null 2>&1 || die "gh is not logged in. Run: gh auth login"
  GH_REPO=$(cd "$REPO_ROOT" && gh repo view --json nameWithOwner --jq .nameWithOwner) \
    || die "Could not resolve the GitHub repo of $REPO_ROOT."
  ok "GitHub repo: $GH_REPO"
}

preflight_cluster() {
  need kubectl; need kubeseal; need jq; need python3; need sha256sum; need git
  kubectl get ns argocd >/dev/null 2>&1 \
    || die "kubectl can't reach the cluster (context: $(kubectl config current-context 2>/dev/null || echo none))."
  kubeseal --fetch-cert >/dev/null 2>&1 || die "kubeseal can't fetch the Sealed Secrets certificate from the cluster."
  ok "Cluster: $(kubectl config current-context), Sealed Secrets controller reachable"
  preflight_gh

  cd "$REPO_ROOT"
  local branch; branch=$(git rev-parse --abbrev-ref HEAD)
  if [[ $branch != main ]]; then
    warn "You are on branch '$branch', not main."
    confirm "Continue on '$branch' anyway?" n || die "Switch to main first: git switch main"
  fi
  if ! git diff --quiet || ! git diff --cached --quiet; then
    warn "The working tree has uncommitted changes:"
    git status --short | sed 's/^/      /'
    confirm "Continue? Only the re-sealed files will be committed." n || exit 1
  fi
  if [[ $branch == main ]] && confirm "Pull the latest main first (git pull --ff-only)?"; then
    git pull --ff-only --quiet && ok "main is up to date."
  fi
}

# ---------- SealedSecret machinery ----------
CHANGED_FILES=()  # repo-relative files re-sealed in this run
CHECKS=()         # "ns|secret|key|sha256" expected in the cluster after sync
RESTARTS=()       # "ns|deployment" to restart once the new value is live
APPS=()           # Argo CD applications that deliver the files

# seal_into FILE NS NAME KEY VALUE: replace one encryptedData key in FILE (repo-relative)
seal_into() {
  local file="$1" ns="$2" name="$3" key="$4" value="$5" enc
  [[ -f $REPO_ROOT/$file ]] || die "Missing $file"
  enc=$(printf '%s' "$value" | kubeseal --raw --scope strict --namespace "$ns" --name "$name" --from-file=/dev/stdin) \
    || die "kubeseal failed for $ns/$name ($key)."
  python3 - "$REPO_ROOT/$file" "$key" "$enc" <<'PY' || die "Could not update key $key in $file."
import re, sys
path, key, enc = sys.argv[1:]
raw = open(path, "rb").read().decode()
pat = re.compile(r"^(\s+" + re.escape(key) + r":[ \t]+)\S+(\r?)$", re.M)
new, n = pat.subn(lambda m: m.group(1) + enc + m.group(2), raw, count=1)
if n != 1:
    sys.exit(1)
open(path, "wb").write(new.encode())
PY
  [[ " ${CHANGED_FILES[*]} " == *" $file "* ]] || CHANGED_FILES+=("$file")
  CHECKS+=("$ns|$name|$key|$(sha "$value")")
  ok "Re-sealed ${B}$key${N} in $file"
}

live_sha() { # live_sha NS NAME KEY → sha256 of the value in the cluster ("" if missing)
  local b64
  b64=$(kubectl get secret -n "$1" "$2" -o json 2>/dev/null | jq -r --arg k "$3" '.data[$k] // empty') || true
  [[ -n $b64 ]] && printf '%s' "$b64" | base64 -d | sha256sum | cut -d' ' -f1
}

argo_refresh() {
  local app
  for app in "${APPS[@]}"; do
    kubectl -n argocd annotate application "$app" argocd.argoproj.io/refresh=normal --overwrite >/dev/null 2>&1 || true
  done
}

ship() { # ship BRANCH-SLUG "commit subject"
  local slug="$1" subject="$2" br url
  step "Open a pull request"
  help "Only the re-sealed file(s) go into the commit. The encrypted values can be"
  help "decrypted only by the Sealed Secrets controller in this cluster."
  (cd "$REPO_ROOT" && git --no-pager diff --stat -- "${CHANGED_FILES[@]}")
  if ! confirm "Create branch, commit, push and open the PR now?"; then
    warn "Skipped. Commit ${CHANGED_FILES[*]} yourself; the next step waits for the merge."
    return
  fi
  br="renew/${slug}-$(date +%Y%m%d-%H%M)"
  cd "$REPO_ROOT"
  git switch -q -c "$br"
  git add -- "${CHANGED_FILES[@]}"
  git commit -q -m "$subject" -m "Re-sealed with renew-secrets.sh."
  git push -q -u origin "$br"
  url=$(gh pr create --repo "$GH_REPO" --base main --head "$br" --title "$subject" \
    --body "Renewed with \`renew-secrets.sh\`. Only the re-sealed keys changed: ${CHANGED_FILES[*]}")
  ok "PR: $url"
  if confirm "Merge it now (squash, delete branch)? Merging = deploying." n; then
    gh pr merge "$url" --squash --delete-branch >/dev/null && ok "Merged."
    git switch -q main && git pull -q --ff-only
  else
    do_ "Review and merge the PR in GitHub; this script keeps waiting."
  fi
}

wait_for_sync() {
  step "Wait until the new value is live in the cluster"
  help "Argo CD picks up the merge (auto-sync, up to ~3 min), the Sealed Secrets controller"
  help "decrypts it into the Secret. The script compares SHA-256 hashes only."
  if [[ " ${APPS[*]} " == *" argocd "* ]]; then
    warn "The ${B}argocd${N} app syncs manually. After the merge: Argo CD UI → argocd → ${B}Sync${N}"
    help "or: argocd app sync argocd. Review the diff first: it syncs the whole argocd chart."
  fi
  local start=$SECONDS c ns name key want k
  local -a pending
  while true; do
    argo_refresh
    pending=()
    for c in "${CHECKS[@]}"; do
      IFS='|' read -r ns name key want <<<"$c"
      [[ $(live_sha "$ns" "$name" "$key") == "$want" ]] || pending+=("$ns/$name:$key")
    done
    if [[ ${#pending[@]} -eq 0 ]]; then echo; ok "All renewed keys are live in the cluster."; return 0; fi
    if ((SECONDS - start > SYNC_TIMEOUT)); then
      echo; fail "Not live after $((SYNC_TIMEOUT / 60)) min: ${pending[*]}"
      help "Is the PR merged? Check the app in Argo CD and: kubectl get sealedsecret -A"
      return 1
    fi
    printf '\r  %s… waiting for %s (%ds, s=skip)%s ' "$DIM" "${pending[*]}" $((SECONDS - start)) "$N"
    if read -rsn1 -t 15 k && [[ $k == s ]]; then echo; warn "Skipped waiting."; return 1; fi
  done
}

restart_workloads() {
  [[ ${#RESTARTS[@]} -eq 0 ]] && return 0
  step "Restart the workloads that read the secret at startup"
  help "Environment variables from a Secret are read only when a pod starts."
  local r ns dep
  for r in "${RESTARTS[@]}"; do
    IFS='|' read -r ns dep <<<"$r"
    if confirm "Restart deployment ${B}$ns/$dep${N}?"; then
      kubectl rollout restart -n "$ns" "deploy/$dep" >/dev/null
      if kubectl rollout status -n "$ns" "deploy/$dep" --timeout=300s >/dev/null; then
        ok "$ns/$dep restarted and ready."
      else
        fail "$ns/$dep did not become ready; check: kubectl get pods -n $ns"
      fi
    fi
  done
}

finish_sealed() { # finish_sealed SLUG "commit subject": PR → wait for sync → restarts
  ship "$1" "$2"
  if wait_for_sync; then
    restart_workloads
  else
    local r
    for r in "${RESTARTS[@]}"; do
      warn "Once synced, restart: kubectl rollout restart -n ${r%%|*} deploy/${r##*|}"
    done
  fi
}

# ---------- Slack bot token ----------
slack_bot_token_steps() { # slack_bot_token_steps "App name" "App ID" ["extra hint"]
  step "Get a new bot token in Slack"
  help "Slack app ${B}$1${N}${DIM} (App ID $2, workspace Germanium)."
  [[ -n ${3:-} ]] && help "$3"
  open_url "https://api.slack.com/apps/$2/oauth"
  do_ "If the page asks, log in to the ${B}Germanium${N} workspace; you land on ${B}OAuth & Permissions${N}"
  help "Not there? https://api.slack.com/apps → click ${B}$1${N} → OAuth & Permissions."
  help "Just testing the script? Skip the revoke and copy the current token."
  help "Bot tokens don't expire. To replace a leaked one:"
  do_ "${B}Revoke All OAuth Tokens${N} (bottom of the page) → ${B}Reinstall to Workspace${N} → ${B}Allow${N}"
  warn "Revoking stops the app at once until the new token is live."
  do_ "Copy the ${B}Bot User OAuth Token${N} (xoxb-…)"
  pause
}

read_slack_bot_token() { # read_slack_bot_token VAR
  local _t
  while true; do
    read_secret _t "Bot User OAuth Token" "xoxb-"
    if [[ $(curl -fsS --max-time 20 -H @<(printf 'Authorization: Bearer %s\n' "$_t") \
      https://slack.com/api/auth.test | jq -r .ok) == true ]]; then
      ok "Slack accepted the token (auth.test)."; break
    fi
    fail "Slack rejected this token. Copy it again."
  done
  printf -v "$1" '%s' "$_t"
}

# ---------- entry point ----------
# renew_main "Title" "$@" with MENU=("id|description|function" ...) set by the caller.
# One entry runs directly; several show a menu (or take the id as $1).
renew_main() {
  local heading="$1"; shift
  local choice="${1:-}" e id desc fn i
  if [[ $choice == -h || $choice == --help ]]; then
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0
  fi
  title "$heading"
  if [[ ${#MENU[@]} -eq 1 ]]; then
    choice=${MENU[0]%%|*}
  elif [[ -z $choice ]]; then
    printf '\n  Which secret do you want to renew?\n'
    i=1
    for e in "${MENU[@]}"; do
      IFS='|' read -r id desc fn <<<"$e"
      printf '    %d) %-10s %s\n' "$i" "$id" "$desc"; i=$((i + 1))
    done
    printf '    q) Quit\n'
    read -rp "  Choice: " choice
  fi
  [[ $choice == q || $choice == Q ]] && exit 0
  if [[ $choice =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#MENU[@]})); then
    choice=${MENU[$((choice - 1))]%%|*}
  fi
  for e in "${MENU[@]}"; do
    IFS='|' read -r id desc fn <<<"$e"
    if [[ $id == "$choice" ]]; then "$fn"; return; fi
  done
  die "Unknown choice: $choice"
}
