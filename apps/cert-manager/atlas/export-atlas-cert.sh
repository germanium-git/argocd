#!/usr/bin/env bash
# Export the Let's Encrypt certificate for the UGREEN NAS (atlas.germanium.cz)
# from the cert-manager Secret, then either
#   - copy it to the Windows Downloads folder for a manual import in UGOS, or
#   - install it on the NAS over SSH (--upload).
#
# Usage:
#   ./export-atlas-cert.sh                 # write files to Windows Downloads
#   ./export-atlas-cert.sh --upload        # install on the NAS over SSH, reload nginx
#   ./export-atlas-cert.sh --upload --force  # reinstall even if the NAS has this cert
#
# Environment:
#   DEST=/some/dir   write somewhere other than Downloads (download mode)
#   WIN_USER=name    Windows user for the Downloads path (auto-detected)
#   NAS_SSH=atlas    ssh destination for --upload (needs passwordless sudo there)
#
# Download mode writes:
#   atlas.fullchain.crt  leaf + intermediates (as stored by cert-manager)
#   atlas.crt            leaf certificate only
#   intermediate.crt     rest of the chain
#   atlas.key            private key
set -euo pipefail

NAMESPACE=default
CERT_NAME=atlas
SECRET_NAME=atlas-tls
HOST=atlas.germanium.cz
PORT=9443
NAS_SSH="${NAS_SSH:-atlas}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info() { printf '==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
usage() { sed -n '2,/^set -euo/{/^set -euo/d;s/^# \{0,1\}//;p}' "${BASH_SOURCE[0]}"; }

UPLOAD=0
FORCE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --upload) UPLOAD=1 ;;
    --force)  FORCE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" ;;
  esac
  shift
done
[[ $FORCE -eq 1 && $UPLOAD -eq 0 ]] && die "--force only makes sense with --upload"

for cmd in kubectl openssl awk base64; do
  command -v "$cmd" >/dev/null || die "'$cmd' not found in PATH"
done

# --- Destination: Windows Downloads folder (download mode only) ---------------
if [[ $UPLOAD -eq 0 && -z "${DEST:-}" ]]; then
  win_user="${WIN_USER:-}"
  if [[ -z "$win_user" ]] && command -v cmd.exe >/dev/null; then
    win_user="$(cd /mnt/c && cmd.exe /c 'echo %USERNAME%' 2>/dev/null | tr -d '\r')"
  fi
  [[ -n "$win_user" ]] || die "cannot determine Windows user; set WIN_USER or DEST"
  DEST="/mnt/c/Users/${win_user}/Downloads"
fi
[[ $UPLOAD -eq 1 || -d "$DEST" ]] || die "destination folder does not exist: $DEST"

# --- 1. Certificate must be Ready ---------------------------------------------
info "Checking Certificate ${NAMESPACE}/${CERT_NAME}"
ready="$(kubectl get certificate "$CERT_NAME" -n "$NAMESPACE" \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')" \
  || die "cannot read Certificate ${NAMESPACE}/${CERT_NAME} (wrong kubectl context?)"
if [[ "$ready" != "True" ]]; then
  kubectl get certificate "$CERT_NAME" -n "$NAMESPACE" -o wide >&2 || true
  die "Certificate is not Ready (status: '${ready:-unknown}'); check 'kubectl describe certificate $CERT_NAME -n $NAMESPACE'"
fi
info "Certificate is Ready"

# --- 2. Export from the Secret into a private temp dir ------------------------
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
umask 077

kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.tls\.crt}' \
  | base64 -d > "$tmp/atlas.fullchain.crt"
kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.tls\.key}' \
  | base64 -d > "$tmp/atlas.key"
[[ -s "$tmp/atlas.fullchain.crt" ]] || die "tls.crt in Secret ${SECRET_NAME} is empty"
[[ -s "$tmp/atlas.key" ]]           || die "tls.key in Secret ${SECRET_NAME} is empty"

# Split the chain: first PEM block = leaf, the rest = intermediates.
awk -v leaf="$tmp/atlas.crt" -v rest="$tmp/intermediate.crt" '
  /-----BEGIN CERTIFICATE-----/ { n++ }
  n == 1 { print > leaf }
  n > 1  { print > rest }
' "$tmp/atlas.fullchain.crt"
[[ -s "$tmp/atlas.crt" ]]        || die "no certificate found in tls.crt"
[[ -s "$tmp/intermediate.crt" ]] || warn "tls.crt contains no intermediates; intermediate.crt is empty"

# Sanity check: key belongs to the leaf certificate.
[[ "$(openssl x509 -in "$tmp/atlas.crt" -noout -pubkey)" == "$(openssl pkey -in "$tmp/atlas.key" -pubout)" ]] \
  || die "private key does not match the certificate"

expiry="$(openssl x509 -in "$tmp/atlas.crt" -noout -enddate | cut -d= -f2)"
serial="$(openssl x509 -in "$tmp/atlas.crt" -noout -serial | cut -d= -f2)"
info "Subject:  $(openssl x509 -in "$tmp/atlas.crt" -noout -subject | sed 's/^subject=\s*//')"
info "Issuer:   $(openssl x509 -in "$tmp/atlas.crt" -noout -issuer  | sed 's/^issuer=\s*//')"
info "Expires:  $expiry"
info "Serial:   $serial"

served_serial() {
  timeout 10 openssl s_client -connect "${HOST}:${PORT}" -servername "$HOST" </dev/null 2>/dev/null \
    | openssl x509 -noout -serial 2>/dev/null | cut -d= -f2 || true
}

# --- 3a. Upload: install on the NAS over SSH ------------------------------------
if [[ $UPLOAD -eq 1 ]]; then
  installer="$SCRIPT_DIR/install-on-nas.sh"
  [[ -f "$installer" ]] || die "$installer not found"
  info "Installing on the NAS via ssh ${NAS_SSH}"
  # Cert and key travel inside the ssh session (stdin), never as files in a user-readable place.
  {
    printf 'SUBJECT=%q\n'  "$HOST"
    printf 'CERT_B64=%q\n' "$(base64 -w0 "$tmp/atlas.fullchain.crt")"
    printf 'KEY_B64=%q\n'  "$(base64 -w0 "$tmp/atlas.key")"
    printf 'FORCE=%q\n'    "$FORCE"
    cat "$installer"
  } | ssh -o BatchMode=yes "$NAS_SSH" 'sudo -n bash -s' \
    || die "installation on the NAS failed (see messages above)"

  # nginx reloads gracefully; give it a moment before checking.
  live=""
  for _ in 1 2 3 4 5; do
    live="$(served_serial)"
    [[ "$live" == "$serial" ]] && break
    sleep 2
  done
  if [[ "$live" == "$serial" ]]; then
    info "Verified: https://${HOST}:${PORT} serves serial $serial (expires $expiry)"
  else
    die "NAS serves serial '${live:-unreachable}', expected $serial"
  fi
  exit 0
fi

# --- 3b. Download: copy to Downloads ------------------------------------------
for f in atlas.fullchain.crt atlas.crt intermediate.crt atlas.key; do
  cp "$tmp/$f" "$DEST/$f"
done
info "Wrote to $DEST:"
printf '      %s\n' atlas.fullchain.crt atlas.crt intermediate.crt atlas.key

# --- 4. Compare with what the NAS serves right now (informational) -----------
live_serial="$(served_serial)"
if [[ -z "$live_serial" ]]; then
  warn "could not reach https://${HOST}:${PORT} to compare the served certificate"
elif [[ "$live_serial" == "$serial" ]]; then
  info "NAS already serves this certificate - no import needed"
else
  info "NAS serves a different certificate (serial $live_serial) - run with --upload, or import the new one in UGOS"
fi

echo
info "Delete atlas.key from Downloads once it is imported into UGOS."
