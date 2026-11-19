#!/bin/sh
# 1. Backs up the staged files and the application volumes to the local restic repository on orange1,
#    then applies retention. Runs after collect.sh has filled /staging.
# 2. Copies the new snapshots to the off-site repository on Google Drive (through rclone), applies the
#    same retention there, and fails if that repository grows past the size limit.
set -eu

export RESTIC_REPOSITORY=/repo
export RESTIC_PASSWORD_FILE=/secrets/restic/password
log() { echo "$(date -u +%FT%TZ) restic: $*"; }
fail() { log "ERROR: $*"; exit 1; }

KEEP="--keep-daily 7 --keep-weekly 4 --keep-monthly 6"
SUNDAY=$([ "$(date +%u)" = "7" ] && echo yes || echo no)

# ---------- local repository ----------

if ! restic cat config --no-cache >/dev/null 2>&1; then
  log "no repository at $RESTIC_REPOSITORY, creating it"
  restic init
fi

# The NAS folders go in as listed; the staged data keeps its /staging/data paths.
# Exit code 3 (some files could not be read) also fails the job.
restic backup --no-cache --host orange --tag nightly \
  --exclude '.esphome' \
  --files-from-verbatim /staging/paths.txt \
  /staging/data

# shellcheck disable=SC2086
restic forget --no-cache --host orange --tag nightly $KEEP --prune

# Sundays: read back a sample of the stored data to catch corruption
if [ "$SUNDAY" = yes ]; then
  log "weekly check (local)"
  restic check --no-cache --read-data-subset=5%
fi

restic snapshots --no-cache --latest 1 --compact
restic stats --no-cache --mode raw-data

# ---------- off-site repository (Google Drive) ----------

# rclone binary and a writable copy of its config come from the rclone-bin init container
OFFSITE="rclone:gdrive:orange-backup/restic"
OFFSITE_LIMIT_GB=15
export RCLONE_CONFIG=/tools/rclone.conf
# Files deleted by prune must not end up in the Drive trash, where they would still use the quota
export RCLONE_DRIVE_USE_TRASH=false
export RESTIC_CACHE_DIR=/staging/restic-cache
off() { restic -r "$OFFSITE" -o rclone.program=/tools/rclone "$@"; }
off_size() {
  off stats --mode raw-data --json | sed -nE 's/.*"total_size":([0-9]+).*/\1/p'
}
check_limit() {
  size=$(off_size)
  [ -n "$size" ] || fail "could not read the size of the off-site repository"
  log "off-site repository: $((size / 1024 / 1024)) MiB (limit ${OFFSITE_LIMIT_GB} GB)"
  [ "$size" -le $((OFFSITE_LIMIT_GB * 1000 * 1000 * 1000)) ] || fail "off-site repository is over the ${OFFSITE_LIMIT_GB} GB limit"
}

if ! off cat config >/dev/null 2>&1; then
  log "no off-site repository, creating it"
  # Same chunker settings as the local repository, so copied data deduplicates the same way
  off init --from-repo /repo --from-password-file "$RESTIC_PASSWORD_FILE" --copy-chunker-params
fi

# Don't add data to a repository that is already over the limit
check_limit

log "copying new snapshots to Google Drive"
off copy --from-repo /repo --from-password-file "$RESTIC_PASSWORD_FILE" --host orange --tag nightly
# shellcheck disable=SC2086
off forget --host orange --tag nightly $KEEP --prune

if [ "$SUNDAY" = yes ]; then
  log "weekly check (off-site)"
  off check --read-data-subset=5%
fi

off snapshots --latest 1 --compact
check_limit
log "done"
