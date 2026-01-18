FROM gmag11/metatrader5_vnc:latest

# Switch to root to install python dependencies
USER root

# Install python3-pip and venv if needed (Debian Bookworm)
# Fix GPG error by removing broken winehq source which is not needed for python install
RUN rm -f /etc/apt/sources.list.d/winehq-bookworm.sources && \
    apt-get update && \
    apt-get install -y python3-pip python3-venv sudo && \
    rm -rf /var/lib/apt/lists/*

# Configure sudo to allow root to run wine as abc user without password
RUN echo "root ALL=(abc) NOPASSWD: ALL" >> /etc/sudoers

# Install FastAPI and Uvicorn
# Using --break-system-packages because we are in a container and want global install
RUN pip3 install fastapi uvicorn --break-system-packages

# Set workdir
WORKDIR /app

# Copy API script
COPY compile_api.py /app/compile_api.py
COPY entrypoint_wrapper.sh /app/entrypoint_wrapper.sh

# Make wrapper executable
RUN chmod +x /app/entrypoint_wrapper.sh

# Expose API port
EXPOSE 8080

# Override entrypoint to run our wrapper
ENTRYPOINT ["/app/entrypoint_wrapper.sh"]
