# Backup Examples

## Quick Start

### MongoDB Backup

```bash
# Syntax check first
ansible-playbook -i inventory/production/hosts db-backup/playbooks/backup_mongodb.yml --syntax-check

# Run backup (requires s3://my-backups-prod bucket)
ansible-playbook -i inventory/production/hosts db-backup/playbooks/backup_mongodb.yml \
  -e "mongodb_backup_s3_bucket=my-backups-prod" \
  -e "mongodb_backup_s3_prefix=mongodb-daily"

# Output on S3:
# s3://my-backups-prod/mongodb-daily/mongodb-backup-20260722T123456.tar.gz
# s3://my-backups-prod/mongodb-daily/mongodb-backup-20260722T123456.tar.gz.sha256
```

### Redis Backup

```bash
# Run backup
ansible-playbook -i inventory/production/hosts db-backup/playbooks/backup_redis.yml \
  -e "redis_backup_s3_bucket=my-backups-prod" \
  -e "redis_backup_s3_prefix=redis-daily"

# Output on S3:
# s3://my-backups-prod/redis-daily/redis-dump-20260722T123456.rdb.gz
# s3://my-backups-prod/redis-daily/redis-dump-20260722T123456.rdb.gz.sha256
```

### PostgreSQL Backup

```bash
# First, ensure postgres_cluster & postgres_replicas groups exist in inventory
# Then run:
ansible-playbook -i inventory/production/hosts db-backup/playbooks/backup_postgres.yml \
  -e "postgres_backup_s3_bucket=my-backups-prod" \
  -e "postgres_backup_s3_prefix=postgres-daily"

# Output on S3:
# s3://my-backups-prod/postgres-daily/postgres-full-20260722T123456.sql.gz
# s3://my-backups-prod/postgres-daily/postgres-full-20260722T123456.sql.gz.sha256
```

## Via group_vars (Recommended for Production)

Create persistent configuration in your inventory:

```bash
# MongoDB
cat > inventory/production/group_vars/mongodb_cluster.yml <<EOF
mongodb_backup_s3_bucket: my-backups-prod
mongodb_backup_s3_prefix: mongodb-daily
EOF

# Redis
cat > inventory/production/group_vars/redis_cluster.yml <<EOF
redis_backup_s3_bucket: my-backups-prod
redis_backup_s3_prefix: redis-daily
EOF

# PostgreSQL
cat > inventory/production/group_vars/postgres_cluster.yml <<EOF
postgres_backup_s3_bucket: my-backups-prod
postgres_backup_s3_prefix: postgres-daily
postgres_cluster_size: 3
EOF
```

Then run without `-e` flags:

```bash
ansible-playbook -i inventory/production/hosts db-backup/playbooks/backup_mongodb.yml
ansible-playbook -i inventory/production/hosts db-backup/playbooks/backup_redis.yml
ansible-playbook -i inventory/production/hosts db-backup/playbooks/backup_postgres.yml
```

## Daily Backup Schedule (Cron)

```bash
#!/bin/bash
# /usr/local/bin/run-db-backups.sh

ANSIBLE_DIR="/path/to/emirates-ansible"
LOG_DIR="/var/log/db-backups"
mkdir -p "$LOG_DIR"

cd "$ANSIBLE_DIR"

echo "=== Starting MongoDB backup ===" >> "$LOG_DIR/backups.log"
ansible-playbook -i inventory/production/hosts db-backup/playbooks/backup_mongodb.yml >> "$LOG_DIR/mongodb.log" 2>&1

echo "=== Starting Redis backup ===" >> "$LOG_DIR/backups.log"
ansible-playbook -i inventory/production/hosts db-backup/playbooks/backup_redis.yml >> "$LOG_DIR/redis.log" 2>&1

echo "=== Starting PostgreSQL backup ===" >> "$LOG_DIR/backups.log"
ansible-playbook -i inventory/production/hosts db-backup/playbooks/backup_postgres.yml >> "$LOG_DIR/postgres.log" 2>&1

echo "=== Backups completed ===" >> "$LOG_DIR/backups.log"
```

Add to crontab:

```bash
# crontab -e
0 2 * * * /usr/local/bin/run-db-backups.sh
```

## Verify Backups in S3

```bash
# List all MongoDB backups
aws s3 ls s3://my-backups-prod/mongodb-daily/ --recursive

# List latest Redis backup
aws s3 ls s3://my-backups-prod/redis-daily/ --recursive | tail -1

# Download and verify checksum
aws s3 cp s3://my-backups-prod/mongodb-daily/mongodb-backup-20260722T123456.tar.gz.sha256 .
aws s3 cp s3://my-backups-prod/mongodb-daily/mongodb-backup-20260722T123456.tar.gz .
sha256sum -c mongodb-backup-20260722T123456.tar.gz.sha256
```

## Multi-Database Backup (All at Once)

Run all three backups in sequence:

```bash
# Create wrapper playbook
cat > db-backup/playbooks/backup_all.yml <<EOF
---
- import_playbook: backup_mongodb.yml
- import_playbook: backup_redis.yml
- import_playbook: backup_postgres.yml
EOF

# Run all backups
ansible-playbook -i inventory/production/hosts db-backup/playbooks/backup_all.yml
```

## Staging vs Production

Use different S3 prefixes or buckets for staging:

```bash
# Staging backup to test bucket
ansible-playbook -i inventory/staging/hosts db-backup/playbooks/backup_mongodb.yml \
  -e "mongodb_backup_s3_bucket=my-backups-staging" \
  -e "mongodb_backup_s3_prefix=mongodb-test"

# Production backup to prod bucket
ansible-playbook -i inventory/production/hosts db-backup/playbooks/backup_mongodb.yml \
  -e "mongodb_backup_s3_bucket=my-backups-prod" \
  -e "mongodb_backup_s3_prefix=mongodb-daily"
```

## Troubleshooting

### Check which secondary/replica will be used

```bash
# MongoDB
ansible-inventory -i inventory/production/hosts --host mongo2.prod.local

# Redis
ansible-inventory -i inventory/production/hosts --host redis2.prod.local

# Postgres (if groups exist)
ansible-inventory -i inventory/production/hosts --group postgres_replicas
```

### Dry run without S3 upload

Modify the playbook temporarily to skip S3 upload:

```bash
ansible-playbook -i inventory/production/hosts db-backup/playbooks/backup_mongodb.yml \
  -e "mongodb_backup_s3_bucket=test" \
  --skip-tags "upload"
```

### Monitor long-running backups

```bash
# SSH to the target node and monitor
ssh ubuntu@<secondary-host>

# Watch mongodump progress
ps aux | grep mongodump

# Monitor disk space
df -h /tmp

# Monitor S3 upload
tail -f /var/log/syslog | grep "aws s3 cp"
```
