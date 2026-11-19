#!/bin/sh
# Backs up the staged files and the application volumes to the local restic repository on orange1,
# then applies retention. Runs after collect.sh has filled /staging.
set -eu

export RESTIC_REPOSITORY=/repo
export RESTIC_PASSWORD_FILE=/secrets/restic/password
log() { echo "$(date -u +%FT%TZ) restic: $*"; }

if ! restic cat config >/dev/null 2>&1; then
  log "no repository at $RESTIC_REPOSITORY, creating it"
  restic init
fi

# The NAS folders go in as listed; the staged data keeps its /staging/data paths.
# Exit code 3 (some files could not be read) also fails the job.
restic backup --no-cache --host orange --tag nightly \
  --exclude '.esphome' \
  --files-from-verbatim /staging/paths.txt \
  /staging/data

restic forget --no-cache --host orange --tag nightly \
  --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune

# Sundays: read back a sample of the stored data to catch corruption
if [ "$(date +%u)" = "7" ]; then
  log "weekly check"
  restic check --no-cache --read-data-subset=5%
fi

restic snapshots --no-cache --latest 1 --compact
restic stats --no-cache --mode raw-data
log "done"
