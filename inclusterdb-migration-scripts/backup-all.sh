#!/bin/bash
#
# Master Backup Script - Runs all database backups
# Executes backups for PostgreSQL, MongoDB, Redis, and TimescaleDB
#

set -euo pipefail

# Configuration
NAMESPACE="${NAMESPACE:-harness}"
BACKUP_ROOT="${BACKUP_ROOT:-/backup/harness-migration-$(date +%Y%m%d-%H%M%S)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

section() {
    echo ""
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}=========================================${NC}"
}

# Create main backup directory
mkdir -p "$BACKUP_ROOT"
MAIN_LOG="$BACKUP_ROOT/backup-all.log"

log "Starting Harness SMP database backup process"
log "Backup root directory: $BACKUP_ROOT"
log "Kubernetes namespace: $NAMESPACE"
log "Log file: $MAIN_LOG"

# Check kubectl connectivity
log "Checking Kubernetes connectivity..."
if ! kubectl cluster-info >/dev/null 2>&1; then
    error "Cannot connect to Kubernetes cluster. Please check your kubectl configuration."
fi
log "✓ Connected to Kubernetes cluster"

# Check namespace exists
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    error "Namespace '$NAMESPACE' not found"
fi
log "✓ Namespace '$NAMESPACE' exists"

# Track backup results
BACKUP_RESULTS=()
START_TIME_TOTAL=$(date +%s)

# Function to run backup script
run_backup() {
    local script_name=$1
    local display_name=$2

    section "Backing up $display_name"

    local script_path="$SCRIPT_DIR/backup/$script_name"

    if [ ! -f "$script_path" ]; then
        warn "Backup script not found: $script_path"
        BACKUP_RESULTS+=("$display_name: SKIPPED (script not found)")
        return 1
    fi

    # Make script executable
    chmod +x "$script_path"

    log "Running: $script_name"

    if NAMESPACE="$NAMESPACE" BACKUP_ROOT="$BACKUP_ROOT" "$script_path" >> "$MAIN_LOG" 2>&1; then
        log "✓ $display_name backup completed successfully"
        BACKUP_RESULTS+=("$display_name: SUCCESS")
        return 0
    else
        warn "✗ $display_name backup failed (check logs)"
        BACKUP_RESULTS+=("$display_name: FAILED")
        return 1
    fi
}

# Backup PostgreSQL
run_backup "01-backup-postgres.sh" "PostgreSQL 14.20"

# Backup MongoDB
run_backup "02-backup-mongodb.sh" "MongoDB 6.0.1"

# Backup Redis
run_backup "03-backup-redis.sh" "Redis 7.4.8"

# Backup TimescaleDB
run_backup "04-backup-timescaledb.sh" "TimescaleDB (PG13 + TS2.9)"

# Calculate total time
END_TIME_TOTAL=$(date +%s)
DURATION_TOTAL=$((END_TIME_TOTAL - START_TIME_TOTAL))
DURATION_MIN=$((DURATION_TOTAL / 60))
DURATION_SEC=$((DURATION_TOTAL % 60))

# Calculate total backup size
TOTAL_SIZE=$(du -sh "$BACKUP_ROOT" | cut -f1)

# Final summary
section "Backup Summary"
log "Backup Location: $BACKUP_ROOT"
log "Total Duration: ${DURATION_MIN}m ${DURATION_SEC}s"
log "Total Size: $TOTAL_SIZE"
log ""
log "Backup Results:"

SUCCESS_COUNT=0
FAILED_COUNT=0

for result in "${BACKUP_RESULTS[@]}"; do
    if echo "$result" | grep -q "SUCCESS"; then
        log "  ✓ $result"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    elif echo "$result" | grep -q "FAILED"; then
        warn "  ✗ $result"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    else
        log "  ⊘ $result"
    fi
done

log ""
log "Summary: $SUCCESS_COUNT successful, $FAILED_COUNT failed"

# Create manifest file
cat > "$BACKUP_ROOT/MANIFEST.txt" <<EOF
Harness SMP Database Backup Manifest
=====================================

Backup Date: $(date)
Kubernetes Namespace: $NAMESPACE
Backup Duration: ${DURATION_MIN}m ${DURATION_SEC}s
Total Backup Size: $TOTAL_SIZE

Databases Backed Up:
$(for result in "${BACKUP_RESULTS[@]}"; do echo "  - $result"; done)

Backup Files:
$(find "$BACKUP_ROOT" -type f -name "*.gz" -o -name "*.tar.gz" | while read file; do
    echo "  - $(basename "$file") ($(du -h "$file" | cut -f1))"
done)

Next Steps:
1. Verify backup integrity by checking .sha256 files
2. Transfer backups to VM environment
3. Test restore on non-production VM first
4. Follow restore procedures in DATABASE_MIGRATION_GUIDE.md

EOF

log "Manifest created: $BACKUP_ROOT/MANIFEST.txt"

# Show backup contents
log ""
log "Backup directory contents:"
ls -lh "$BACKUP_ROOT" | tail -n +2

if [ $FAILED_COUNT -gt 0 ]; then
    error "Some backups failed. Please check logs at: $MAIN_LOG"
fi

log ""
log "========================================="
log "✓ All backups completed successfully!"
log "========================================="
log ""
log "Backup location: $BACKUP_ROOT"
log "To transfer backups to VMs:"
log "  rsync -avz --progress $BACKUP_ROOT/ user@vm-host:/backup/"
log ""
log "To restore on VMs, run the corresponding restore scripts:"
log "  ./restore/01-restore-postgres-vm.sh <backup-file>"
log "  ./restore/02-restore-mongodb-vm.sh <backup-file>"
log "  ./restore/03-restore-redis-vm.sh <backup-file>"
log "  ./restore/04-restore-timescaledb-vm.sh <backup-file>"

exit 0
