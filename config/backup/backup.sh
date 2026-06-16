#!/bin/bash
# Nightly logical backup of every database in the shared cluster.
# Runs inside the `backup` service. Keeps BACKUP_KEEP_DAYS of dumps.
set -euo pipefail

STAMP="$(date +%F-%H%M)"
OUT="/backups"
KEEP="${BACKUP_KEEP_DAYS:-14}"

echo "[$(date)] starting backup -> $OUT"

# pg_dumpall captures all app databases + roles in one consistent file.
pg_dumpall | gzip > "$OUT/magicworkflow-all-$STAMP.sql.gz"

echo "[$(date)] wrote magicworkflow-all-$STAMP.sql.gz"

# Prune old dumps
find "$OUT" -name 'magicworkflow-all-*.sql.gz' -mtime "+$KEEP" -print -delete || true

echo "[$(date)] backup complete. Reminder: also back up the MinIO 'minio_data' volume (user files)."
