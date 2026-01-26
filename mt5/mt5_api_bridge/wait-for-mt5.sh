#!/bin/bash
# Wait for MT5 to be ready before starting API

echo "Waiting for MT5 to start..."
sleep 10

echo "Starting MT5 API Bridge..."
exec "$@"
