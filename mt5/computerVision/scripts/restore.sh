#!/bin/bash
set -e

if [ $# -eq 0 ]; then
    echo "Usage: ./restore.sh <backup_timestamp>"
    echo "Example: ./restore.sh 20260210_120000"
    exit 1
fi

TIMESTAMP=$1
BACKUP_DIR="./volumes/backups"
# Assuming the project folder is 'computerVision', the volume is named 'computervision_mt5_data'.
# If you renamed the folder, update this variable.
VOLUME_NAME="computervision_mt5_data"

echo "🔄 Restoring from backup: $TIMESTAMP"

# Stop services
echo "⏸️ Stopping services..."
docker compose stop trader bridge dashboard

# Restore database
if [ -f "$BACKUP_DIR/db_backup_$TIMESTAMP.sql.gz" ]; then
    echo "📥 Restoring database..."
    gunzip < "$BACKUP_DIR/db_backup_$TIMESTAMP.sql.gz" | \
        docker compose exec -T postgres psql -U cv_agent cv_trading
else
    echo "⚠️ Database backup not found"
fi

# Restore MT5 data
if [ -f "$BACKUP_DIR/mt5_backup_$TIMESTAMP.tar.gz" ]; then
    echo "📥 Restoring MT5 data..."
    docker run --rm \
        -v $VOLUME_NAME:/data \
        -v "$(pwd)/$BACKUP_DIR:/backup" \
        alpine \
        tar xzf "/backup/mt5_backup_$TIMESTAMP.tar.gz" -C /data
else
    echo "⚠️ MT5 backup not found"
fi

# Restart services
echo "▶️ Starting services..."
docker compose up -d

echo "✅ Restore complete!"
