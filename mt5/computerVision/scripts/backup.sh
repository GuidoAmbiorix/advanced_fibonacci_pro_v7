#!/bin/bash
set -e

BACKUP_DIR="./volumes/backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
# Assuming the project folder is 'computerVision', the volume is named 'computervision_mt5_data'.
# If you renamed the folder, update this variable.
VOLUME_NAME="computervision_mt5_data"

echo "💾 Starting backup at $TIMESTAMP..."

# Database backup
echo "📦 Backing up PostgreSQL database..."
docker compose exec -T postgres pg_dump -U cv_agent cv_trading | \
    gzip > "$BACKUP_DIR/db_backup_$TIMESTAMP.sql.gz"

# MT5 data backup
echo "📦 Backing up MT5 data..."
docker run --rm \
    -v $VOLUME_NAME:/data \
    -v "$(pwd)/$BACKUP_DIR:/backup" \
    alpine \
    tar czf "/backup/mt5_backup_$TIMESTAMP.tar.gz" -C /data .

# Logs backup
echo "📦 Backing up logs..."
tar czf "$BACKUP_DIR/logs_backup_$TIMESTAMP.tar.gz" volumes/logs/

echo "✅ Backup complete!"
echo "📁 Backups saved to: $BACKUP_DIR"
ls -lh "$BACKUP_DIR" | grep "$TIMESTAMP"
