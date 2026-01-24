#!/bin/bash
set -e

echo "Starting MT5 API Server entrypoint..."

# Start the original MT5 container init in the background
/init &

# Wait a bit for MT5 to initialize
sleep 10

echo "Starting MT5 API Server on port 8001..."
# Start the API server
cd /app
python3 mt5_api_server.py &

# Keep container running
wait -n

# Exit with status of process that exited first
exit $?
