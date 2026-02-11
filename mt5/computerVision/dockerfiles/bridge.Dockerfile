FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        gcc \
        postgresql-client && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy requirements
COPY bridge/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY bridge/ ./bridge/

# Health check endpoint
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s \
    CMD curl -f http://localhost:5000/status || exit 1

EXPOSE 5000

CMD ["python", "bridge/mt5_bridge.py"]
