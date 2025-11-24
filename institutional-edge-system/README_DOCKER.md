# Docker Setup for Institutional Edge PRO

This guide will help you set up the entire system (Frontend, Backend, Database, Redis) using Docker.

## Prerequisites

- Docker Desktop installed and running
- Docker Compose (included with Docker Desktop)

## Quick Start

### 1. Start the System

```bash
# Start all services (Frontend, Backend, PostgreSQL, Redis, PgAdmin)
docker-compose up -d --build

# Check if containers are running
docker-compose ps

# View logs
docker-compose logs -f
```

### 2. Access the Application

- **Frontend (Dashboard):** http://localhost
- **Backend API:** http://localhost:8000
- **API Documentation:** http://localhost:8000/docs
- **PgAdmin (Database UI):** http://localhost:5050

### 3. Important Note on MetaTrader 5

The backend running in Docker is Linux-based. **MetaTrader 5 (MT5) is a Windows-only application.**

- When running in Docker, the backend will start in **Headless/Mock Mode**.
- It will **NOT** connect to a real MT5 terminal.
- This mode allows you to develop the UI, test the API, and work with the database without a live trading connection.
- To connect to a real MT5 terminal, you must run the backend **locally on Windows** (outside Docker) while keeping the database and frontend in Docker, OR use a Windows container (advanced).

## Service Details

### Frontend
- **Host:** localhost
- **Port:** 80
- **Technology:** Vue 3 + Vite (served by Nginx)

### Backend
- **Host:** localhost
- **Port:** 8000
- **Technology:** FastAPI (Python 3.11)
- **Swagger Docs:** http://localhost:8000/docs

### PostgreSQL
- **Host:** localhost
- **Port:** 5433 (mapped from 5432)
- **Database:** institutional_edge
- **Username:** postgres
- **Password:** postgres

### Redis
- **Host:** localhost
- **Port:** 6379

### PgAdmin
- **URL:** http://localhost:5050
- **Email:** admin@institutional-edge.com
- **Password:** admin

## Docker Commands

```bash
# Start services and rebuild images
docker-compose up -d --build

# Stop services
docker-compose down

# Stop and remove volumes (WARNING: This deletes all database data!)
docker-compose down -v

# View logs for a specific service
docker-compose logs -f backend
docker-compose logs -f frontend

# Execute commands in Backend container
docker exec -it institutional_edge_backend bash

# Execute commands in PostgreSQL container
docker exec -it institutional_edge_db psql -U postgres -d institutional_edge
```

## Troubleshooting

### Port Conflicts
If ports 80, 8000, or 5433 are in use, modify `docker-compose.yml` ports section:
```yaml
ports:
  - "8080:80"  # Change frontend to 8080
```

### Database Connection
The backend automatically connects to the `postgres` service within the Docker network using the hostname `postgres`. You do not need to change `.env` files for Docker execution; `docker-compose.yml` handles the environment variables.
