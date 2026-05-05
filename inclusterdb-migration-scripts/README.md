# Harness SMP Database Migration Scripts

Automated backup and restore scripts for migrating Harness SMP databases from Kubernetes to VM-based clusters.

## 📦 What's Included

```
migration-scripts/
├── backup/                          # Kubernetes backup scripts
│   ├── 01-backup-postgres.sh       # PostgreSQL 14.20
│   ├── 02-backup-mongodb.sh        # MongoDB 6.0.1
│   ├── 03-backup-redis.sh          # Redis 7.4.8
│   └── 04-backup-timescaledb.sh    # TimescaleDB (PG13 + TS2.9)
├── restore/                         # VM restore scripts
│   ├── 01-restore-postgres-vm.sh
│   ├── 02-restore-mongodb-vm.sh
│   ├── 03-restore-redis-vm.sh
│   └── 04-restore-timescaledb-vm.sh
├── backup-all.sh                    # Master backup script (runs all backups)
├── validate-migration.sh            # Post-migration validation
└── README.md                        # This file
```

## 🚀 Quick Start

### Step 1: Backup from Kubernetes

```bash
# Set your namespace
export NAMESPACE="harness"

# Run all backups
./backup-all.sh

# Or run individual backups
cd backup/
./01-backup-postgres.sh
./02-backup-mongodb.sh
./03-backup-redis.sh
./04-backup-timescaledb.sh
```

**Output**: Backups will be stored in `/backup/harness-migration-<timestamp>/`

### Step 2: Transfer Backups to VMs

```bash
# Transfer all backups
rsync -avz --progress /backup/harness-migration-*/ user@vm-host:/backup/

# Or use scp
scp -r /backup/harness-migration-*/ user@vm-host:/backup/
```

### Step 3: Restore on VMs

```bash
# On each VM, run the corresponding restore script

# PostgreSQL VM
./restore/01-restore-postgres-vm.sh /backup/harness-migration-*/postgres-*/postgres-full-*.sql.gz

# MongoDB VM
export MONGO_PASSWORD="your-password"
./restore/02-restore-mongodb-vm.sh /backup/harness-migration-*/mongodb-*/mongodb-backup-*.tar.gz

# Redis VM (requires sudo)
sudo ./restore/03-restore-redis-vm.sh /backup/harness-migration-*/redis-*/redis-dump-*.rdb.gz

# TimescaleDB VM
./restore/04-restore-timescaledb-vm.sh /backup/harness-migration-*/timescaledb-*/timescaledb-full-*.sql.gz
```

### Step 4: Validate Migration

```bash
# Set database hosts
export POSTGRES_HOST="postgres-vm-ip"
export MONGO_HOST="mongodb-vm-ip"
export MONGO_PASSWORD="your-password"
export REDIS_HOST="redis-vm-ip"
export TSDB_HOST="timescaledb-vm-ip"

# Run validation
./validate-migration.sh
```

---

## 📋 Prerequisites

### Kubernetes Environment (for backups)

- `kubectl` configured and connected to the cluster
- Access to the Harness namespace
- Required command-line tools:
  - `psql` (PostgreSQL client)
  - `mongodump` / `mongosh` (MongoDB tools)
  - `redis-cli` (Redis client)

### VM Environment (for restores)

**PostgreSQL VM:**
- PostgreSQL 14.20 installed
- `psql` client
- User with superuser privileges

**MongoDB VM:**
- MongoDB 6.0.1 installed
- `mongorestore` and `mongosh`
- Admin credentials

**Redis VM:**
- Redis 7.4.8 installed
- `redis-cli`
- Root/sudo access

**TimescaleDB VM:**
- PostgreSQL 13 installed
- TimescaleDB 2.9 extension installed
- `psql` client

---

## ⚙️ Configuration

### Environment Variables

All scripts support configuration via environment variables:

**Backup Scripts:**
```bash
export NAMESPACE="harness"           # Kubernetes namespace
export BACKUP_ROOT="/backup"         # Backup destination directory
```

**Restore Scripts:**
```bash
# PostgreSQL
export POSTGRES_USER="postgres"
export POSTGRES_HOST="localhost"
export POSTGRES_PORT="5432"

# MongoDB
export MONGO_USER="root"
export MONGO_PASSWORD="your-password"
export MONGO_HOST="localhost"
export MONGO_PORT="27017"

# Redis
export REDIS_DATA_DIR="/var/lib/redis"
export REDIS_USER="redis"
export REDIS_SERVICE="redis"

# TimescaleDB
export TSDB_USER="postgres"
export TSDB_HOST="localhost"
```

---

## 🔍 Features

### Backup Scripts

✅ **Automated Discovery**: Automatically finds database pods in your namespace  
✅ **Integrity Checks**: Generates SHA256 checksums for all backups  
✅ **Metadata Collection**: Saves database version, statistics, and configuration  
✅ **Compression**: Automatically compresses backups to save space  
✅ **Logging**: Detailed logs for troubleshooting  
✅ **Error Handling**: Fails gracefully with clear error messages

### Restore Scripts

✅ **Integrity Validation**: Verifies checksums before restore  
✅ **Safety Backups**: Creates backup of existing data before restore  
✅ **Connectivity Tests**: Validates database access before proceeding  
✅ **Interactive Confirmations**: Requires explicit confirmation for destructive operations  
✅ **Post-Restore Validation**: Verifies data after restore  
✅ **Detailed Reporting**: Shows statistics and next steps

---

## 📊 Backup Sizes (Approximate)

| Database | Typical Size | Backup Duration |
|----------|-------------|-----------------|
| PostgreSQL | 5-20 GB | 5-15 minutes |
| MongoDB | 10-50 GB | 10-30 minutes |
| Redis | 1-5 GB | 1-3 minutes |
| TimescaleDB | 50-500 GB | 30-120 minutes |

*Actual sizes and durations depend on your data volume and cluster performance.*

---

## 🛠️ Troubleshooting

### Common Issues

**1. "Pod not found" errors**
```bash
# Check if pods are running
kubectl get pods -n $NAMESPACE | grep -E 'postgres|mongo|redis|timescale'

# Check pod labels
kubectl get pods -n $NAMESPACE --show-labels
```

**2. "Permission denied" errors**
```bash
# For Kubernetes backups: Check RBAC permissions
kubectl auth can-i get pods -n $NAMESPACE

# For VM restores: Use sudo for Redis
sudo ./restore/03-restore-redis-vm.sh <backup-file>
```

**3. "Checksum verification failed"**
```bash
# Backup may be corrupted, re-run backup script
# Or skip checksum check (not recommended):
# Comment out the sha256sum check in the restore script
```

**4. "Cannot connect to database"**
```bash
# Check database is running
systemctl status postgresql  # or mongodb, redis

# Check firewall rules
telnet <vm-ip> 5432  # PostgreSQL
telnet <vm-ip> 27017 # MongoDB
telnet <vm-ip> 6379  # Redis
```

### Logs

- Backup logs: `<backup-dir>/backup.log`
- Restore logs: Check stdout/stderr
- Database logs:
  - PostgreSQL: `/var/log/postgresql/`
  - MongoDB: `/var/log/mongodb/`
  - Redis: `journalctl -u redis`

---

## 🔐 Security Best Practices

1. **Encrypt backups in transit**:
   ```bash
   # Use rsync over SSH
   rsync -avz -e "ssh -i ~/.ssh/id_rsa" /backup/ user@vm:/backup/
   ```

2. **Encrypt backups at rest**:
   ```bash
   # Encrypt with GPG
   gpg --encrypt --recipient your-key backup-file.sql.gz
   ```

3. **Rotate passwords**: Change default passwords after migration

4. **Secure backup storage**: Use restricted permissions:
   ```bash
   chmod 600 /backup/*.gz
   ```

5. **Clean up**: Remove old backups after successful migration

---

## 📝 Best Practices

### Before Migration

- [ ] Test restore on non-production VMs first
- [ ] Verify VM disk space (2x backup size recommended)
- [ ] Document current database configurations
- [ ] Schedule maintenance window
- [ ] Notify stakeholders

### During Migration

- [ ] Run backups during low-traffic periods
- [ ] Verify checksums before transferring
- [ ] Monitor backup progress (don't interrupt!)
- [ ] Keep application read-only during final backup

### After Migration

- [ ] Run validation scripts
- [ ] Perform application smoke tests
- [ ] Monitor database performance for 48 hours
- [ ] Keep K8s databases for 7-14 days as rollback
- [ ] Update DNS/connection strings gradually

---

## 🆘 Emergency Rollback

If migration fails:

```bash
# 1. Revert application connection strings to K8s databases
# 2. K8s databases should still be running

# 3. On VMs, restore safety backups created during restore:
psql -U postgres < /tmp/postgres-safety-backup-*.sql.gz
mongorestore --dir=/tmp/mongodb-safety-backup-*
sudo systemctl stop redis && sudo cp /tmp/redis-dump-safety-*.rdb /var/lib/redis/dump.rdb && sudo systemctl start redis
```

---

## 📚 Additional Resources

- [Main Migration Guide](../DATABASE_MIGRATION_GUIDE.md)
- [PostgreSQL Backup Documentation](https://www.postgresql.org/docs/14/backup.html)
- [MongoDB Backup Methods](https://www.mongodb.com/docs/manual/core/backups/)
- [Redis Persistence](https://redis.io/docs/management/persistence/)
- [TimescaleDB Migration](https://docs.timescale.com/self-hosted/latest/migration/)

---

## 💡 Tips

- **Parallel backups**: Run backup scripts simultaneously in different terminals to save time
- **Bandwidth optimization**: Compress backups before transfer to save time
- **Testing**: Always test on non-production first
- **Monitoring**: Set up database monitoring before cutover
- **Documentation**: Keep notes of any customizations or issues encountered

---

## 🤝 Support

If you encounter issues:

1. Check the troubleshooting section above
2. Review log files for detailed error messages
3. Verify prerequisites are met
4. Test network connectivity between VMs

---

**Last Updated**: 2026-05-05  
**Version**: 1.0
