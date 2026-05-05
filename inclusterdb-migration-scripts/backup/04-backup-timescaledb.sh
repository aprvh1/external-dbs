#!/bin/bash
#
# TimescaleDB (PG13 + TS2.9) Backup Script for Kubernetes
# Performs full pg_dumpall with TimescaleDB support
#

set -euo pipefail

# Configuration
NAMESPACE="${NAMESPACE:-harness}"
BACKUP_ROOT="${BACKUP_ROOT:-/backup}"
BACKUP_DIR="$BACKUP_ROOT/timescaledb-$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$BACKUP_DIR/backup.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

# Create backup directory
mkdir -p "$BACKUP_DIR"
log "Created backup directory: $BACKUP_DIR"

# Get TimescaleDB pod
log "Finding TimescaleDB pod in namespace: $NAMESPACE"
TSDB_POD=$(kubectl get pods -n "$NAMESPACE" \
    -l app=timescaledb \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$TSDB_POD" ]; then
    # Try alternative label
    TSDB_POD=$(kubectl get pods -n "$NAMESPACE" \
        -l app.kubernetes.io/name=timescaledb \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
fi

if [ -z "$TSDB_POD" ]; then
    error "TimescaleDB pod not found in namespace $NAMESPACE"
fi

log "Found TimescaleDB pod: $TSDB_POD"

# Get TimescaleDB password
log "Retrieving TimescaleDB credentials..."
TSDB_PASSWORD=$(kubectl get secret -n "$NAMESPACE" \
    -l app=timescaledb \
    -o jsonpath='{.items[0].data.password}' 2>/dev/null | base64 -d)

if [ -z "$TSDB_PASSWORD" ]; then
    warn "Could not retrieve password from secrets"
    TSDB_PASSWORD="${TIMESCALEDB_PASSWORD:-}"
fi

# Backup filename
BACKUP_FILE="timescaledb-full-$(date +%Y%m%d-%H%M%S).sql"

# Perform backup
log "Starting TimescaleDB backup..."
log "This may take significant time for large time-series datasets..."

if kubectl exec -n "$NAMESPACE" "$TSDB_POD" -- bash -c \
    "PGPASSWORD='$TSDB_PASSWORD' pg_dumpall -U postgres \
    --exclude-database=template0 \
    --exclude-database=template1" > "$BACKUP_DIR/$BACKUP_FILE"; then
    log "Backup completed successfully"
else
    error "Backup failed"
fi

# Get backup size
BACKUP_SIZE=$(du -h "$BACKUP_DIR/$BACKUP_FILE" | cut -f1)
log "Backup size: $BACKUP_SIZE"

# Compress backup
log "Compressing backup (this may take a while for large backups)..."
if gzip "$BACKUP_DIR/$BACKUP_FILE"; then
    log "Compression completed"
else
    error "Compression failed"
fi

# Calculate checksum
log "Calculating checksum..."
sha256sum "$BACKUP_DIR/$BACKUP_FILE.gz" > "$BACKUP_DIR/$BACKUP_FILE.gz.sha256"
CHECKSUM=$(cut -d' ' -f1 "$BACKUP_DIR/$BACKUP_FILE.gz.sha256")
log "Checksum: $CHECKSUM"

# Get database statistics
log "Collecting TimescaleDB statistics..."

# List databases
kubectl exec -n "$NAMESPACE" "$TSDB_POD" -- bash -c \
    "PGPASSWORD='$TSDB_PASSWORD' psql -U postgres -c '\l+'" \
    > "$BACKUP_DIR/database-list.txt" 2>/dev/null || warn "Could not retrieve database list"

# TimescaleDB version
kubectl exec -n "$NAMESPACE" "$TSDB_POD" -- bash -c \
    "PGPASSWORD='$TSDB_PASSWORD' psql -U postgres -c 'SELECT version();'" \
    > "$BACKUP_DIR/postgres-version.txt" 2>/dev/null || warn "Could not retrieve PostgreSQL version"

kubectl exec -n "$NAMESPACE" "$TSDB_POD" -- bash -c \
    "PGPASSWORD='$TSDB_PASSWORD' psql -U postgres -c 'SELECT extversion FROM pg_extension WHERE extname='\''timescaledb'\'';'" \
    > "$BACKUP_DIR/timescaledb-version.txt" 2>/dev/null || warn "Could not retrieve TimescaleDB version"

# Hypertables info
kubectl exec -n "$NAMESPACE" "$TSDB_POD" -- bash -c \
    "PGPASSWORD='$TSDB_PASSWORD' psql -U postgres -c 'SELECT * FROM timescaledb_information.hypertables;'" \
    > "$BACKUP_DIR/hypertables-info.txt" 2>/dev/null || warn "Could not retrieve hypertables info"

# Chunk info
kubectl exec -n "$NAMESPACE" "$TSDB_POD" -- bash -c \
    "PGPASSWORD='$TSDB_PASSWORD' psql -U postgres -c 'SELECT * FROM timescaledb_information.chunks LIMIT 100;'" \
    > "$BACKUP_DIR/chunks-info.txt" 2>/dev/null || warn "Could not retrieve chunks info"

# Compression settings
kubectl exec -n "$NAMESPACE" "$TSDB_POD" -- bash -c \
    "PGPASSWORD='$TSDB_PASSWORD' psql -U postgres -c 'SELECT * FROM timescaledb_information.compression_settings;'" \
    > "$BACKUP_DIR/compression-settings.txt" 2>/dev/null || warn "Could not retrieve compression settings"

# Final summary
log "========================================="
log "TimescaleDB Backup Summary"
log "========================================="
log "Namespace: $NAMESPACE"
log "Pod: $TSDB_POD"
log "Backup Directory: $BACKUP_DIR"
log "Backup File: $BACKUP_FILE.gz"
log "Original Size: $BACKUP_SIZE"
log "Compressed Size: $(du -h "$BACKUP_DIR/$BACKUP_FILE.gz" | cut -f1)"
log "Checksum: $CHECKSUM"
log "========================================="
log "Backup completed successfully!"

# Create metadata file
cat > "$BACKUP_DIR/metadata.txt" <<EOF
Backup Timestamp: $(date)
Database: TimescaleDB (PostgreSQL 13 + TimescaleDB 2.9)
Namespace: $NAMESPACE
Pod: $TSDB_POD
Backup File: $BACKUP_FILE.gz
Checksum: $CHECKSUM
Original Size: $BACKUP_SIZE
Compressed Size: $(du -h "$BACKUP_DIR/$BACKUP_FILE.gz" | cut -f1)
EOF

exit 0
