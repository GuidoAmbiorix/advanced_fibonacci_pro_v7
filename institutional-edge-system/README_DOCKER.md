# Docker Setup for Institutional Edge PRO

This guide will help you set up the database using Docker.

## Prerequisites

- Docker Desktop installed and running
- Docker Compose (included with Docker Desktop)

## Quick Start

### 1. Start the Database

```bash
# Start all services (PostgreSQL, Redis, PgAdmin)
docker-compose up -d

# Check if containers are running
docker-compose ps

# View logs
docker-compose logs -f postgres
```

### 2. Verify PostgreSQL is Running

```bash
# Connect to PostgreSQL using psql
docker exec -it institutional_edge_db psql -U postgres -d institutional_edge

# Inside psql, you can run:
\l          # List databases
\dt         # List tables (after initialization)
\q          # Quit
```

### 3. Access PgAdmin (Optional)

1. Open browser: http://localhost:5050
2. Login:
   - Email: admin@institutional-edge.com
   - Password: admin
3. Add server:
   - Host: postgres
   - Port: 5432
   - Database: institutional_edge
   - Username: postgres
   - Password: postgres

## Service Details

### PostgreSQL
- **Host:** localhost
- **Port:** 5432
- **Database:** institutional_edge
- **Username:** postgres
- **Password:** postgres
- **Connection String:** `postgresql://postgres:postgres@localhost:5432/institutional_edge`

### Redis
- **Host:** localhost
- **Port:** 6379

### PgAdmin
- **URL:** http://localhost:5050
- **Email:** admin@institutional-edge.com
- **Password:** admin

## Docker Commands

```bash
# Start services
docker-compose up -d

# Stop services
docker-compose down

# Stop and remove volumes (WARNING: This deletes all data!)
docker-compose down -v

# View logs
docker-compose logs -f

# Restart a specific service
docker-compose restart postgres

# Execute commands in PostgreSQL container
docker exec -it institutional_edge_db psql -U postgres -d institutional_edge

# Backup database
docker exec institutional_edge_db pg_dump -U postgres institutional_edge > backup.sql

# Restore database
docker exec -i institutional_edge_db psql -U postgres institutional_edge < backup.sql
```

## Troubleshooting

### Port Already in Use

If port 5432 is already in use:

1. Stop existing PostgreSQL service
2. Or change the port in docker-compose.yml:
   ```yaml
   ports:
     - "5433:5432"  # Change to 5433
   ```
   Then update DATABASE_URL in .env to use port 5433

### Container Won't Start

```bash
# Check container logs
docker-compose logs postgres

# Remove and recreate
docker-compose down
docker-compose up -d
```

### Reset Database

```bash
# Stop and remove everything
docker-compose down -v

# Start fresh
docker-compose up -d
```

## Production Notes

For production deployment:

1. Change default passwords in docker-compose.yml
2. Use Docker secrets for sensitive data
3. Configure regular backups
4. Set resource limits
5. Use external volumes for data persistence
6. Configure SSL/TLS for PostgreSQL

## Integration with Application

The `.env` file should contain:

```bash
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/institutional_edge
REDIS_HOST=localhost
REDIS_PORT=6379
```

Then run the database initialization script:

```bash
python init_db.py
```
