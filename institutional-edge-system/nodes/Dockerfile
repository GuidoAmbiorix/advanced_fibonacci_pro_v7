FROM python:3.10-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    python3-dev \
    libpq-dev \
    libssl-dev \
    libffi-dev \
    && rm -rf /var/lib/apt/lists/*

# Upgrade pip
RUN pip install --upgrade pip

# Install dependencies (mirroring backend + worker specific)
# We assume requirements.txt exists in build context path
COPY orchestrator/backend/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt
# Extra deps for worker if not in requirements.txt (aio_pika might be missing?)
RUN pip install --no-cache-dir aio_pika rpyc loguru sqlalchemy psycopg2-binary pandas numpy python-dotenv

# Copy Backend Code (for shared modules)
COPY orchestrator/backend /app/orchestrator/backend

# Copy Node Code
COPY nodes /app/nodes

# Set PYTHONPATH so nodes can import app.* from backend
ENV PYTHONPATH=/app/orchestrator/backend

# Default Entrypoint
WORKDIR /app/nodes
CMD ["python", "worker.py", "--bot-id", "1"]
