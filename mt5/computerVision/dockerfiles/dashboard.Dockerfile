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
COPY dashboard/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY dashboard/ ./dashboard/

EXPOSE 8501

CMD ["streamlit", "run", "dashboard/app.py", \
     "--server.address=0.0.0.0", \
     "--server.port=8501", \
     "--server.headless=true"]
