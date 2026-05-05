#!/bin/bash
#
# Redis 7.4.8 Backup Script for Kubernetes
# Performs BGSAVE and copies RDB file
#

set -euo pipefail

# Configuration
NAMESPACE="${NAMESPACE:-harness}"
BACKUP_ROOT="${BACKUP_ROOT:-/backup}"
BACKUP_DIR="$BACKUP_ROOT/redis-$(date +%Y%m%d-%H%M%S)"
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

# Get Redis master pod (in Sentinel mode, find the master)
log "Finding Redis master pod in namespace: $NAMESPACE"
REDIS_MASTER=$(kubectl get pods -n "$NAMESPACE" \
    -l app=redis \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$REDIS_MASTER" ]; then
    error "Redis pod not found in namespace $NAMESPACE"
fi

log "Found Redis pod: $REDIS_MASTER"

# Check if Redis is running
log "Checking Redis connectivity..."
if kubectl exec -n "$NAMESPACE" "$REDIS_MASTER" -- redis-cli ping >/dev/null 2>&1; then
    log "Redis is responding"
else
    error "Redis is not responding"
fi

# Get Redis info
log "Collecting Redis statistics..."
kubectl exec -n "$NAMESPACE" "$REDIS_MASTER" -- redis-cli INFO server \
    > "$BACKUP_DIR/redis-info.txt" 2>/dev/null || warn "Could not retrieve Redis info"

# Trigger BGSAVE
log "Triggering background save (BGSAVE)..."
if kubectl exec -n "$NAMESPACE" "$REDIS_MASTER" -- redis-cli BGSAVE >/dev/null 2>&1; then
    log "BGSAVE initiated successfully"
else
    error "Failed to trigger BGSAVE"
fi

# Wait for BGSAVE to complete
log "Waiting for BGSAVE to complete..."
TIMEOUT=300 # 5 minutes timeout
ELAPSED=0
INTERVAL=5

while [ $ELAPSED -lt $TIMEOUT ]; do
    LAST_SAVE=$(kubectl exec -n "$NAMESPACE" "$REDIS_MASTER" -- redis-cli LASTSAVE)
    sleep $INTERVAL
    NEW_SAVE=$(kubectl exec -n "$NAMESPACE" "$REDIS_MASTER" -- redis-cli LASTSAVE)

    if [ "$NEW_SAVE" -gt "$LAST_SAVE" ]; then
        log "BGSAVE completed successfully"
        break
    fi

    ELAPSED=$((ELAPSED + INTERVAL))
    echo -n "." | tee -a "$LOG_FILE"
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    error "BGSAVE timeout after $TIMEOUT seconds"
fi

# Copy RDB file
BACKUP_FILE="redis-dump-$(date +%Y%m%d-%H%M%S).rdb"
log "Copying Redis RDB file..."

if kubectl cp -n "$NAMESPACE" "$REDIS_MASTER:/data/dump.rdb" "$BACKUP_DIR/$BACKUP_FILE"; then
    log "RDB file copied successfully"
else
    error "Failed to copy RDB file"
fi

# Get backup size
BACKUP_SIZE=$(du -h "$BACKUP_DIR/$BACKUP_FILE" | cut -f1)
log "Backup size: $BACKUP_SIZE"

# Compress backup
log "Compressing backup..."
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

# Get keyspace info
log "Collecting keyspace statistics..."
kubectl exec -n "$NAMESPACE" "$REDIS_MASTER" -- redis-cli INFO keyspace \
    > "$BACKUP_DIR/keyspace-info.txt" 2>/dev/null || warn "Could not retrieve keyspace info"

# Final summary
log "========================================="
log "Redis Backup Summary"
log "========================================="
log "Namespace: $NAMESPACE"
log "Pod: $REDIS_MASTER"
log "Backup Directory: $BACKUP_DIR"
log "Backup File: $BACKUP_FILE.gz"
log "Compressed Size: $(du -h "$BACKUP_DIR/$BACKUP_FILE.gz" | cut -f1)"
log "Checksum: $CHECKSUM"
log "========================================="
log "Backup completed successfully!"

# Create metadata file
cat > "$BACKUP_DIR/metadata.txt" <<EOF
Backup Timestamp: $(date)
Database: Redis 7.4.8
Namespace: $NAMESPACE
Pod: $REDIS_MASTER
Backup File: $BACKUP_FILE.gz
Checksum: $CHECKSUM
EOF

exit 0
