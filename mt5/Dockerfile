FROM ubuntu:20.04

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Enable 32-bit architecture for Wine
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        wine \
        wine32 \
        wine64 \
        xvfb \
        x11vnc \
        fluxbox \
        wget \
        cabextract \
        nano \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create user
RUN useradd -m -s /bin/bash mt5
WORKDIR /home/mt5

# Setup VNC password (default: antigravity)
RUN mkdir -p /home/mt5/.vnc && \
    x11vnc -storepasswd antigravity /home/mt5/.vnc/passwd

# Copy entrypoint
COPY entrypoint.sh /home/mt5/entrypoint.sh
RUN chmod +x /home/mt5/entrypoint.sh && \
    chown mt5:mt5 /home/mt5/entrypoint.sh

# Switch to user
USER mt5

# Environment variables
ENV WINEPREFIX=/home/mt5/.wine
ENV WINEARCH=win32
ENV DISPLAY=:0

# Initialize Wine
RUN winecfg && sleep 5

EXPOSE 5900

CMD ["/home/mt5/entrypoint.sh"]
