# Quick Start Guide - Database Setup

This guide will help you get the database up and running in 5 minutes.

## Step 1: Start Docker Desktop

Make sure Docker Desktop is running on your machine.

```bash
# Check if Docker is running
docker --version
docker-compose --version
```

## Step 2: Start the Database

```bash
# Navigate to project directory
cd institutional-edge-system

# Start PostgreSQL, Redis, and PgAdmin
docker-compose up -d

# Verify containers are running
docker-compose ps
```

You should see:
```
NAME                        STATUS
institutional_edge_db       Up (healthy)
institutional_edge_redis    Up
institutional_edge_pgadmin  Up
```

## Step 3: Initialize the Database

```bash
# Run the initialization script
python init_db.py
```

This will:
- Test the database connection
- Create all required tables
- Create an admin user
- Set up a default bot configuration

## Step 4: Verify Everything Works

### Option 1: Using psql (Command Line)

```bash
# Connect to the database
docker exec -it institutional_edge_db psql -U postgres -d institutional_edge

# List all tables
\dt

# View users
SELECT * FROM users;

# Exit
\q
```

### Option 2: Using PgAdmin (Web Interface)

1. Open browser: http://localhost:5050
2. Login:
   - Email: `admin@institutional-edge.com`
   - Password: `admin`
3. Right-click "Servers" → "Register" → "Server"
4. Connection settings:
   - Name: Institutional Edge
   - Host: `postgres`
   - Port: `5432`
   - Database: `institutional_edge`
   - Username: `postgres`
   - Password: `postgres`

## Step 5: Start the Application

### Backend

```bash
cd backend/app
python main.py
```

Access API docs at: http://localhost:8000/docs

### Frontend

```bash
cd frontend
npm install  # First time only
npm run dev
```

Access dashboard at: http://localhost:5173

## Default Credentials

### Database
- Host: `localhost:5432`
- Database: `institutional_edge`
- Username: `postgres`
- Password: `postgres`

### PgAdmin
- URL: http://localhost:5050
- Email: `admin@institutional-edge.com`
- Password: `admin`

### Application Admin User
- Email: `admin@institutional-edge.com`
- Password: `admin123`
- ⚠️ Change this password after first login!

## Common Issues

### Port 5432 Already in Use

If you have PostgreSQL already installed:

```bash
# Stop existing PostgreSQL service (Windows)
net stop postgresql-x64-15

# Or use a different port in docker-compose.yml
# Change ports to "5433:5432"
# Then update .env: DATABASE_URL=postgresql://postgres:postgres@localhost:5433/institutional_edge
```

### Docker Not Running

```bash
# Start Docker Desktop
# Wait for it to fully start
# Then run: docker-compose up -d
```

### Permission Denied

```bash
# On Linux/Mac, you might need sudo
sudo docker-compose up -d
```

### Can't Connect to Database

```bash
# Check if container is running
docker-compose ps

# View container logs
docker-compose logs postgres

# Restart the container
docker-compose restart postgres

# Full reset (WARNING: Deletes all data!)
docker-compose down -v
docker-compose up -d
python init_db.py
```

## Stopping the Database

```bash
# Stop all containers
docker-compose down

# Stop and remove all data (WARNING: Deletes everything!)
docker-compose down -v
```

## Backup and Restore

### Backup

```bash
# Create a backup
docker exec institutional_edge_db pg_dump -U postgres institutional_edge > backup_$(date +%Y%m%d).sql
```

### Restore

```bash
# Restore from backup
docker exec -i institutional_edge_db psql -U postgres institutional_edge < backup_20240101.sql
```

## Next Steps

1. ✅ Database is running
2. ✅ Tables created
3. ✅ Admin user exists
4. ➡️ Start the backend API
5. ➡️ Start the frontend dashboard
6. ➡️ Configure MT5 credentials in `.env`
7. ➡️ Start trading!

## Useful Commands

```bash
# View all running containers
docker ps

# View database logs in real-time
docker-compose logs -f postgres

# Connect to database shell
docker exec -it institutional_edge_db psql -U postgres -d institutional_edge

# Restart database
docker-compose restart postgres

# Check database health
docker-compose ps postgres
```

## Production Notes

Before deploying to production:

1. Change all default passwords
2. Use environment variables for sensitive data
3. Enable SSL/TLS for PostgreSQL
4. Set up automated backups
5. Configure firewall rules
6. Use strong passwords
7. Enable logging and monitoring

For detailed Docker documentation, see `README_DOCKER.md`
