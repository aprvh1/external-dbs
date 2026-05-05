# Database Clusters - Complete Summary

This Ansible project now supports three database systems with high availability for air-gapped environments.

## Overview

| Database | 3-Node HA | 1-Node | Restore | Upgrade | Status |
|----------|-----------|---------|---------|---------|--------|
| **MongoDB** | ✅ Replica Set | ✅ | ✅ mongodump | ✅ Rolling | **Implemented** |
| **Redis** | ✅ Sentinel | ✅ | ✅ RDB | ⏳ Planned | **Implemented** |
| **PostgreSQL** | ✅ Patroni+etcd | ✅ | ✅ pg_basebackup | ✅ pg_upgrade | **Planned** |

## Architecture Comparison

### MongoDB (Implemented)
```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   mongo1.prod   │────▶│   mongo2.prod   │────▶│   mongo3.prod   │
│                 │     │                 │     │                 │
│    PRIMARY      │     │   SECONDARY     │     │   SECONDARY     │
└─────────────────┘     └─────────────────┘     └─────────────────┘
     Built-in HA              Replica Set                Auto-failover
```

**Services per node:** 1 (mongod)  
**HA Method:** Replica set with voting  
**Restore:** mongodump/mongorestore  
**Complexity:** Medium  

### Redis (Implemented)
```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   redis1.prod   │────▶│   redis2.prod   │     │   redis3.prod   │
│                 │     │                 │     │                 │
│  Master         │     │  Replica        │◀────│  Replica        │
│  Sentinel       │     │  Sentinel       │     │  Sentinel       │
└─────────────────┘     └─────────────────┘     └─────────────────┘
     │                       │                       │
     └───────────────────────┴───────────────────────┘
                    Sentinel Quorum = 2
```

**Services per node:** 2 (redis, sentinel)  
**HA Method:** Sentinel-based failover  
**Restore:** RDB file copy  
**Complexity:** Low-Medium  

### PostgreSQL (Planned)
```
┌─────────────────────────────────────────┐
│              pg1.prod                   │
│  ┌──────────┐  ┌─────────┐  ┌───────┐ │
│  │PostgreSQL│◄─┤ Patroni │◄─┤ etcd  │ │
│  │  Leader  │  └─────────┘  └───────┘ │
└─────────────────────────────────────────┘
           │                    ▲
           │ Replication        │ DCS
           ▼                    │
┌─────────────────────────────────────────┐
│              pg2.prod                   │
│  ┌──────────┐  ┌─────────┐  ┌───────┐ │
│  │PostgreSQL│◄─┤ Patroni │◄─┤ etcd  │ │
│  │ Replica  │  └─────────┘  └───────┘ │
└─────────────────────────────────────────┘
           │                    ▲
           ▼                    │
┌─────────────────────────────────────────┐
│              pg3.prod                   │
│  ┌──────────┐  ┌─────────┐  ┌───────┐ │
│  │PostgreSQL│◄─┤ Patroni │◄─┤ etcd  │ │
│  │ Replica  │  └─────────┘  └───────┘ │
└─────────────────────────────────────────┘
```

**Services per node:** 3 (postgres, patroni, etcd)  
**HA Method:** Patroni + etcd consensus  
**Restore:** pg_basebackup/pg_dump  
**Complexity:** High  

## Quick Reference

### Deployment Commands

**MongoDB:**
```bash
ansible-playbook -i inventory/production/hosts playbooks/deploy_fresh.yml
ansible-playbook -i inventory/production/hosts playbooks/verify.yml
```

**Redis:**
```bash
ansible-playbook -i inventory/production/hosts playbooks/deploy_redis.yml
ansible-playbook -i inventory/production/hosts playbooks/verify_redis.yml
```

**PostgreSQL:**
```bash
ansible-playbook -i inventory/production/hosts playbooks/deploy_postgres.yml
ansible-playbook -i inventory/production/hosts playbooks/verify_postgres.yml
```

### Restore Commands

**MongoDB:**
```bash
ansible-playbook -i inventory/production/hosts playbooks/deploy_restore.yml \
  -e "mongodb_restore_backup_path=/backups/mongodump"
```

**Redis:**
```bash
ansible-playbook -i inventory/production/hosts playbooks/deploy_redis_restore.yml \
  -e "redis_restore_rdb_path=/backups/dump.rdb"
```

**PostgreSQL:**
```bash
ansible-playbook -i inventory/production/hosts playbooks/deploy_postgres_restore.yml \
  -e "postgres_restore_backup_path=/backups/pg_basebackup"
```

### Connection Strings

**MongoDB:**
```
mongodb://admin:testp@ssw0rd123@mongo1.prod.local:27017/admin
```

**Redis:**
```
redis://redis_secure_pass123@redis1.prod.local:6379
```

**PostgreSQL:**
```
postgresql://postgres:postgres_secure_pass@pg1.prod.local:5432/postgres
```

### Health Check Commands

**MongoDB:**
```bash
mongosh --username admin --password testp@ssw0rd123 --authenticationDatabase admin
rs.status()
```

**Redis:**
```bash
redis-cli -a redis_secure_pass123 INFO replication
redis-cli -p 26379 SENTINEL master mymaster  # Sentinel check
```

**PostgreSQL:**
```bash
patronictl -c /etc/patroni/patroni.yml list
psql -U postgres -c "SELECT * FROM pg_stat_replication;"
```

## Inventory Structure

All three can coexist in the same inventory file:

```ini
# inventory/production/hosts

# MongoDB Cluster
[mongodb_cluster]
mongo1.prod.local ansible_host=10.0.1.10 mongodb_role=primary mongodb_dns_name=mongo1.prod.local
mongo2.prod.local ansible_host=10.0.1.11 mongodb_role=secondary mongodb_dns_name=mongo2.prod.local
mongo3.prod.local ansible_host=10.0.1.12 mongodb_role=secondary mongodb_dns_name=mongo3.prod.local

[mongodb_primary]
mongo1.prod.local

[mongodb_secondary]
mongo2.prod.local
mongo3.prod.local

# Redis Cluster
[redis_cluster]
redis1.prod.local ansible_host=10.0.1.20 redis_role=master redis_dns_name=redis1.prod.local
redis2.prod.local ansible_host=10.0.1.21 redis_role=replica redis_dns_name=redis2.prod.local
redis3.prod.local ansible_host=10.0.1.22 redis_role=replica redis_dns_name=redis3.prod.local

[redis_master]
redis1.prod.local

[redis_replicas]
redis2.prod.local
redis3.prod.local

# PostgreSQL Cluster
[postgres_cluster]
pg1.prod.local ansible_host=10.0.1.30 postgres_role=leader postgres_dns_name=pg1.prod.local
pg2.prod.local ansible_host=10.0.1.31 postgres_role=replica postgres_dns_name=pg2.prod.local
pg3.prod.local ansible_host=10.0.1.32 postgres_role=replica postgres_dns_name=pg3.prod.local

[postgres_leader]
pg1.prod.local

[postgres_replicas]
pg2.prod.local
pg3.prod.local

# Global variables
[all:vars]
ansible_user=ubuntu
ansible_become=yes
```

## Port Reference

| Database | Service | Port | Notes |
|----------|---------|------|-------|
| MongoDB | mongod | 27017 | Main database port |
| Redis | redis-server | 6379 | Main database port |
| Redis | redis-sentinel | 26379 | Sentinel monitoring |
| PostgreSQL | postgres | 5432 | Main database port |
| PostgreSQL | patroni REST API | 8008 | Cluster management |
| PostgreSQL | etcd client | 2379 | DCS communication |
| PostgreSQL | etcd peer | 2380 | etcd cluster sync |

## Default Credentials (Change in Production!)

| Database | User | Password | Location |
|----------|------|----------|----------|
| MongoDB | admin | testp@ssw0rd123 | roles/mongodb/defaults/main.yml |
| Redis | - | redis_secure_pass123 | roles/redis/defaults/main.yml |
| PostgreSQL | postgres | postgres_secure_pass | roles/postgres/defaults/main.yml |

## Files Required for Air-Gap

### MongoDB
```
roles/mongodb/files/mongodb-binaries/
└── mongodb-linux-x86_64-ubuntu2004-7.0.15.tgz
```

### Redis
```
roles/redis/files/redis-binaries/
└── redis-7.2.4.tar.gz
```

### PostgreSQL
```
roles/postgres/files/
├── postgres-binaries/
│   └── postgresql-14.11.tar.gz
├── etcd-binaries/
│   └── etcd-v3.5.12-linux-amd64.tar.gz
└── patroni-packages/
    ├── patroni-*.whl
    ├── python-etcd3-*.whl
    └── (other dependencies)
```

## Documentation Reference

| Database | Quick Start | Full Guide | Plan |
|----------|-------------|------------|------|
| MongoDB | QUICKSTART.md | README.md | completed plan |
| Redis | REDIS_QUICKSTART.md | REDIS_README.md | completed plan |
| PostgreSQL | (in implementation guide) | POSTGRES_IMPLEMENTATION_GUIDE.md | planned |

## Failover Behavior

### MongoDB
- Automatic via replica set voting
- Requires majority (2/3 nodes)
- ~10-30 seconds downtime
- Clients reconnect automatically

### Redis
- Automatic via Sentinel
- Requires quorum (2/3 Sentinels)
- ~10-30 seconds downtime
- Clients need Sentinel-aware drivers

### PostgreSQL
- Automatic via Patroni
- Requires etcd quorum (2/3 nodes)
- ~10-30 seconds downtime
- Connection pooler (pgbouncer) recommended

## Backup Strategy

### MongoDB
```bash
# Manual backup
mongodump --uri="mongodb://admin:pass@mongo1.prod.local:27017" --out=/backups/mongodump-$(date +%Y%m%d)

# Restore
ansible-playbook -i inventory/production/hosts playbooks/deploy_restore.yml \
  -e "mongodb_restore_backup_path=/backups/mongodump-20240420"
```

### Redis
```bash
# Manual backup (copy RDB file)
scp redis1.prod.local:/var/lib/redis/dump.rdb /backups/redis-$(date +%Y%m%d).rdb

# Restore
ansible-playbook -i inventory/production/hosts playbooks/deploy_redis_restore.yml \
  -e "redis_restore_rdb_path=/backups/redis-20240420.rdb"
```

### PostgreSQL
```bash
# Manual backup
pg_basebackup -h pg1.prod.local -U replicator -D /backups/pg_basebackup-$(date +%Y%m%d) -Fp -Xs -P

# Restore
ansible-playbook -i inventory/production/hosts playbooks/deploy_postgres_restore.yml \
  -e "postgres_restore_backup_path=/backups/pg_basebackup-20240420"
```

## Monitoring Integration

All three databases support Prometheus exporters:

- **MongoDB**: mongodb_exporter
- **Redis**: redis_exporter
- **PostgreSQL**: postgres_exporter

Integration can be added to roles in future iterations.

## Common Operations

### Scale from 1-node to 3-node

1. Update inventory (add 2 more nodes)
2. Change `cluster_size: 3` in group_vars
3. Re-run deployment playbook
4. For MongoDB: Add nodes to replica set
5. For Redis: Configure replication and Sentinel
6. For PostgreSQL: Let Patroni handle it automatically

### Rolling Restart

**MongoDB:**
```bash
# Restart secondaries first, then primary
ansible postgres_replicas -i inventory/production/hosts -m systemd -a "name=mongod state=restarted"
# Then restart primary
```

**Redis:**
```bash
# Redis handles this via Sentinel
# Just restart services normally
```

**PostgreSQL:**
```bash
# Use Patroni for controlled restart
patronictl -c /etc/patroni/patroni.yml restart postgres-cluster --role replica
patronictl -c /etc/patroni/patroni.yml restart postgres-cluster pg1
```

## Troubleshooting Quick Reference

### DNS Issues
All three databases require DNS resolution:
```bash
# Check resolution on all nodes
ansible all -i inventory/production/hosts -m command -a "getent hosts mongo1.prod.local"
ansible all -i inventory/production/hosts -m command -a "getent hosts redis1.prod.local"
ansible all -i inventory/production/hosts -m command -a "getent hosts pg1.prod.local"

# Fix: Add to /etc/hosts if DNS not available
```

### Firewall Issues
```bash
# Open all database ports
sudo ufw allow from 10.0.1.0/24 to any port 27017  # MongoDB
sudo ufw allow from 10.0.1.0/24 to any port 6379   # Redis
sudo ufw allow from 10.0.1.0/24 to any port 26379  # Sentinel
sudo ufw allow from 10.0.1.0/24 to any port 5432   # PostgreSQL
sudo ufw allow from 10.0.1.0/24 to any port 8008   # Patroni API
sudo ufw allow from 10.0.1.0/24 to any port 2379   # etcd client
sudo ufw allow from 10.0.1.0/24 to any port 2380   # etcd peer
```

### Service Status
```bash
# MongoDB
systemctl status mongod

# Redis
systemctl status redis redis-sentinel

# PostgreSQL
systemctl status etcd patroni
```

## Implementation Status

✅ **MongoDB** - Fully implemented and documented  
✅ **Redis + Sentinel** - Fully implemented and documented  
⏳ **PostgreSQL + Patroni + etcd** - Planned (implementation guide created)

## Next Steps

1. **PostgreSQL Implementation**: Follow POSTGRES_IMPLEMENTATION_GUIDE.md to complete the PostgreSQL role

2. **Testing**: Test each database cluster in staging before production:
   - Fresh deployment
   - Restore from backup
   - Failover scenarios
   - Upgrade procedures

3. **Monitoring**: Integrate Prometheus exporters for all three databases

4. **Backup Automation**: Create cron jobs for scheduled backups

5. **Security Hardening**:
   - Change default passwords
   - Enable TLS/SSL
   - Configure firewalls
   - Implement backup encryption

6. **Documentation**: Create operational runbooks for each database

---

**Project Structure:**
```
emirates-ansible/
├── MongoDB (Implemented) ✅
├── Redis + Sentinel (Implemented) ✅
└── PostgreSQL + Patroni + etcd (Planned) ⏳
```

All three database clusters follow consistent patterns:
- Air-gapped deployment
- DNS-based configuration
- 1-node and 3-node support
- Restore from backups
- High availability
- Idempotent playbooks
