"""Make consistent copies of the SQLite databases found in the backed-up volumes.

A database file copied while its app writes to it can be inconsistent. The volumes are mounted read-only,
so SQLite's online backup can't run against them directly. Instead, each database and its write-ahead log
are copied to local disk, checked with PRAGMA integrity_check, and then written out as one clean file with
SQLite's backup API. A copy that fails the check is retried a few times; if it keeps failing, the job fails.

Usage: sqlite_copy.py <paths.txt> <output dir> <scratch dir>
"""
import os
import shutil
import sqlite3
import sys
import tempfile
import time

MAX_DEPTH = 4                       # how deep to look inside each volume
SKIP_DIRS = {".esphome", "node_modules", ".git"}
SKIP_FILES = ("celerybeat-schedule",)  # Paperless scheduler state, rebuilt automatically
HEADER = b"SQLite format 3\x00"
ATTEMPTS = 3


def is_sqlite(path):
    try:
        with open(path, "rb") as f:
            return f.read(16) == HEADER
    except OSError:
        return False


def find_databases(root):
    for dirpath, dirnames, filenames in os.walk(root):
        depth = dirpath[len(root):].count(os.sep)
        dirnames[:] = [] if depth >= MAX_DEPTH else [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            if name.endswith(("-wal", "-shm", "-journal")) or name.startswith(SKIP_FILES):
                continue
            path = os.path.join(dirpath, name)
            if is_sqlite(path):
                yield path


def copy_consistent(src, dest, scratch):
    for attempt in range(1, ATTEMPTS + 1):
        with tempfile.TemporaryDirectory(dir=scratch) as tmp:
            local = os.path.join(tmp, "db")
            shutil.copyfile(src, local)
            if os.path.exists(src + "-wal"):
                shutil.copyfile(src + "-wal", local + "-wal")
            try:
                conn = sqlite3.connect(local)
                result = conn.execute("PRAGMA integrity_check").fetchone()[0]
                if result != "ok":
                    raise sqlite3.DatabaseError(result)
                out = sqlite3.connect(dest)
                conn.backup(out)
                # Store the copy as one self-contained file, without a write-ahead log
                out.execute("PRAGMA journal_mode=DELETE")
                out.close()
                conn.close()
                return
            except sqlite3.DatabaseError as err:
                print(f"sqlite: attempt {attempt} for {src} failed: {err}", flush=True)
                time.sleep(5)
    sys.exit(f"sqlite: ERROR: no consistent copy of {src} after {ATTEMPTS} attempts")


def main():
    paths_file, out_dir, scratch = sys.argv[1:4]
    with open(paths_file) as f:
        roots = [line.strip().rstrip("/") for line in f if line.strip()]
    count = 0
    for root in roots:
        volume = os.path.basename(root)
        for db in find_databases(root):
            dest = os.path.join(out_dir, volume, os.path.relpath(db, root))
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            copy_consistent(db, dest, scratch)
            count += 1
            print(f"sqlite: {volume}/{os.path.relpath(db, root)} {os.path.getsize(dest) // 1024} KiB", flush=True)
    print(f"sqlite: {count} databases copied", flush=True)


if __name__ == "__main__":
    main()
