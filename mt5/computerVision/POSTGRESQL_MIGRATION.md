# PostgreSQL Migration Guide

## Overview

This guide explains how to migrate from SQLite to PostgreSQL for the CV Trading Agent. PostgreSQL solves the "disk I/O error" issues caused by SQLite on Docker volume mounts in Windows.

## Why PostgreSQL?

- ✅ **Solves Windows Docker I/O issues** - Data stays in Linux container, not Windows volume
- ✅ **Better concurrency** - Multiple services (dashboard, trader, bridge) can access simultaneously
- ✅ **Better performance** - Optimized for high-frequency inserts (market data)
- ✅ **Native JSON support** - JSONB type for hyperparameters, details fields
- ✅ **Production-ready** - Battle-tested for trading systems

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Docker Network                        │
│                                                          │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────┐ │
│  │  Dashboard   │───→│  PostgreSQL  │←───│  Trader  │ │
│  │  (Container) │    │  (Container) │    │(Container)│ │
│  └──────────────┘    └──────────────┘    └──────────┘ │
│                             ↑                            │
└─────────────────────────────┼────────────────────────────┘
                              │
                              │ localhost:5432
                              │
                    ┌─────────┴─────────┐
                    │   MT5 Bridge      │
                    │ (Windows Host)    │
                    └───────────────────┘
```

## Prerequisites

- Docker and Docker Compose installed
- Existing SQLite database (optional - for migration)
- Python 3.11+ with psycopg2-binary

## Step 1: Review Configuration

The migration is already configured! Review these files:

### `.env` (Project Root)
```env
DATABASE_TYPE=postgresql
DATABASE_URL=postgresql://cv_agent:cv_trading_2024@postgres:5432/cv_trading
POSTGRES_PASSWORD=cv_trading_2024
```

**⚠️ IMPORTANT:** Change `cv_trading_2024` to a secure password before deployment!

### `bridge/.env` (Bridge Service)
```env
DATABASE_TYPE=postgresql
DATABASE_URL=postgresql://cv_agent:cv_trading_2024@localhost:5432/cv_trading
```

Note: Bridge connects to `localhost:5432` because it runs on Windows host.

## Step 2: Backup Existing Data

**CRITICAL:** Always backup before migration!

```bash
# Backup SQLite database
cp data/cv_agent.db data/cv_agent.db.backup.$(date +%Y%m%d_%H%M%S)

# Verify backup
ls -lh data/cv_agent.db.backup.*
```

## Step 3: Start PostgreSQL Service

```bash
# Stop existing services
docker-compose down

# Build with new dependencies
docker-compose build

# Start PostgreSQL only (to prepare for migration)
docker-compose up -d postgres

# Wait for PostgreSQL to be ready (check logs)
docker-compose logs -f postgres
# Look for: "database system is ready to accept connections"
```

## Step 4: Migrate Data from SQLite (Optional)

If you have existing data in SQLite:

```bash
# Install dependencies (if not already installed)
pip install psycopg2-binary python-dotenv

# Run migration script
python scripts/migrate_sqlite_to_postgres.py \
  --sqlite data/cv_agent.db \
  --postgres "postgresql://cv_agent:cv_trading_2024@localhost:5432/cv_trading"
```

**Expected Output:**
```
🔄 Starting migration from SQLite to PostgreSQL
  Source: data/cv_agent.db
  Target: localhost:5432/cv_trading

  ✓ Migrated 5432 rows from 'market_data'
  ✓ Migrated 12 rows from 'models'
  ✓ Migrated 8 rows from 'predictions'
  ...

📊 Migration Summary:
  Total rows migrated: 6789

🔍 Verifying data integrity...
  ✓ market_data: 5432 rows
  ✓ models: 12 rows
  ✓ predictions: 8 rows
  ...

✅ Migration completed successfully! All tables verified.
```

## Step 5: Start All Services

```bash
# Start dashboard and trader (both depend on postgres)
docker-compose up -d

# Monitor logs for any errors
docker-compose logs -f
```

**What to look for in logs:**

Dashboard:
```
[OK] PostgreSQL connection pool initialized
Database type: postgresql
```

Trader:
```
[OK] PostgreSQL connection pool initialized
Database type: postgresql
```

## Step 6: Update and Restart Bridge

The bridge runs on Windows host, so it needs manual restart:

1. **Install dependencies:**
   ```bash
   # In bridge directory or main project with requirements.txt
   pip install psycopg2-binary python-dotenv
   ```

2. **Verify bridge/.env configuration:**
   ```bash
   cat bridge/.env
   # Should show:
   # DATABASE_TYPE=postgresql
   # DATABASE_URL=postgresql://cv_agent:cv_trading_2024@localhost:5432/cv_trading
   ```

3. **Restart the bridge:**
   ```bash
   # Stop the running bridge (if any)
   # Then start it again
   python bridge/mt5_bridge.py
   ```

4. **Check bridge logs:**
   ```
   Loaded environment variables from bridge/.env
   Database type: postgresql
   PostgreSQL connection: localhost:5432/cv_trading
   MT5 connected successfully
   Starting MT5 Bridge API on 0.0.0.0:5000
   ```

## Step 7: Verify Everything Works

### 1. Check Docker Services
```bash
docker-compose ps
# All services should be "Up" and "healthy"
```

### 2. Access Dashboard
Open browser: http://localhost:8501

Check for:
- ✅ No "disk I/O error" messages
- ✅ Dashboard loads successfully
- ✅ Data displays correctly

### 3. Check Database Connections
```bash
# Connect to PostgreSQL directly
docker exec -it cv_postgres psql -U cv_agent -d cv_trading

# Run queries to verify data
SELECT COUNT(*) FROM market_data;
SELECT COUNT(*) FROM models;
SELECT * FROM trading_config;

# Exit
\q
```

### 4. Monitor for 24 Hours
Keep services running and check logs periodically:
```bash
docker-compose logs --tail=100 -f
```

Look for:
- ✅ No "disk I/O error"
- ✅ No database connection errors
- ✅ Trader generating predictions
- ✅ Bridge syncing market data

## Rollback Plan

If PostgreSQL has issues, rollback to SQLite:

```bash
# 1. Stop all services
docker-compose down

# 2. Update .env to use SQLite
cat > .env << EOF
DATABASE_TYPE=sqlite
EOF

# 3. Update bridge/.env
cat > bridge/.env << EOF
DATABASE_TYPE=sqlite
EOF

# 4. Restore SQLite backup
cp data/cv_agent.db.backup.YYYYMMDD_HHMMSS data/cv_agent.db

# 5. Start services (without postgres)
docker-compose up dashboard trader

# 6. Restart bridge manually
python bridge/mt5_bridge.py
```

## Troubleshooting

### Error: "psycopg2 not found"
**Solution:** Install PostgreSQL driver
```bash
pip install psycopg2-binary
```

### Error: "connection refused"
**Solution:** Ensure PostgreSQL is running and healthy
```bash
docker-compose logs postgres
docker-compose ps postgres
```

### Error: "authentication failed"
**Solution:** Check password in .env files matches
```bash
# Should match in both files:
grep POSTGRES_PASSWORD .env
grep DATABASE_URL .env
grep DATABASE_URL bridge/.env
```

### Error: "disk I/O error" still happening
**Solution:** Verify DATABASE_TYPE is set correctly
```bash
# In containers
docker exec cv_dashboard env | grep DATABASE_TYPE
docker exec cv_trader env | grep DATABASE_TYPE

# Should show: DATABASE_TYPE=postgresql
```

### Dashboard/Trader not connecting to PostgreSQL
**Solution:** Check depends_on in docker-compose.yml
```bash
# Restart services in correct order
docker-compose down
docker-compose up -d postgres
# Wait 10 seconds
docker-compose up -d dashboard trader
```

### Bridge can't connect from Windows host
**Solution:** Ensure port 5432 is exposed
```bash
# Check port mapping
docker-compose ps postgres
# Should show: 0.0.0.0:5432->5432/tcp

# Test connection from Windows
psql -h localhost -p 5432 -U cv_agent -d cv_trading
```

## Performance Tuning (Optional)

For high-frequency trading, tune PostgreSQL settings:

1. **Increase connection pool size** (db_manager.py):
   ```python
   self._pg_pool = psycopg2.pool.ThreadedConnectionPool(
       minconn=5,   # Increase from 2
       maxconn=20,  # Increase from 10
       dsn=self.db_url
   )
   ```

2. **Add PostgreSQL performance settings** (docker-compose.yml):
   ```yaml
   postgres:
     command:
       - "postgres"
       - "-c"
       - "shared_buffers=256MB"
       - "-c"
       - "max_connections=100"
       - "-c"
       - "work_mem=16MB"
   ```

3. **Monitor query performance:**
   ```sql
   -- Connect to PostgreSQL
   docker exec -it cv_postgres psql -U cv_agent -d cv_trading

   -- Check slow queries
   SELECT query, calls, mean_exec_time, total_exec_time
   FROM pg_stat_statements
   ORDER BY mean_exec_time DESC
   LIMIT 10;
   ```

## Maintenance

### Backup PostgreSQL
```bash
# Backup database
docker exec cv_postgres pg_dump -U cv_agent cv_trading > backup_$(date +%Y%m%d).sql

# Verify backup
ls -lh backup_*.sql
```

### Restore PostgreSQL
```bash
# Stop services
docker-compose down

# Remove old data
docker volume rm computerVision_postgres_data

# Start postgres
docker-compose up -d postgres

# Wait for ready
sleep 10

# Restore backup
cat backup_20260210.sql | docker exec -i cv_postgres psql -U cv_agent -d cv_trading
```

### Vacuum Database (Monthly)
```sql
-- Connect to PostgreSQL
docker exec -it cv_postgres psql -U cv_agent -d cv_trading

-- Vacuum all tables
VACUUM ANALYZE;

-- Check database size
SELECT pg_size_pretty(pg_database_size('cv_trading'));
```

## Success Criteria

Migration is successful when:

1. ✅ All 20 tables migrated with 100% data integrity
2. ✅ Dashboard loads and displays data correctly
3. ✅ Trader generates predictions and tracks positions
4. ✅ Bridge syncs market data (H1, H4, D1)
5. ✅ No "disk I/O error" for 24 hours
6. ✅ Concurrent access works (dashboard + trader + bridge)
7. ✅ Performance ≥ SQLite baseline

## Support

If you encounter issues:

1. Check logs: `docker-compose logs`
2. Verify environment: `docker exec cv_dashboard env | grep DATABASE`
3. Test PostgreSQL: `docker exec -it cv_postgres psql -U cv_agent -d cv_trading`
4. Review this guide's Troubleshooting section
5. Check DATABASE_FIXES.md for known issues

## Files Changed

- ✅ `docker-compose.yml` - Added PostgreSQL service
- ✅ `.env` - Database configuration
- ✅ `bridge/.env` - Bridge database configuration
- ✅ `.gitignore` - Ignore .env files
- ✅ `requirements-linux.txt` - Added psycopg2-binary, python-dotenv
- ✅ `Dockerfile.trader` - Added libpq-dev
- ✅ `src/database/db_manager.py` - Database abstraction layer
- ✅ `src/database/schema_postgres.sql` - PostgreSQL schema
- ✅ `scripts/migrate_sqlite_to_postgres.py` - Migration script
- ✅ `bridge/mt5_bridge.py` - PostgreSQL support

## Next Steps

After successful migration:

1. Monitor for 24-48 hours
2. Run performance benchmarks
3. Update documentation
4. Train team on PostgreSQL operations
5. Setup automated backups
6. Consider upgrading to PostgreSQL 16 in future
