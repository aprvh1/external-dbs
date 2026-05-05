#!/bin/bash
#
# MongoDB 6.0.1 Backup Script for Kubernetes
# Performs mongodump backup
#

set -euo pipefail

# Configuration
NAMESPACE="${NAMESPACE:-harness}"
BACKUP_ROOT="${BACKUP_ROOT:-/backup}"
BACKUP_DIR="$BACKUP_ROOT/mongodb-$(date +%Y%m%d-%H%M%S)"
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

# Get MongoDB pod
log "Finding MongoDB pod in namespace: $NAMESPACE"
MONGO_POD=$(kubectl get pods -n "$NAMESPACE" \
    -l app.kubernetes.io/name=mongodb \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$MONGO_POD" ]; then
    error "MongoDB pod not found in namespace $NAMESPACE"
fi

log "Found MongoDB pod: $MONGO_POD"

# Get MongoDB password
log "Retrieving MongoDB credentials..."
MONGO_PASSWORD=$(kubectl get secret -n "$NAMESPACE" \
    -l app.kubernetes.io/name=mongodb \
    -o jsonpath='{.items[0].data.mongodb-root-password}' 2>/dev/null | base64 -d)

if [ -z "$MONGO_PASSWORD" ]; then
    warn "Could not retrieve password from secrets"
    MONGO_PASSWORD="${MONGO_PASSWORD:-}"
fi

# Create backup directory in pod
log "Creating backup directory in pod..."
kubectl exec -n "$NAMESPACE" "$MONGO_POD" -- mkdir -p /tmp/mongodb-backup

# Perform mongodump
log "Starting MongoDB backup..."
log "This may take several minutes depending on database size..."

if kubectl exec -n "$NAMESPACE" "$MONGO_POD" -- bash -c \
    "mongodump --username=root --password='$MONGO_PASSWORD' \
    --authenticationDatabase=admin \
    --out=/tmp/mongodb-backup"; then
    log "Mongodump completed successfully"
else
    error "Mongodump failed"
fi

# Copy backup from pod
log "Copying backup from pod to local filesystem..."
if kubectl cp -n "$NAMESPACE" "$MONGO_POD:/tmp/mongodb-backup" "$BACKUP_DIR/mongodb"; then
    log "Backup copied successfully"
else
    error "Failed to copy backup from pod"
fi

# Compress backup
log "Compressing backup..."
BACKUP_FILE="mongodb-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
if tar -czf "$BACKUP_DIR/$BACKUP_FILE" -C "$BACKUP_DIR" mongodb; then
    log "Compression completed"
else
    error "Compression failed"
fi

# Calculate checksum
log "Calculating checksum..."
sha256sum "$BACKUP_DIR/$BACKUP_FILE" > "$BACKUP_DIR/$BACKUP_FILE.sha256"
CHECKSUM=$(cut -d' ' -f1 "$BACKUP_DIR/$BACKUP_FILE.sha256")
log "Checksum: $CHECKSUM"

# Get database statistics
log "Collecting database statistics..."
kubectl exec -n "$NAMESPACE" "$MONGO_POD" -- bash -c \
    "mongosh --username=root --password='$MONGO_PASSWORD' \
    --authenticationDatabase=admin \
    --eval 'db.adminCommand({listDatabases: 1})'" \
    > "$BACKUP_DIR/database-list.txt" 2>/dev/null || warn "Could not retrieve database list"

kubectl exec -n "$NAMESPACE" "$MONGO_POD" -- bash -c \
    "mongosh --version" \
    > "$BACKUP_DIR/mongodb-version.txt" 2>/dev/null || warn "Could not retrieve MongoDB version"

# Cleanup pod backup
log "Cleaning up temporary files in pod..."
kubectl exec -n "$NAMESPACE" "$MONGO_POD" -- rm -rf /tmp/mongodb-backup

# Remove uncompressed directory
rm -rf "$BACKUP_DIR/mongodb"

# Final summary
log "========================================="
log "MongoDB Backup Summary"
log "========================================="
log "Namespace: $NAMESPACE"
log "Pod: $MONGO_POD"
log "Backup Directory: $BACKUP_DIR"
log "Backup File: $BACKUP_FILE"
log "Compressed Size: $(du -h "$BACKUP_DIR/$BACKUP_FILE" | cut -f1)"
log "Checksum: $CHECKSUM"
log "========================================="
log "Backup completed successfully!"

# Create metadata file
cat > "$BACKUP_DIR/metadata.txt" <<EOF
Backup Timestamp: $(date)
Database: MongoDB 6.0.1
Namespace: $NAMESPACE
Pod: $MONGO_POD
Backup File: $BACKUP_FILE
Checksum: $CHECKSUM
EOF

exit 0
