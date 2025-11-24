FROM python:3.11

WORKDIR /app

# System dependencies are skipped to avoid apt-get errors.
# We rely on binary wheels (psycopg2-binary) and the full python image.

# Copy requirements
COPY requirements_docker.txt requirements.txt

# Install python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Expose port
EXPOSE 8000

# Command
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
