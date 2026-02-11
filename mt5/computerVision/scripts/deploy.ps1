# PowerShell Deployment Script for Local Testing (ASCII)
$ErrorActionPreference = "Stop"

Write-Host "Deploying Advanced Fibonacci Trading System (Windows Mode)..." -ForegroundColor Cyan

# Check if .env exists
if (-not (Test-Path ".env")) {
    Write-Host "Error: .env file not found" -ForegroundColor Red
    Write-Host "Copy .env.example to .env and configure your secrets"
    exit 1
}

# Create necessary directories
$directories = @("volumes\postgres_data", "volumes\mt5_data", "volumes\logs", "volumes\backups")
foreach ($dir in $directories) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

# Build images
Write-Host "Building Docker images..." -ForegroundColor Yellow
docker compose build --no-cache
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# Start infrastructure services first
Write-Host "Starting database..." -ForegroundColor Yellow
docker compose up -d postgres redis
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# Wait for database to be healthy
Write-Host "Waiting for database to be ready..." -ForegroundColor Cyan
$retries = 30
$healthy = $false
while ($retries -gt 0) {
    try {
        docker compose exec postgres pg_isready -U cv_agent
        if ($LASTEXITCODE -eq 0) {
            $healthy = $true
            break
        }
    } catch {
        # Ignore error
    }
    Start-Sleep -Seconds 2
    $retries--
}

if (-not $healthy) {
    Write-Host "Database check timed out or failed, proceeding anyway but logs might show errors..." -ForegroundColor Yellow
}

# Start MT5 terminal
Write-Host "Starting MT5 terminal..." -ForegroundColor Yellow
docker compose up -d mt5-terminal

# Wait for MT5 to initialize
Write-Host "Waiting for MT5 to initialize (60s)..." -ForegroundColor Cyan
Start-Sleep -Seconds 60

# Start application services
Write-Host "Starting trading services..." -ForegroundColor Yellow
docker compose up -d bridge trader dashboard postgres-backup

# Start nginx (if configured)
if (Test-Path "configs\nginx\nginx.conf") {
    Write-Host "Starting Nginx..." -ForegroundColor Yellow
    docker compose up -d nginx
}

# Show status
Write-Host "Deployment complete!" -ForegroundColor Green
Write-Host ""
docker compose ps

Write-Host ""
Write-Host "Access points (Localhost):"
Write-Host "  Dashboard: http://localhost:8501"
Write-Host "  MT5 Terminal: http://localhost:6080"
Write-Host "  Bridge API: http://localhost:5000"
Write-Host ""
