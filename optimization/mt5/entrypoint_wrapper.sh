#!/bin/bash

# Start the compilation API in the background
echo "Starting Compile API..."
# Ensure environment variables are passed correctly
export WINEPREFIX="/config/.wine"
export DISPLAY=:0

# Install dependencies if simple request failed (fallback)
# but we assume they are installed in Dockerfile.

# Run the API
uvicorn compile_api:app --host 0.0.0.0 --port 8080 &

# Execute the original entrypoint (passed as CMD in Dockerfile or default /init)
exec /init
