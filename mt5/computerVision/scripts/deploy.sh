#!/bin/bash
set -e

echo "🚀 Deploying Advanced Fibonacci Trading System..."

# Check if .env exists
if [ ! -f .env ]; then
    echo "❌ Error: .env file not found"
    echo "📝 Copy .env.example to .env and configure your secrets"
    exit 1
fi

# Create necessary directories
mkdir -p volumes/{postgres_data,mt5_data,logs,backups}
chmod 700 volumes  # Secure permissions

# Build images
echo "🔨 Building Docker images..."
docker compose build --no-cache

# Start infrastructure services first
echo "🗄️ Starting database..."
docker compose up -d postgres redis

# Wait for database to be healthy
echo "⏳ Waiting for database to be ready..."
timeout 60 bash -c 'until docker compose exec postgres pg_isready -U cv_agent; do sleep 2; done'

# Start MT5 terminal
echo "🖥️ Starting MT5 terminal..."
docker compose up -d mt5-terminal

# Wait for MT5 to initialize
echo "⏳ Waiting for MT5 to initialize (60s)..."
sleep 60

# Start application services
echo "📈 Starting trading services..."
docker compose up -d bridge trader dashboard postgres-backup

# Start nginx (if configured)
if [ -f configs/nginx/nginx.conf ]; then
    echo "🌐 Starting Nginx..."
    docker compose up -d nginx
fi

# Show status
echo "✅ Deployment complete!"
echo ""
docker compose ps

echo ""
echo "📊 Access points:"
echo "  Dashboard: http://$(curl -s ifconfig.me):8501"
echo "  MT5 Terminal: http://$(curl -s ifconfig.me):6080"
echo "  Bridge API: http://$(curl -s ifconfig.me):5000"
