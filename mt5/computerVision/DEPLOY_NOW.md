# 🚀 Quick Deployment Guide - PostgreSQL Migration

## ⚡ Quick Start (5 Minutes)

### Step 1: Secure Your Password (30 seconds)

**IMPORTANT:** Change the default password first!

```bash
# Edit .env file and change the password
notepad .env

# Change this line:
POSTGRES_PASSWORD=cv_trading_2024

# To something secure like:
POSTGRES_PASSWORD=your_super_secure_random_password_here

# Also update DATABASE_URL with same password:
DATABASE_URL=postgresql://cv_agent:your_super_secure_random_password_here@postgres:5432/cv_trading
```

**Also update bridge/.env:**
```bash
notepad bridge\.env

# Change the password in DATABASE_URL to match
DATABASE_URL=postgresql://cv_agent:your_super_secure_random_password_here@localhost:5432/cv_trading
```

### Step 2: Backup Your Data (30 seconds)

```bash
# Windows PowerShell or Git Bash
cp data/cv_agent.db data/cv_agent.db.backup
```

### Step 3: Start PostgreSQL (1 minute)

```bash
# Build with new dependencies
docker-compose build

# Start PostgreSQL
docker-compose up -d postgres

# Wait and check it's healthy
docker-compose ps postgres
# Should show: "healthy"
```

### Step 4: Migrate Your Data (2 minutes)

**Only if you have existing data in SQLite:**

```bash
# Install Python dependencies (if needed)
pip install psycopg2-binary python-dotenv

# Run migration (replace password with yours)
python scripts/migrate_sqlite_to_postgres.py \
  --sqlite data/cv_agent.db \
  --postgres "postgresql://cv_agent:your_super_secure_random_password_here@localhost:5432/cv_trading"
```

**Skip if starting fresh** - PostgreSQL schema is already loaded.

### Step 5: Start All Services (30 seconds)

```bash
# Start dashboard and trader
docker-compose up -d

# Check all services are running
docker-compose ps
```

### Step 6: Restart Bridge (30 seconds)

```bash
# Install dependencies if needed
pip install psycopg2-binary python-dotenv

# Stop old bridge (if running)
# Then start new one
python bridge/mt5_bridge.py
```

### Step 7: Verify (30 seconds)

```bash
# Check logs
docker-compose logs --tail=50

# Look for these SUCCESS messages:
# ✓ "PostgreSQL connection pool initialized"
# ✓ "Database type: postgresql"
# ✓ No "disk I/O error" messages

# Open dashboard
start http://localhost:8501
```

---

## ✅ Success Indicators

You'll know it worked when you see:

### In Docker Logs:
```
cv_postgres    | database system is ready to accept connections
cv_dashboard   | [OK] PostgreSQL connection pool initialized
cv_trader      | Database type: postgresql
```

### In Bridge Logs:
```
Loaded environment variables from bridge/.env
Database type: postgresql
PostgreSQL connection: localhost:5432/cv_trading
MT5 connected successfully
```

### In Dashboard:
- ✅ No error messages
- ✅ Data loads correctly
- ✅ No "disk I/O error"

---

## 🔴 If Something Goes Wrong

### Quick Rollback (2 minutes)

```bash
# 1. Stop everything
docker-compose down

# 2. Switch back to SQLite
echo DATABASE_TYPE=sqlite > .env
echo DATABASE_TYPE=sqlite > bridge\.env

# 3. Restore backup
cp data/cv_agent.db.backup data/cv_agent.db

# 4. Start without postgres
docker-compose up dashboard trader

# 5. Restart bridge
python bridge/mt5_bridge.py
```

---

## 📚 Need More Details?

See **POSTGRESQL_MIGRATION.md** for:
- Detailed troubleshooting
- Performance tuning
- Maintenance procedures
- Architecture diagrams

---

## 🎯 What Changed?

All these files were created/modified:

**New Files:**
- ✅ `.env` - Database config
- ✅ `bridge/.env` - Bridge config
- ✅ `.gitignore` - Security
- ✅ `src/database/schema_postgres.sql` - PostgreSQL schema
- ✅ `scripts/migrate_sqlite_to_postgres.py` - Migration tool
- ✅ `POSTGRESQL_MIGRATION.md` - Full guide
- ✅ `MIGRATION_SUMMARY.md` - Implementation details
- ✅ `DEPLOY_NOW.md` - This file

**Modified Files:**
- ✅ `docker-compose.yml` - Added PostgreSQL service
- ✅ `requirements-linux.txt` - Added psycopg2-binary, python-dotenv
- ✅ `Dockerfile.trader` - Added PostgreSQL support
- ✅ `src/database/db_manager.py` - Dual database support
- ✅ `bridge/mt5_bridge.py` - Environment variable loading

---

## 💡 Pro Tips

1. **Use strong passwords** - Generate with: `openssl rand -base64 32`
2. **Keep backups** - Run before migration: `cp data/cv_agent.db data/cv_agent.db.backup`
3. **Monitor logs** - Use: `docker-compose logs -f`
4. **Test thoroughly** - Verify all functionality works
5. **Rollback plan ready** - Know how to switch back to SQLite

---

## 🎉 That's It!

Your system is now running on PostgreSQL with:
- ✅ No more "disk I/O error"
- ✅ Better concurrent access
- ✅ Faster performance
- ✅ Production-ready reliability

**Questions?** Check POSTGRESQL_MIGRATION.md or DATABASE_FIXES.md

---

**Need Help?**
1. Check logs: `docker-compose logs`
2. Verify environment: `docker exec cv_dashboard env | grep DATABASE`
3. Test connection: `docker exec -it cv_postgres psql -U cv_agent -d cv_trading`
