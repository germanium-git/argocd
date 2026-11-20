# Runs ON THE NAS as root, fed through `ssh atlas 'sudo -n bash -s'` by
# export-atlas-cert.sh --upload. Not meant to be run directly.
#
# Expects these variables to be prepended by the caller:
#   SUBJECT   certificate folder name in UGOS (atlas.germanium.cz)
#   CERT_B64  base64 of the full chain (leaf first)
#   KEY_B64   base64 of the private key
#   FORCE     1 = reinstall even if the NAS already has this certificate
#
# UGOS layout (UGOS Pro, Debian 12, checked 2026-11-20):
#   /ugreen/.config/ssl/certs/<subject>/{cert.pem,privkey.pem}  full chain + key, used by nginx
#   /ugreen/.config/ssl/certcache.json  what the UI's certificate list shows (expiry as epoch)
#   /ugreen/.config/ssl/ssl.json        service -> certificate mapping (left untouched)
set -euo pipefail

SSL_DIR=/ugreen/.config/ssl
CERT_DIR="$SSL_DIR/certs/$SUBJECT"
CACHE="$SSL_DIR/certcache.json"
BACKUP_ROOT=/ugreen/.config/ssl-backup
KEEP_BACKUPS=5

info() { printf '    [nas] %s\n' "$*"; }
die()  { printf '    [nas] ERROR: %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "must run as root"
[[ -d "$CERT_DIR" ]] || die "$CERT_DIR not found - import the certificate once via the UGOS UI first"
for f in cert.pem privkey.pem; do [[ -f "$CERT_DIR/$f" ]] || die "$CERT_DIR/$f not found"; done

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
umask 077
base64 -d <<<"$CERT_B64" > "$staging/cert.pem"
base64 -d <<<"$KEY_B64"  > "$staging/privkey.pem"

# --- Validate the new certificate ---------------------------------------------
openssl x509 -in "$staging/cert.pem" -noout -checkhost "$SUBJECT" | grep -q 'does match' \
  || die "new certificate is not valid for $SUBJECT"
[[ "$(openssl x509 -in "$staging/cert.pem" -noout -pubkey)" == "$(openssl pkey -in "$staging/privkey.pem" -pubout)" ]] \
  || die "new private key does not match the certificate"
openssl x509 -in "$staging/cert.pem" -noout -checkend 0 >/dev/null || die "new certificate is already expired"

new_serial="$(openssl x509 -in "$staging/cert.pem" -noout -serial | cut -d= -f2)"
old_serial="$(openssl x509 -in "$CERT_DIR/cert.pem" -noout -serial 2>/dev/null | cut -d= -f2 || true)"
new_end="$(openssl x509 -in "$staging/cert.pem" -noout -enddate | cut -d= -f2)"
new_epoch="$(date -d "$new_end" +%s)"
info "installed serial: ${old_serial:-none}"
info "new serial:       $new_serial (expires $new_end)"

if [[ "$new_serial" == "$old_serial" && "${FORCE:-0}" != 1 ]]; then
  info "NAS already has this certificate - nothing to do (use --force to reinstall)"
  exit 0
fi

# --- Back up the current files ------------------------------------------------
backup="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup"
chmod 700 "$BACKUP_ROOT"
cp -a "$CERT_DIR/cert.pem" "$CERT_DIR/privkey.pem" "$backup/"
cp -a "$CACHE" "$backup/" 2>/dev/null || true
info "backup: $backup"
# Keep only the newest backups.
ls -1d "$BACKUP_ROOT"/*/ 2>/dev/null | sort | head -n -"$KEEP_BACKUPS" | xargs -r rm -rf

restore() {
  info "restoring previous certificate from $backup"
  cp -a "$backup/cert.pem" "$backup/privkey.pem" "$CERT_DIR/"
  [[ -f "$backup/certcache.json" ]] && cp -a "$backup/certcache.json" "$CACHE"
  systemctl reload nginx || true
}

# --- Install (write next to the target, then rename = atomic swap) -------------
install -m 600 -o root -g root "$staging/cert.pem"    "$CERT_DIR/.cert.pem.new"
install -m 600 -o root -g root "$staging/privkey.pem" "$CERT_DIR/.privkey.pem.new"
mv -f "$CERT_DIR/.privkey.pem.new" "$CERT_DIR/privkey.pem"
mv -f "$CERT_DIR/.cert.pem.new"    "$CERT_DIR/cert.pem"

# Update the expiry the UGOS UI shows (only the entry for this subject).
if [[ -f "$CACHE" ]]; then
  jq -cj --arg s "$SUBJECT" --argjson e "$new_epoch" \
    'map(if .subject == $s then .expired = $e else . end)' "$CACHE" > "$staging/certcache.json" \
    && install -m 600 -o root -g root "$staging/certcache.json" "$CACHE" \
    || info "WARNING: could not update $CACHE (UI may show the old expiry)"
fi

# --- Reload nginx -------------------------------------------------------------
if ! nginx -t -q 2>"$staging/nginx-t.log"; then
  cat "$staging/nginx-t.log" >&2
  restore
  die "nginx config test failed - rolled back"
fi
if ! systemctl reload nginx; then
  restore
  die "nginx reload failed - rolled back"
fi
info "installed and nginx reloaded"
