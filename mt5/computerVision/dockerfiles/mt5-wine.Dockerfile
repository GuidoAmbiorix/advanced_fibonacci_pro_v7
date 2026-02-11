# Based on proven MT5-Docker solutions
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:99
ENV WINEARCH=win64
ENV WINEPREFIX=/root/.wine

# Install Wine, X11, VNC, noVNC
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y \
        wine64 wine32 winetricks \
        xvfb x11vnc novnc websockify \
        wget curl unzip \
        supervisor && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Download and install MT5
RUN mkdir -p /install && \
    wget -O /install/mt5setup.exe \
        "https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe" && \
    Xvfb :99 -screen 0 1024x768x16 & \
    sleep 5 && \
    wine /install/mt5setup.exe /auto && \
    sleep 30 && \
    rm -rf /install

# Setup VNC and noVNC
RUN mkdir -p ~/.vnc && \
    x11vnc -storepasswd ${VNC_PASSWORD:-password} ~/.vnc/passwd

# Supervisor configuration
COPY configs/mt5/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Expose ports
EXPOSE 8080 5900

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
