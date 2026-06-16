#!/bin/sh
# Creates the per-app buckets and a single scoped service-account the apps use.
# Idempotent: safe to re-run.
set -eu

echo "==> Waiting for MinIO and configuring alias..."
mc alias set local "http://minio:9000" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"

echo "==> Ensuring buckets exist"
mc mb --ignore-existing "local/${NEXTCLOUD_S3_BUCKET}"
mc mb --ignore-existing "local/${MATTERMOST_S3_BUCKET}"

echo "==> Creating application service-account (scoped access key)"
# Remove a stale key with the same id, then (re)create it deterministically.
mc admin user svcacct rm local "${S3_ACCESS_KEY}" 2>/dev/null || true
mc admin user svcacct add local "$MINIO_ROOT_USER" \
  --access-key "${S3_ACCESS_KEY}" \
  --secret-key "${S3_SECRET_KEY}" >/dev/null

echo "==> MinIO initialised: buckets [${NEXTCLOUD_S3_BUCKET}, ${MATTERMOST_S3_BUCKET}], access key ${S3_ACCESS_KEY}"
