#!/bin/bash
#
# MongoDB 6.0.1 Restore Script for VM
# Restores mongodump backup
#

set -euo pipefail

# Configuration
MONGO_USER="${MONGO_USER:-root}"
MONGO_PASSWORD="${MONGO_PASSWORD:-}"
MONGO_HOST="${MONGO_HOST:-localhost}"
MONGO_PORT="${MONGO_PORT:-27017}"
MONGO_AUTH_DB="${MONGO_AUTH_DB:-admin}"
BACKUP_FILE="${1:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
    exit 1
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

# Usage
if [ -z "$BACKUP_FILE" ]; then
    echo "Usage: $0 <backup-file.tar.gz>"
    echo ""
    echo "Example:"
    echo "  $0 /backup/mongodb-20260505-120000/mongodb-backup-20260505-120000.tar.gz"
    echo ""
    echo "Environment Variables:"
    echo "  MONGO_USER       - MongoDB username (default: root)"
    echo "  MONGO_PASSWORD   - MongoDB password (required)"
    echo "  MONGO_HOST       - MongoDB host (default: localhost)"
    echo "  MONGO_PORT       - MongoDB port (default: 27017)"
    exit 1
fi

# Check MongoDB password
if [ -z "$MONGO_PASSWORD" ]; then
    error "MONGO_PASSWORD environment variable must be set"
fi

# Check if backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
    error "Backup file not found: $BACKUP_FILE"
fi

log "========================================="
log "MongoDB Restore Process"
log "========================================="
log "Backup File: $BACKUP_FILE"
log "MongoDB Host: $MONGO_HOST"
log "MongoDB Port: $MONGO_PORT"
log "MongoDB User: $MONGO_USER"
log "========================================="

# Check if checksum file exists
CHECKSUM_FILE="${BACKUP_FILE}.sha256"
if [ -f "$CHECKSUM_FILE" ]; then
    log "Verifying backup integrity..."
    if sha256sum -c "$CHECKSUM_FILE"; then
        log "✓ Checksum verification passed"
    else
        error "✗ Checksum verification failed! Backup may be corrupted."
    fi
else
    warn "Checksum file not found, skipping integrity check"
fi

# Check MongoDB connectivity
log "Checking MongoDB connectivity..."
if mongosh --username="$MONGO_USER" \
    --password="$MONGO_PASSWORD" \
    --authenticationDatabase="$MONGO_AUTH_DB" \
    --host="$MONGO_HOST" \
    --port="$MONGO_PORT" \
    --eval "db.version()" >/dev/null 2>&1; then
    log "✓ MongoDB is accessible"
else
    error "✗ Cannot connect to MongoDB. Please check credentials and connectivity."
fi

# Get MongoDB version
MONGO_VERSION=$(mongosh --username="$MONGO_USER" \
    --password="$MONGO_PASSWORD" \
    --authenticationDatabase="$MONGO_AUTH_DB" \
    --host="$MONGO_HOST" \
    --port="$MONGO_PORT" \
    --quiet --eval "db.version()")
log "MongoDB Version: $MONGO_VERSION"

# Warning about existing data
warn "⚠️  WARNING: This will OVERWRITE existing databases!"
read -p "Are you sure you want to proceed? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    log "Restore cancelled by user"
    exit 0
fi

# Create restore directory
RESTORE_DIR="/tmp/mongodb-restore-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RESTORE_DIR"
log "Created temporary restore directory: $RESTORE_DIR"

# Extract backup
log "Extracting MongoDB backup..."
if tar -xzf "$BACKUP_FILE" -C "$RESTORE_DIR"; then
    log "✓ Backup extracted successfully"
else
    error "✗ Failed to extract backup"
fi

# Backup existing databases (safety measure)
log "Creating safety backup of existing databases..."
SAFETY_BACKUP="/tmp/mongodb-safety-backup-$(date +%Y%m%d-%H%M%S)"
if mongodump --username="$MONGO_USER" \
    --password="$MONGO_PASSWORD" \
    --authenticationDatabase="$MONGO_AUTH_DB" \
    --host="$MONGO_HOST" \
    --port="$MONGO_PORT" \
    --out="$SAFETY_BACKUP" >/dev/null 2>&1; then
    log "✓ Safety backup created: $SAFETY_BACKUP"
else
    warn "Could not create safety backup, but continuing..."
fi

# Perform restore
log "Starting MongoDB restore..."
log "This may take several minutes depending on database size..."

START_TIME=$(date +%s)

# Find the mongodb directory in the extracted backup
MONGO_BACKUP_DIR=$(find "$RESTORE_DIR" -type d -name "mongodb" | head -1)

if [ -z "$MONGO_BACKUP_DIR" ]; then
    error "MongoDB backup directory not found in extracted files"
fi

if mongorestore --username="$MONGO_USER" \
    --password="$MONGO_PASSWORD" \
    --authenticationDatabase="$MONGO_AUTH_DB" \
    --host="$MONGO_HOST" \
    --port="$MONGO_PORT" \
    --dir="$MONGO_BACKUP_DIR"; then
    log "✓ Restore completed successfully"
else
    error "✗ Restore failed! Check MongoDB logs for details."
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
log "Restore duration: $DURATION seconds"

# Cleanup
log "Cleaning up temporary files..."
rm -rf "$RESTORE_DIR"

# Verify restore
log "Verifying restored databases..."
DB_LIST=$(mongosh --username="$MONGO_USER" \
    --password="$MONGO_PASSWORD" \
    --authenticationDatabase="$MONGO_AUTH_DB" \
    --host="$MONGO_HOST" \
    --port="$MONGO_PORT" \
    --quiet --eval "db.adminCommand({listDatabases: 1}).databases.map(d => d.name).join(', ')")
log "Restored databases: $DB_LIST"

# Final summary
log "========================================="
log "MongoDB Restore Summary"
log "========================================="
log "Backup File: $BACKUP_FILE"
log "Restore Duration: $DURATION seconds"
log "Restored Databases: $DB_LIST"
log "Safety Backup: $SAFETY_BACKUP"
log "========================================="
log "✓ Restore completed successfully!"
log ""
log "Next Steps:"
log "1. Verify data integrity by running application smoke tests"
log "2. Check application connection strings point to this VM"
log "3. Monitor MongoDB logs for any errors"
log "4. Keep safety backup for rollback: $SAFETY_BACKUP"

exit 0
