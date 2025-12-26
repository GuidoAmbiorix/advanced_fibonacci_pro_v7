FROM python:3.9-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Install Docker Compose
RUN apt-get update && apt-get install -y curl
RUN curl -L "https://github.com/docker/compose/releases/download/v2.29.1/docker-compose-linux-x86_64" -o /usr/local/bin/docker-compose
RUN chmod +x /usr/local/bin/docker-compose

# Copy source
COPY backend /app/backend
COPY frontend /app/frontend

# Expose API
EXPOSE 8000

# Run
CMD ["uvicorn", "backend.main:app", "--host", "0.0.0.0", "--port", "8000"]
