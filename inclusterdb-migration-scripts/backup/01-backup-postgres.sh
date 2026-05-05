#!/bin/bash
#
# PostgreSQL 14.20 Backup Script for Kubernetes
# Performs full pg_dumpall backup
#

set -euo pipefail

# Configuration
NAMESPACE="${NAMESPACE:-harness}"
BACKUP_ROOT="${BACKUP_ROOT:-/backup}"
BACKUP_DIR="$BACKUP_ROOT/postgres-$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$BACKUP_DIR/backup.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
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

# Get PostgreSQL pod
log "Finding PostgreSQL pod in namespace: $NAMESPACE"
POSTGRES_POD=$(kubectl get pods -n "$NAMESPACE" \
    -l app.kubernetes.io/name=postgresql \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$POSTGRES_POD" ]; then
    error "PostgreSQL pod not found in namespace $NAMESPACE"
fi

log "Found PostgreSQL pod: $POSTGRES_POD"

# Get PostgreSQL password
log "Retrieving PostgreSQL credentials..."
POSTGRES_PASSWORD=$(kubectl get secret -n "$NAMESPACE" \
    -l app.kubernetes.io/name=postgresql \
    -o jsonpath='{.items[0].data.postgres-password}' 2>/dev/null | base64 -d)

if [ -z "$POSTGRES_PASSWORD" ]; then
    warn "Could not retrieve password from secrets, trying environment variable"
    POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"
fi

# Backup filename
BACKUP_FILE="postgres-full-$(date +%Y%m%d-%H%M%S).sql"

# Perform backup
log "Starting PostgreSQL backup..."
log "This may take several minutes depending on database size..."

if kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- bash -c \
    "PGPASSWORD='$POSTGRES_PASSWORD' pg_dumpall -U postgres" > "$BACKUP_DIR/$BACKUP_FILE"; then
    log "Backup completed successfully"
else
    error "Backup failed"
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

# Get database statistics
log "Collecting database statistics..."
kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- bash -c \
    "PGPASSWORD='$POSTGRES_PASSWORD' psql -U postgres -c '\l+'" \
    > "$BACKUP_DIR/database-list.txt" 2>/dev/null || warn "Could not retrieve database list"

kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- bash -c \
    "PGPASSWORD='$POSTGRES_PASSWORD' psql -U postgres -c 'SELECT version();'" \
    > "$BACKUP_DIR/postgres-version.txt" 2>/dev/null || warn "Could not retrieve PostgreSQL version"

# Final summary
log "========================================="
log "PostgreSQL Backup Summary"
log "========================================="
log "Namespace: $NAMESPACE"
log "Pod: $POSTGRES_POD"
log "Backup Directory: $BACKUP_DIR"
log "Backup File: $BACKUP_FILE.gz"
log "Compressed Size: $(du -h "$BACKUP_DIR/$BACKUP_FILE.gz" | cut -f1)"
log "Checksum: $CHECKSUM"
log "========================================="
log "Backup completed successfully!"

# Create metadata file
cat > "$BACKUP_DIR/metadata.txt" <<EOF
Backup Timestamp: $(date)
Database: PostgreSQL 14.20
Namespace: $NAMESPACE
Pod: $POSTGRES_POD
Backup File: $BACKUP_FILE.gz
Checksum: $CHECKSUM
EOF

exit 0
