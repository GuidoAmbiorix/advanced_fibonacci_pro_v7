# MT5 Docker Container with Wine + RPyC
# For headless automated backtesting

FROM ubuntu:22.04

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive
ENV WINEARCH=win64
ENV WINEPREFIX=/root/.wine
ENV DISPLAY=:99

# Install base dependencies
RUN apt-get update && apt-get install -y \
    wget \
    curl \
    gnupg2 \
    software-properties-common \
    xvfb \
    x11vnc \
    supervisor \
    cabextract \
    winbind \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Add Wine repository and install
RUN dpkg --add-architecture i386 && \
    mkdir -pm755 /etc/apt/keyrings && \
    wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key && \
    wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/ubuntu/dists/jammy/winehq-jammy.sources && \
    apt-get update && \
    apt-get install -y --install-recommends winehq-stable || apt-get install -y wine64 wine32

# Install Winetricks
RUN wget -q https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks -O /usr/local/bin/winetricks && \
    chmod +x /usr/local/bin/winetricks

# Initialize Wine and install dependencies
RUN xvfb-run -a wineboot --init && \
    xvfb-run -a winetricks -q vcrun2019 corefonts || true

# Download MetaTrader 5 installer
RUN wget -q -O /tmp/mt5setup.exe "https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe"

# Install MT5 silently
RUN xvfb-run -a wine /tmp/mt5setup.exe /auto || true && \
    sleep 30 && \
    rm -f /tmp/mt5setup.exe

# Download and install Python in Wine
RUN wget -q -O /tmp/python-installer.exe "https://www.python.org/ftp/python/3.10.11/python-3.10.11-amd64.exe" && \
    xvfb-run -a wine /tmp/python-installer.exe /quiet InstallAllUsers=1 PrependPath=1 Include_pip=1 || true && \
    sleep 20 && \
    rm -f /tmp/python-installer.exe

# Install Python packages in Wine
RUN xvfb-run -a wine python -m pip install --upgrade pip && \
    xvfb-run -a wine python -m pip install MetaTrader5 rpyc numpy pandas || true

# Install Python packages for host (RPyC server runs on Linux Python)
RUN pip3 install rpyc

# Create directories
RUN mkdir -p /opt/mt5 /tmp/mt5_reports /var/log/supervisor

# Copy server scripts
COPY rpyc_mt5_server.py /opt/mt5/rpyc_mt5_server.py
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY entrypoint.sh /opt/mt5/entrypoint.sh
RUN chmod +x /opt/mt5/entrypoint.sh

# Expose ports
EXPOSE 18812 5900

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD python3 -c "import rpyc; c = rpyc.connect('localhost', 18812); c.close()" || exit 1

# Start supervisor
CMD ["/opt/mt5/entrypoint.sh"]
