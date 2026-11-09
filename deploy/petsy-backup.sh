#!/usr/bin/env bash
# Daily backup of the Petsy database and uploads. Installed as /usr/local/sbin/petsy-backup.
set -euo pipefail
umask 077

ENV_FILE=/etc/petsy/petsy.env
UPLOADS_DIR=/opt/petsy/backend/uploads
BACKUP_DIR=/var/backups/petsy
KEEP_DAYS="${KEEP_DAYS:-14}"

mongo_url=$(grep -E '^MONGO_URL=' "$ENV_FILE" | cut -d= -f2-)
db_name=$(grep -E '^DB_NAME=' "$ENV_FILE" | cut -d= -f2-)
[ -n "$mongo_url" ] && [ -n "$db_name" ] || { echo "MONGO_URL/DB_NAME missing in $ENV_FILE" >&2; exit 1; }

mkdir -p "$BACKUP_DIR"
stamp=$(date -u +%Y%m%d-%H%M%S)
cfg=$(mktemp)
trap 'rm -f "$cfg"' EXIT
# Passing the URI through a config file keeps the password out of the process list.
printf 'uri: "%s"\n' "$mongo_url" > "$cfg"

db_file="$BACKUP_DIR/petsy-db-$stamp.archive.gz"
mongodump --config="$cfg" --db="$db_name" --archive="$db_file.tmp" --gzip --quiet
mv "$db_file.tmp" "$db_file"

uploads_file="$BACKUP_DIR/petsy-uploads-$stamp.tar.gz"
tar -czf "$uploads_file.tmp" -C "$(dirname "$UPLOADS_DIR")" "$(basename "$UPLOADS_DIR")"
mv "$uploads_file.tmp" "$uploads_file"

find "$BACKUP_DIR" -maxdepth 1 -type f \( -name 'petsy-db-*' -o -name 'petsy-uploads-*' \) -mtime +"$KEEP_DAYS" -delete

echo "backup ok: $(basename "$db_file") $(du -h "$db_file" | cut -f1), $(basename "$uploads_file") $(du -h "$uploads_file" | cut -f1)"

# Off-site copy to Google Drive (rclone remote "gdrive", scope drive.file, configured for root).
REMOTE="${REMOTE:-gdrive:petsy-backups}"
REMOTE_KEEP_DAYS="${REMOTE_KEEP_DAYS:-30}"
if rclone listremotes 2>/dev/null | grep -qx "${REMOTE%%:*}:"; then
  rclone copy "$db_file" "$REMOTE" --quiet
  rclone copy "$uploads_file" "$REMOTE" --quiet
  rclone delete "$REMOTE" --min-age "${REMOTE_KEEP_DAYS}d" --include 'petsy-{db,uploads}-*' --quiet
  echo "uploaded to $REMOTE"
else
  echo "remote ${REMOTE%%:*} not configured; skipped off-site copy" >&2
fi
