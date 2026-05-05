#!/bin/bash
#
# Redis 7.4.8 Restore Script for VM
# Restores Redis RDB file
#

set -euo pipefail

# Configuration
REDIS_DATA_DIR="${REDIS_DATA_DIR:-/var/lib/redis}"
REDIS_USER="${REDIS_USER:-redis}"
REDIS_GROUP="${REDIS_GROUP:-redis}"
REDIS_SERVICE="${REDIS_SERVICE:-redis}"
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

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error "This script must be run as root (use sudo)"
fi

# Usage
if [ -z "$BACKUP_FILE" ]; then
    echo "Usage: sudo $0 <backup-file.rdb.gz>"
    echo ""
    echo "Example:"
    echo "  sudo $0 /backup/redis-20260505-120000/redis-dump-20260505-120000.rdb.gz"
    echo ""
    echo "Environment Variables:"
    echo "  REDIS_DATA_DIR   - Redis data directory (default: /var/lib/redis)"
    echo "  REDIS_USER       - Redis user (default: redis)"
    echo "  REDIS_SERVICE    - Redis service name (default: redis)"
    exit 1
fi

# Check if backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
    error "Backup file not found: $BACKUP_FILE"
fi

log "========================================="
log "Redis Restore Process"
log "========================================="
log "Backup File: $BACKUP_FILE"
log "Redis Data Dir: $REDIS_DATA_DIR"
log "Redis User: $REDIS_USER"
log "Redis Service: $REDIS_SERVICE"
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

# Check if Redis service exists
if ! systemctl list-unit-files | grep -q "^${REDIS_SERVICE}.service"; then
    error "Redis service not found: $REDIS_SERVICE"
fi

# Check Redis status
REDIS_STATUS=$(systemctl is-active "$REDIS_SERVICE" || echo "inactive")
log "Current Redis status: $REDIS_STATUS"

# Warning about existing data
warn "⚠️  WARNING: This will OVERWRITE existing Redis data!"
read -p "Are you sure you want to proceed? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    log "Restore cancelled by user"
    exit 0
fi

# Backup existing RDB file (safety measure)
if [ -f "$REDIS_DATA_DIR/dump.rdb" ]; then
    SAFETY_BACKUP="/tmp/redis-dump-safety-$(date +%Y%m%d-%H%M%S).rdb"
    log "Creating safety backup of existing RDB file..."
    if cp "$REDIS_DATA_DIR/dump.rdb" "$SAFETY_BACKUP"; then
        log "✓ Safety backup created: $SAFETY_BACKUP"
    else
        warn "Could not create safety backup, but continuing..."
    fi
fi

# Stop Redis service
log "Stopping Redis service..."
if systemctl stop "$REDIS_SERVICE"; then
    log "✓ Redis service stopped"
else
    error "✗ Failed to stop Redis service"
fi

# Wait for Redis to fully stop
sleep 2

# Extract and restore RDB file
log "Restoring Redis RDB file..."
TEMP_RDB="/tmp/restore-dump-$(date +%Y%m%d-%H%M%S).rdb"

if gunzip -c "$BACKUP_FILE" > "$TEMP_RDB"; then
    log "✓ RDB file decompressed"
else
    error "✗ Failed to decompress RDB file"
fi

# Copy RDB file to Redis data directory
log "Copying RDB file to Redis data directory..."
if cp "$TEMP_RDB" "$REDIS_DATA_DIR/dump.rdb"; then
    log "✓ RDB file copied successfully"
else
    error "✗ Failed to copy RDB file"
fi

# Set proper permissions
log "Setting file permissions..."
chown "$REDIS_USER:$REDIS_GROUP" "$REDIS_DATA_DIR/dump.rdb"
chmod 640 "$REDIS_DATA_DIR/dump.rdb"
log "✓ Permissions set"

# Cleanup temp file
rm -f "$TEMP_RDB"

# Start Redis service
log "Starting Redis service..."
if systemctl start "$REDIS_SERVICE"; then
    log "✓ Redis service started"
else
    error "✗ Failed to start Redis service"
fi

# Wait for Redis to start
sleep 3

# Verify Redis is running
log "Verifying Redis is running..."
MAX_RETRIES=10
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if redis-cli ping >/dev/null 2>&1; then
        log "✓ Redis is responding to PING"
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    sleep 1
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    error "✗ Redis is not responding after restore"
fi

# Get keyspace info
log "Checking keyspace statistics..."
KEYSPACE_INFO=$(redis-cli INFO keyspace | grep -v "^#" | grep -v "^$")
if [ -n "$KEYSPACE_INFO" ]; then
    log "Keyspace Info:"
    echo "$KEYSPACE_INFO" | while read line; do
        log "  $line"
    done
else
    warn "No keys found in keyspace (database may be empty)"
fi

# Get memory info
MEMORY_USED=$(redis-cli INFO memory | grep "used_memory_human:" | cut -d: -f2 | tr -d '\r')
log "Memory used: $MEMORY_USED"

# Final summary
log "========================================="
log "Redis Restore Summary"
log "========================================="
log "Backup File: $BACKUP_FILE"
log "Redis Status: $(systemctl is-active "$REDIS_SERVICE")"
log "Memory Used: $MEMORY_USED"
log "Safety Backup: ${SAFETY_BACKUP:-N/A}"
log "========================================="
log "✓ Restore completed successfully!"
log ""
log "Next Steps:"
log "1. Verify data by running: redis-cli GET <key>"
log "2. Check application connection strings point to this VM"
log "3. Monitor Redis logs: journalctl -u $REDIS_SERVICE -f"
log "4. Keep safety backup for rollback: ${SAFETY_BACKUP:-N/A}"

exit 0
