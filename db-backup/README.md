# Database Backup to S3

Ansible playbooks to backup MongoDB, Redis, and PostgreSQL deployments to AWS S3. Backups run on replica/secondary nodes to avoid performance impact on primary instances.

## Overview

```
db-backup/
├── playbooks/
│   ├── backup_mongodb.yml      # Backup from MongoDB secondary
│   ├── backup_redis.yml        # Backup from Redis replica
│   └── backup_postgres.yml     # Backup from PostgreSQL standby
└── roles/
    ├── mongodb_backup/
    ├── redis_backup/
    └── postgres_backup/
```

## Prerequisites

1. **Ansible inventory** with appropriate groups:
   - MongoDB: `mongodb_cluster`, `mongodb_secondary` groups
   - Redis: `redis_cluster`, `redis_replicas` groups
   - PostgreSQL: `postgres_cluster`, `postgres_replicas` groups (see section below)

2. **AWS credentials** configured on target VMs:
   - IAM instance role attached to EC2 instances, OR
   - AWS credentials in `~/.aws/credentials` or environment variables

3. **AWS CLI** installed on target VMs:
   ```bash
   apt-get install -y awscli
   ```

4. **Database CLI tools** installed:
   - MongoDB: `mongodump` (installed by `roles/mongodb`)
   - Redis: `redis-cli` (installed by `roles/redis`)
   - PostgreSQL: `pg_basebackup` (installed by `roles/postgres`)

## Inventory Setup

### MongoDB & Redis

These groups already exist in `inventory/production/hosts` and `inventory/staging/hosts`:

```ini
[mongodb_cluster]
mongo1.prod.local ansible_host=10.0.1.10 mongodb_role=primary
mongo2.prod.local ansible_host=10.0.1.11 mongodb_role=secondary
mongo3.prod.local ansible_host=10.0.1.12 mongodb_role=secondary

[mongodb_secondary]
mongo2.prod.local
mongo3.prod.local

[redis_cluster]
redis1.prod.local ansible_host=10.0.1.20 redis_role=master
redis2.prod.local ansible_host=10.0.1.21 redis_role=replica
redis3.prod.local ansible_host=10.0.1.22 redis_role=replica

[redis_replicas]
redis2.prod.local
redis3.prod.local
```

### PostgreSQL (REQUIRED SETUP)

PostgreSQL groups do **not** exist yet and must be added to your inventory. Example:

```ini
[postgres_cluster]
pg1.prod.local ansible_host=10.0.1.30 postgres_role=leader
pg2.prod.local ansible_host=10.0.1.31 postgres_role=replica
pg3.prod.local ansible_host=10.0.1.32 postgres_role=replica

[postgres_replicas]
pg2.prod.local
pg3.prod.local
```

**Template:** See `inventory/examples/hosts_postgres_3node.example` (if it exists), or adapt from the MongoDB example above.

Add these groups to both:
- `inventory/production/hosts`
- `inventory/staging/hosts`

Also create group_vars files for PostgreSQL (optional but recommended):

```bash
mkdir -p inventory/production/group_vars
cat > inventory/production/group_vars/postgres_cluster.yml <<EOF
---
postgres_cluster_size: 3
EOF
```

## Usage

### MongoDB Backup

Backup the secondary node to S3:

```bash
# Dry run (syntax check)
ansible-playbook -i inventory/production/hosts db-backup/playbooks/backup_mongodb.yml --syntax-check

# Actual backup with custom S3 bucket
ansible-playbook -i inventory/production/hosts db-backup/playbooks/backup_mongodb.yml \
  -e "mongodb_backup_s3_bucket=my-backups-prod" \
  -e "mongodb_backup_s3_prefix=mongodb-daily"
```

### Redis Backup

Backup the replica node to S3:

```bash
# Actual backup
ansible-playbook -i inventory/production/hosts db-backup/playbooks/backup_redis.yml \
  -e "redis_backup_s3_bucket=my-backups-prod" \
  -e "redis_backup_s3_prefix=redis-daily"
```

### PostgreSQL Backup

Backup from standby node to S3:

```bash
# Requires postgres_cluster groups in inventory
ansible-playbook -i inventory/production/hosts db-backup/playbooks/backup_postgres.yml \
  -e "postgres_backup_s3_bucket=my-backups-prod" \
  -e "postgres_backup_s3_prefix=postgres-daily"
```

## Configuration

### Role Variables

#### mongodb_backup
- `mongodb_backup_s3_bucket` (required): S3 bucket name
- `mongodb_backup_s3_prefix` (default: `mongodb-backups`): S3 path prefix
- `mongodb_backup_local_tmp_dir` (default: `/tmp`): Local temp directory for backup staging

Connection vars inherited from `roles/mongodb/defaults/main.yml`:
- `mongodb_admin_user`
- `mongodb_admin_password`
- `mongodb_bin_dir`
- `mongodb_port`

#### redis_backup
- `redis_backup_s3_bucket` (required): S3 bucket name
- `redis_backup_s3_prefix` (default: `redis-backups`): S3 path prefix
- `redis_backup_bgsave_timeout` (default: `300`): Max seconds to wait for BGSAVE to complete
- `redis_backup_local_tmp_dir` (default: `/tmp`): Local temp directory

Connection vars inherited from `roles/redis/defaults/main.yml`:
- `redis_bin_dir`
- `redis_data_dir`
- `redis_dbfilename`
- `redis_port`
- `redis_requirepass`

#### postgres_backup
- `postgres_backup_s3_bucket` (required): S3 bucket name
- `postgres_backup_s3_prefix` (default: `postgres-backups`): S3 path prefix
- `postgres_backup_local_tmp_dir` (default: `/tmp`): Local temp directory

Connection vars inherited from `roles/postgres/defaults/main.yml`:
- `postgres_bin_dir`
- `postgres_port`
- `postgres_replication_user`
- `postgres_replication_password`

### Via group_vars

Set backup variables in your inventory group_vars for persistence:

```bash
cat > inventory/production/group_vars/mongodb_cluster.yml <<EOF
---
mongodb_backup_s3_bucket: my-backups-prod
mongodb_backup_s3_prefix: mongodb-daily
EOF
```

Then backups use these defaults without `-e` flags.

## Backup Output

### MongoDB
- `s3://bucket/prefix/mongodb-backup-<timestamp>.tar.gz` — mongodump archive
- `s3://bucket/prefix/mongodb-backup-<timestamp>.tar.gz.sha256` — checksum

### Redis
- `s3://bucket/prefix/redis-dump-<timestamp>.rdb.gz` — compressed RDB file
- `s3://bucket/prefix/redis-dump-<timestamp>.rdb.gz.sha256` — checksum

### PostgreSQL
- `s3://bucket/prefix/postgres-basebackup-<timestamp>.tar.gz` — pg_basebackup physical snapshot
- `s3://bucket/prefix/postgres-basebackup-<timestamp>.tar.gz.sha256` — checksum

## Verification

### Dry Run (Syntax Check)
```bash
ansible-playbook db-backup/playbooks/backup_mongodb.yml --syntax-check
ansible-playbook db-backup/playbooks/backup_redis.yml --syntax-check
ansible-playbook db-backup/playbooks/backup_postgres.yml --syntax-check
```

### Verify Backup in S3
```bash
# List all backups
aws s3 ls s3://my-backups-prod/mongodb-backups/
aws s3 ls s3://my-backups-prod/redis-backups/
aws s3 ls s3://my-backups-prod/postgres-backups/

# Verify checksum
aws s3 cp s3://my-backups-prod/mongodb-backups/mongodb-backup-<timestamp>.tar.gz.sha256 .
sha256sum -c mongodb-backup-<timestamp>.tar.gz.sha256
```

## Scheduling with Cron

Example cron job to backup daily at 2 AM:

```bash
# Add to crontab (crontab -e)
0 2 * * * cd /path/to/emirates-ansible && ansible-playbook -i inventory/production/hosts db-backup/playbooks/backup_mongodb.yml -e "mongodb_backup_s3_bucket=my-backups-prod" >> /var/log/mongodb-backup.log 2>&1
```

## Performance Notes

- **Replication Lag**: Backups run on replica/secondary nodes to avoid primary load. Acceptable lag depends on your RTO/RPO requirements.
- **Disk Space**: Ensure `/tmp` has enough free space for the full data directory copy during PostgreSQL backups (pg_basebackup can be large).
- **Network**: S3 upload speed depends on instance network bandwidth. Monitor `aws s3 cp` output.
- **Database Load**: mongodump, pg_basebackup, and BGSAVE impact replica performance. Run during maintenance windows if needed.

## Troubleshooting

### "aws: command not found"
```bash
# On target VM, install AWS CLI
sudo apt-get install -y awscli
```

### "Permission denied" accessing S3
```bash
# Verify IAM role is attached to instance
aws sts get-caller-identity

# Or configure credentials
aws configure
```

### "mongodump connection refused"
```bash
# Verify MongoDB is running and authentication is correct
mongo --host localhost --port 27017 -u admin -p testp@ssw0rd123 --authenticationDatabase admin --eval "db.adminCommand('ping')"
```

### BGSAVE timeout
Increase `redis_backup_bgsave_timeout`:
```bash
ansible-playbook db-backup/playbooks/backup_redis.yml \
  -e "redis_backup_s3_bucket=..." \
  -e "redis_backup_bgsave_timeout=600"
```

### "Checksum verification failed"
Backups include `.sha256` files for verification. Verify locally:
```bash
aws s3 cp s3://bucket/prefix/backup.tar.gz.sha256 .
aws s3 cp s3://bucket/prefix/backup.tar.gz .
sha256sum -c backup.tar.gz.sha256
```

## Architecture

Each playbook targets a replica/secondary to distribute backup load:

```
MongoDB Primary          Redis Master              PostgreSQL Leader
      ↓                       ↓                           ↓
   (no load)             (no load)                   (no load)
      ↑                       ↑                           ↑
      │                       │                           │
  Secondary                Replica 1                  Standby/Replica
      ↓                       ↓                           ↓
  mongodump              BGSAVE + RDB cp            pg_basebackup
      ↓                       ↓                           ↓
  tar + gzip            gzip RDB                   tar + gzip
      ↓                       ↓                           ↓
  aws s3 cp             aws s3 cp                   aws s3 cp
      ↓                       ↓                           ↓
    S3 Bucket              S3 Bucket                  S3 Bucket
```

## Notes

- **Format Consistency**: Backup formats are chosen to match existing restore roles:
  - **MongoDB**: mongodump (logical) — matches `roles/mongodb/tasks/restore.yml` via `mongorestore`
  - **Redis**: RDB binary (physical snapshot) — matches `roles/redis/tasks/restore.yml` 
  - **PostgreSQL**: pg_basebackup (physical snapshot) — matches `roles/postgres/tasks/restore.yml` via `synchronize` and `postgres_restore_type: basebackup`
  - All backed-up archives are tarred for S3 transport; extract before passing to restore roles.
- All backups include SHA256 checksums for integrity verification.
- Local temporary files are cleaned up after upload to S3.
- No backup encryption is applied by these playbooks; configure S3 encryption separately if required.
- PostgreSQL backups use the `postgres_replication_user` role (which has REPLICATION privileges per pg_hba.conf) instead of the superuser, matching the authentication protocol required by pg_basebackup.

## Related Files

- [roles/mongodb/tasks/restore.yml](../roles/mongodb/tasks/restore.yml) — MongoDB restore logic
- [roles/redis/tasks/restore.yml](../roles/redis/tasks/restore.yml) — Redis restore logic
- [roles/postgres/tasks/restore.yml](../roles/postgres/tasks/restore.yml) — PostgreSQL restore logic
- [inclusterdb-migration-scripts/](../inclusterdb-migration-scripts/) — K8s backup scripts (reference)
