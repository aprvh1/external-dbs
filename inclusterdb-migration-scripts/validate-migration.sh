#!/bin/bash
#
# Database Migration Validation Script
# Validates data integrity and connectivity after migration to VMs
#

set -euo pipefail

# Configuration
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
MONGO_HOST="${MONGO_HOST:-localhost}"
MONGO_USER="${MONGO_USER:-root}"
MONGO_PASSWORD="${MONGO_PASSWORD:-}"
REDIS_HOST="${REDIS_HOST:-localhost}"
TSDB_HOST="${TSDB_HOST:-localhost}"
TSDB_USER="${TSDB_USER:-postgres}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNINGS=0

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
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

test_pass() {
    log "✓ $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

test_fail() {
    error "✗ $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

test_warn() {
    warn "⚠ $1"
    TESTS_WARNINGS=$((TESTS_WARNINGS + 1))
}

# PostgreSQL Validation
section "PostgreSQL 14.20 Validation"

log "Testing PostgreSQL connectivity..."
if psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -c "SELECT 1;" >/dev/null 2>&1; then
    test_pass "PostgreSQL is accessible"

    # Check version
    PG_VERSION=$(psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -t -c "SELECT version();" | head -1)
    log "PostgreSQL Version: $PG_VERSION"

    # Check database count
    DB_COUNT=$(psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -t -c "SELECT count(*) FROM pg_database WHERE datistemplate = false;")
    log "Database count: $DB_COUNT"

    if [ "$DB_COUNT" -gt 0 ]; then
        test_pass "Found $DB_COUNT databases"
    else
        test_fail "No databases found"
    fi

    # Check connections
    ACTIVE_CONN=$(psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -t -c "SELECT count(*) FROM pg_stat_activity;")
    log "Active connections: $ACTIVE_CONN"

    # List databases
    log "Databases:"
    psql -h "$POSTGRES_HOST" -U "$POSTGRES_USER" -c "\l" | head -20

else
    test_fail "Cannot connect to PostgreSQL"
fi

# MongoDB Validation
section "MongoDB 6.0.1 Validation"

if [ -z "$MONGO_PASSWORD" ]; then
    test_warn "MONGO_PASSWORD not set, skipping MongoDB tests"
else
    log "Testing MongoDB connectivity..."
    if mongosh --host "$MONGO_HOST" --username "$MONGO_USER" --password "$MONGO_PASSWORD" --authenticationDatabase admin --eval "db.version()" >/dev/null 2>&1; then
        test_pass "MongoDB is accessible"

        # Check version
        MONGO_VERSION=$(mongosh --host "$MONGO_HOST" --username "$MONGO_USER" --password "$MONGO_PASSWORD" --authenticationDatabase admin --quiet --eval "db.version()")
        log "MongoDB Version: $MONGO_VERSION"

        # List databases
        log "Databases:"
        mongosh --host "$MONGO_HOST" --username "$MONGO_USER" --password "$MONGO_PASSWORD" --authenticationDatabase admin --quiet --eval "db.adminCommand({listDatabases: 1}).databases.forEach(d => print(d.name + ' - ' + (d.sizeOnDisk / 1024 / 1024 / 1024).toFixed(2) + ' GB'))"

        # Check collections in each database
        DB_LIST=$(mongosh --host "$MONGO_HOST" --username "$MONGO_USER" --password "$MONGO_PASSWORD" --authenticationDatabase admin --quiet --eval "db.adminCommand({listDatabases: 1}).databases.map(d => d.name).join(' ')")

        TOTAL_COLLECTIONS=0
        for db in $DB_LIST; do
            if [ "$db" != "admin" ] && [ "$db" != "local" ] && [ "$db" != "config" ]; then
                COLL_COUNT=$(mongosh --host "$MONGO_HOST" --username "$MONGO_USER" --password "$MONGO_PASSWORD" --authenticationDatabase admin --quiet --eval "use $db; db.getCollectionNames().length" 2>/dev/null || echo "0")
                log "  $db: $COLL_COUNT collections"
                TOTAL_COLLECTIONS=$((TOTAL_COLLECTIONS + COLL_COUNT))
            fi
        done

        if [ $TOTAL_COLLECTIONS -gt 0 ]; then
            test_pass "Found $TOTAL_COLLECTIONS collections across databases"
        else
            test_warn "No collections found"
        fi

    else
        test_fail "Cannot connect to MongoDB"
    fi
fi

# Redis Validation
section "Redis 7.4.8 Validation"

log "Testing Redis connectivity..."
if redis-cli -h "$REDIS_HOST" ping >/dev/null 2>&1; then
    test_pass "Redis is accessible"

    # Check version
    REDIS_VERSION=$(redis-cli -h "$REDIS_HOST" INFO server | grep "redis_version:" | cut -d: -f2 | tr -d '\r')
    log "Redis Version: $REDIS_VERSION"

    # Check keyspace
    KEYSPACE=$(redis-cli -h "$REDIS_HOST" INFO keyspace | grep -v "^#" | grep -v "^$")
    if [ -n "$KEYSPACE" ]; then
        log "Keyspace statistics:"
        echo "$KEYSPACE" | while read line; do
            log "  $line"
        done
        test_pass "Redis keyspace has data"
    else
        test_warn "Redis keyspace is empty"
    fi

    # Check memory usage
    MEMORY_USED=$(redis-cli -h "$REDIS_HOST" INFO memory | grep "used_memory_human:" | cut -d: -f2 | tr -d '\r')
    log "Memory used: $MEMORY_USED"

    # Check connected clients
    CLIENTS=$(redis-cli -h "$REDIS_HOST" INFO clients | grep "connected_clients:" | cut -d: -f2 | tr -d '\r')
    log "Connected clients: $CLIENTS"

else
    test_fail "Cannot connect to Redis"
fi

# TimescaleDB Validation
section "TimescaleDB (PG13 + TS2.9) Validation"

log "Testing TimescaleDB connectivity..."
if psql -h "$TSDB_HOST" -U "$TSDB_USER" -d postgres -c "SELECT 1;" >/dev/null 2>&1; then
    test_pass "TimescaleDB is accessible"

    # Check PostgreSQL version
    PG_VERSION=$(psql -h "$TSDB_HOST" -U "$TSDB_USER" -d postgres -t -c "SELECT version();" | head -1)
    log "PostgreSQL Version: $PG_VERSION"

    # Check TimescaleDB extension
    TSDB_INSTALLED=$(psql -h "$TSDB_HOST" -U "$TSDB_USER" -d postgres -t -c "SELECT count(*) FROM pg_extension WHERE extname='timescaledb';")

    if [ "$TSDB_INSTALLED" -gt 0 ]; then
        test_pass "TimescaleDB extension is installed"

        # Check TimescaleDB version
        TSDB_VERSION=$(psql -h "$TSDB_HOST" -U "$TSDB_USER" -d postgres -t -c "SELECT extversion FROM pg_extension WHERE extname='timescaledb';" | tr -d ' ')
        log "TimescaleDB Version: $TSDB_VERSION"

        # Check hypertables
        HYPERTABLE_COUNT=$(psql -h "$TSDB_HOST" -U "$TSDB_USER" -d postgres -t -c "SELECT count(*) FROM timescaledb_information.hypertables;" 2>/dev/null || echo "0")
        log "Hypertables: $HYPERTABLE_COUNT"

        if [ "$HYPERTABLE_COUNT" -gt 0 ]; then
            test_pass "Found $HYPERTABLE_COUNT hypertables"

            log "Hypertable details:"
            psql -h "$TSDB_HOST" -U "$TSDB_USER" -d postgres -c "SELECT hypertable_schema, hypertable_name, num_chunks FROM timescaledb_information.hypertables;" 2>/dev/null | head -20

            # Check compressed chunks
            COMPRESSED_CHUNKS=$(psql -h "$TSDB_HOST" -U "$TSDB_USER" -d postgres -t -c "SELECT count(*) FROM timescaledb_information.chunks WHERE is_compressed = true;" 2>/dev/null || echo "0")
            log "Compressed chunks: $COMPRESSED_CHUNKS"
        else
            test_warn "No hypertables found"
        fi

    else
        test_fail "TimescaleDB extension not installed"
    fi

    # Check database count
    DB_COUNT=$(psql -h "$TSDB_HOST" -U "$TSDB_USER" -d postgres -t -c "SELECT count(*) FROM pg_database WHERE datistemplate = false;")
    log "Database count: $DB_COUNT"

else
    test_fail "Cannot connect to TimescaleDB"
fi

# Network Latency Tests
section "Network Latency Tests"

log "Testing network latency to database VMs..."

for host in "$POSTGRES_HOST" "$MONGO_HOST" "$REDIS_HOST" "$TSDB_HOST"; do
    if [ "$host" != "localhost" ] && [ "$host" != "127.0.0.1" ]; then
        if command -v ping >/dev/null 2>&1; then
            LATENCY=$(ping -c 3 "$host" 2>/dev/null | tail -1 | awk -F '/' '{print $5}')
            if [ -n "$LATENCY" ]; then
                log "  $host: ${LATENCY}ms avg"
                if [ "$(echo "$LATENCY < 10" | bc 2>/dev/null || echo 0)" = "1" ]; then
                    test_pass "Excellent latency to $host"
                elif [ "$(echo "$LATENCY < 50" | bc 2>/dev/null || echo 0)" = "1" ]; then
                    test_warn "Moderate latency to $host (${LATENCY}ms)"
                else
                    test_warn "High latency to $host (${LATENCY}ms)"
                fi
            fi
        fi
    fi
done

# Final Summary
section "Validation Summary"

TOTAL_TESTS=$((TESTS_PASSED + TESTS_FAILED + TESTS_WARNINGS))

log "Total Tests: $TOTAL_TESTS"
log "  ✓ Passed: $TESTS_PASSED"
log "  ✗ Failed: $TESTS_FAILED"
log "  ⚠ Warnings: $TESTS_WARNINGS"

if [ $TESTS_FAILED -eq 0 ]; then
    log ""
    log "========================================="
    log "✓ All critical tests passed!"
    log "========================================="
    log ""
    log "Migration appears successful. Next steps:"
    log "1. Run application smoke tests"
    log "2. Update Harness connection strings to point to VMs"
    log "3. Monitor database performance and logs"
    log "4. Keep K8s databases running for 7-14 days as rollback option"
    exit 0
else
    error ""
    error "========================================="
    error "✗ $TESTS_FAILED test(s) failed!"
    error "========================================="
    error ""
    error "Please address the failures before proceeding with migration."
    exit 1
fi
