FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY main.py .
COPY wait-for-mt5.sh .
RUN chmod +x wait-for-mt5.sh

EXPOSE 8001

# Wait for MT5 to be ready, then start API
CMD ["./wait-for-mt5.sh", "python", "main.py"]
