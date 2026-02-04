# Docker Compose Usage Guide

## Overview

The `docker-compose.yml` uses **profiles** for different services:

1. **Init Profile**: First-time setup to initialize Wine directory structure
2. **App Profile**: Normal operation with your code bind-mounted
3. **Dashboard Profile**: Streamlit monitoring dashboard

## First Time Setup

### Step 1: Initialize Wine Directory Structure

Run this **only once** on first setup:

```bash
docker-compose --profile init up -d
```

Wait 2-3 minutes for MT5 to fully initialize, then stop it:

```bash
docker-compose --profile init down
```

### Step 2: Run with Your Code

Now start the normal service with your code bind-mounted:

```bash
docker-compose --profile app up -d
```

## Daily Usage

For normal operation (after initial setup):

```bash
# Start MT5 with your code
docker-compose --profile app up -d

# View logs
docker-compose --profile app logs -f mt5

# Stop MT5
docker-compose --profile app down

# Restart MT5
docker-compose --profile app restart mt5
```

## Start Dashboard

Start the monitoring dashboard (make sure MT5 app profile is running first):

```bash
docker-compose --profile dashboard up -d
```

Stop the dashboard:

```bash
docker-compose --profile dashboard down
```

Access at: http://localhost:8501

## Troubleshooting

### "Directory not found" error
- Make sure you ran the init profile first
- Check that the volume was created: `docker volume ls | grep mt5_config_v2`

### Need to reinitialize
```bash
# Stop everything
docker-compose --profile app down
docker-compose --profile init down

# Delete volume (WARNING: Loses all MT5 data!)
docker volume rm mt5_config_v2

# Start over from Step 1
docker-compose --profile init up -d
```

### Check if directory structure exists
```bash
docker run --rm -v mt5_config_v2:/config alpine ls -la "/config/.wine/drive_c/Program Files/MetaTrader 5/MQL5/Experts/"
```

## Quick Reference

| Command | Description |
|---------|-------------|
| `docker-compose --profile init up -d` | First-time initialization |
| `docker-compose --profile app up -d` | Start MT5 with your code |
| `docker-compose --profile app down` | Stop MT5 |
| `docker-compose --profile app logs -f` | View MT5 logs |
| `docker-compose --profile app restart` | Restart MT5 |
| `docker-compose --profile dashboard up -d` | Start dashboard |
| `docker-compose --profile dashboard down` | Stop dashboard |
| `docker-compose --profile dashboard logs -f` | View dashboard logs |

## Why Two Profiles?

Wine needs to create its directory structure before we can bind-mount our code. If we try to bind-mount immediately, Docker creates the path as a directory owned by root, which breaks Wine initialization.

The profile approach:
- ✅ Single docker-compose.yml file
- ✅ Clear separation of init vs runtime
- ✅ No manual file juggling
- ✅ Easy to remember commands

## Sources

- [Docker Compose Profiles Documentation](https://docs.docker.com/compose/profiles/)
- [Bind mounts | Docker Docs](https://docs.docker.com/engine/storage/bind-mounts/)
- [How to Choose Between Docker Bind Mounts and Named Volumes](https://oneuptime.com/blog/post/2026-01-16-docker-bind-mounts-vs-volumes/view)
