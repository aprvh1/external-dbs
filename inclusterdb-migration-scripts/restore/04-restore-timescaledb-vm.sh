#!/bin/bash
#
# TimescaleDB (PG13 + TS2.9) Restore Script for VM
# Restores full TimescaleDB backup with extension support
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
    echo "  $0 /backup/timescaledb-20260505-120000/timescaledb-full-20260505-120000.sql.gz"
    echo ""
    echo "Environment Variables:"
    echo "  POSTGRES_USER - PostgreSQL username (default: postgres)"
    echo "  POSTGRES_HOST - PostgreSQL host (default: localhost)"
    echo "  POSTGRES_PORT - PostgreSQL port (default: 5432)"
    exit 1
fi

# Check if backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
    error "Backup file not found: $BACKUP_FILE"
fi

log "========================================="
log "TimescaleDB Restore Process"
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

# Check if TimescaleDB extension is available
log "Checking TimescaleDB extension availability..."
if psql -U "$POSTGRES_USER" -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -d postgres -c "SELECT * FROM pg_available_extensions WHERE name='timescaledb';" | grep -q "timescaledb"; then
    log "✓ TimescaleDB extension is available"
else
    error "✗ TimescaleDB extension is not available. Please install TimescaleDB first."
fi

# Create TimescaleDB extension if not exists
log "Ensuring TimescaleDB extension is enabled..."
if psql -U "$POSTGRES_USER" -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -d postgres -c "CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;" >/dev/null 2>&1; then
    log "✓ TimescaleDB extension is ready"
else
    warn "Could not create TimescaleDB extension (may already exist)"
fi

# Check TimescaleDB version
TSDB_VERSION=$(psql -U "$POSTGRES_USER" -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -d postgres -t -c "SELECT extversion FROM pg_extension WHERE extname='timescaledb';" | tr -d ' ')
log "TimescaleDB Version: $TSDB_VERSION"

# Warning about existing data
warn "⚠️  WARNING: This will OVERWRITE existing databases!"
read -p "Are you sure you want to proceed? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    log "Restore cancelled by user"
    exit 0
fi

# Backup existing databases (safety measure)
log "Creating safety backup of existing databases..."
SAFETY_BACKUP="/tmp/timescaledb-safety-backup-$(date +%Y%m%d-%H%M%S).sql.gz"
if pg_dumpall -U "$POSTGRES_USER" -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" | gzip > "$SAFETY_BACKUP"; then
    log "✓ Safety backup created: $SAFETY_BACKUP"
else
    warn "Could not create safety backup, but continuing..."
fi

# Perform restore
log "Starting TimescaleDB restore..."
log "This may take significant time for large time-series datasets..."
log "⏳ Please be patient, do not interrupt the process..."

START_TIME=$(date +%s)

if gunzip -c "$BACKUP_FILE" | psql -U "$POSTGRES_USER" -h "$POSTGRES_HOST" -p "$POSTGRES_PORT"; then
    log "✓ Restore completed successfully"
else
    error "✗ Restore failed! Check PostgreSQL logs for details."
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
log "Restore duration: $DURATION seconds"

# Update TimescaleDB extension if needed
log "Updating TimescaleDB extension to latest version..."
if psql -U "$POSTGRES_USER" -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -d postgres -c "ALTER EXTENSION timescaledb UPDATE;" >/dev/null 2>&1; then
    log "✓ TimescaleDB extension updated"
else
    warn "TimescaleDB extension update not needed or failed"
fi

# Run ANALYZE to update statistics
log "Running ANALYZE to update query planner statistics..."
log "This is especially important for TimescaleDB hypertables..."
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

# Verify TimescaleDB hypertables
log "Verifying TimescaleDB hypertables..."
HYPERTABLE_COUNT=$(psql -U "$POSTGRES_USER" -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -d postgres -t -c "SELECT count(*) FROM timescaledb_information.hypertables;" 2>/dev/null || echo "0")
log "Total hypertables found: $HYPERTABLE_COUNT"

if [ "$HYPERTABLE_COUNT" -gt 0 ]; then
    log "Listing hypertables:"
    psql -U "$POSTGRES_USER" -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -d postgres -c "SELECT * FROM timescaledb_information.hypertables;" | head -20
fi

# Check compression settings
log "Checking compression settings..."
COMPRESSED_CHUNKS=$(psql -U "$POSTGRES_USER" -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -d postgres -t -c "SELECT count(*) FROM timescaledb_information.chunks WHERE is_compressed = true;" 2>/dev/null || echo "0")
log "Compressed chunks: $COMPRESSED_CHUNKS"

# Final summary
log "========================================="
log "TimescaleDB Restore Summary"
log "========================================="
log "Backup File: $BACKUP_FILE"
log "Restore Duration: $DURATION seconds"
log "Databases Count: $DB_COUNT"
log "Hypertables Count: $HYPERTABLE_COUNT"
log "Compressed Chunks: $COMPRESSED_CHUNKS"
log "TimescaleDB Version: $TSDB_VERSION"
log "Safety Backup: $SAFETY_BACKUP"
log "========================================="
log "✓ Restore completed successfully!"
log ""
log "Next Steps:"
log "1. Verify hypertables: SELECT * FROM timescaledb_information.hypertables;"
log "2. Check compression: SELECT * FROM timescaledb_information.compression_settings;"
log "3. Test queries against time-series data"
log "4. Check application connection strings point to this VM"
log "5. Monitor PostgreSQL logs for any errors"
log "6. Keep safety backup for rollback: $SAFETY_BACKUP"

exit 0
