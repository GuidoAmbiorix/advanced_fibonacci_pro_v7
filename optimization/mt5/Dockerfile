FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install Wine, VNC, and noVNC dependencies
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
        python3 \
        python3-pip \
        supervisor \
        novnc \
        websockify \
        net-tools \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install FastAPI for compile API
RUN pip3 install fastapi uvicorn

# Create user
RUN useradd -m -s /bin/bash mt5
WORKDIR /home/mt5

# Setup VNC password
RUN mkdir -p /home/mt5/.vnc && \
    x11vnc -storepasswd optima /home/mt5/.vnc/passwd

# Copy scripts
COPY entrypoint.sh /home/mt5/entrypoint.sh
COPY compile_api.py /home/mt5/compile_api.py
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

RUN chmod +x /home/mt5/entrypoint.sh && \
    chown -R mt5:mt5 /home/mt5

# Environment
ENV WINEPREFIX=/home/mt5/.wine
ENV WINEARCH=win64
ENV DISPLAY=:0

# Create data directory
RUN mkdir -p /data/ea_sources /data/ea_compiled /data/reports && \
    chown -R mt5:mt5 /data

# Switch to user for Wine init
USER mt5
RUN winecfg && sleep 3

USER root

# Expose ports: VNC, noVNC (web), API
EXPOSE 5900 6080 8080

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
