#!/bin/bash
#
# PostgreSQL 14.20 Restore Script for VM
# Restores full pg_dumpall backup
#

set -euo pipefail

# Configuration
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
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
    echo "Usage: $0 <backup-file.sql.gz>"
    echo ""
    echo "Example:"
    echo "  $0 /backup/postgres-20260505-120000/postgres-full-20260505-120000.sql.gz"
    exit 1
fi

# Check if backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
    error "Backup file not found: $BACKUP_FILE"
fi

log "========================================="
log "PostgreSQL Restore Process"
log "========================================="
log "Backup File: $BACKUP_FILE"
log "PostgreSQL Host: $POSTGRES_HOST"
log "PostgreSQL Port: $POSTGRES_PORT"
log "PostgreSQL User: $POSTGRES_USER"
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

# Check PostgreSQL connectivity
log "Checking PostgreSQL connectivity..."
if psql -U "$POSTGRES_USER" -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -c "SELECT version();" >/dev/null 2>&1; then
    log "✓ PostgreSQL is accessible"
else
    error "✗ Cannot connect to PostgreSQL. Please check credentials and connectivity."
fi

# Get PostgreSQL version
PG_VERSION=$(psql -U "$POSTGRES_USER" -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -t -c "SELECT version();" | head -1)
log "PostgreSQL Version: $PG_VERSION"

# Warning about existing data
warn "⚠️  WARNING: This will OVERWRITE existing databases!"
read -p "Are you sure you want to proceed? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    log "Restore cancelled by user"
    exit 0
fi

# Backup existing databases (safety measure)
log "Creating safety backup of existing databases..."
SAFETY_BACKUP="/tmp/postgres-safety-backup-$(date +%Y%m%d-%H%M%S).sql.gz"
if pg_dumpall -U "$POSTGRES_USER" -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" | gzip > "$SAFETY_BACKUP"; then
    log "✓ Safety backup created: $SAFETY_BACKUP"
else
    warn "Could not create safety backup, but continuing..."
fi

# Perform restore
log "Starting PostgreSQL restore..."
log "This may take several minutes depending on database size..."

START_TIME=$(date +%s)

if gunzip -c "$BACKUP_FILE" | psql -U "$POSTGRES_USER" -h "$POSTGRES_HOST" -p "$POSTGRES_PORT"; then
    log "✓ Restore completed successfully"
else
    error "✗ Restore failed! Check PostgreSQL logs for details."
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
log "Restore duration: $DURATION seconds"

# Run ANALYZE to update statistics
log "Running ANALYZE to update query planner statistics..."
if psql -U "$POSTGRES_USER" -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -c "ANALYZE;" >/dev/null 2>&1; then
    log "✓ ANALYZE completed"
else
    warn "ANALYZE failed, but restore was successful"
fi

# Verify restore
log "Verifying restored databases..."
psql -U "$POSTGRES_USER" -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -c "\l+" > "/tmp/restored-databases-$(date +%Y%m%d-%H%M%S).txt"
DB_COUNT=$(psql -U "$POSTGRES_USER" -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -t -c "SELECT count(*) FROM pg_database WHERE datistemplate = false;")
log "Total databases restored: $DB_COUNT"

# Final summary
log "========================================="
log "PostgreSQL Restore Summary"
log "========================================="
log "Backup File: $BACKUP_FILE"
log "Restore Duration: $DURATION seconds"
log "Databases Count: $DB_COUNT"
log "Safety Backup: $SAFETY_BACKUP"
log "========================================="
log "✓ Restore completed successfully!"
log ""
log "Next Steps:"
log "1. Verify data integrity by running application smoke tests"
log "2. Check application connection strings point to this VM"
log "3. Monitor PostgreSQL logs for any errors"
log "4. Keep safety backup for rollback: $SAFETY_BACKUP"

exit 0
