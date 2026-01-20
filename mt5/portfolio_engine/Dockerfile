FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Expose web dashboard port
# Expose web dashboard port (Streamlit default)
EXPOSE 8501

CMD ["streamlit", "run", "visualization/streamlit_app.py", "--server.port=8501", "--server.address=0.0.0.0"]
