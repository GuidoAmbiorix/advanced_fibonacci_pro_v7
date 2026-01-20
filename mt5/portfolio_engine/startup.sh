#!/bin/bash
# startup.sh - Fix Dependencies for MT5Linux
# gmag11/metatrader5_vnc runs an internal RPyC server which fails with numpy 2.x
# This script ensures we have numpy<2 installed.

echo ">>> DEPS-FIX STARTUP EXECUTING <<<"

# Run as user 'abc' (UID 911) which owns the wine prefix
run_as_user() {
    if [ "$(id -u)" = "0" ]; then
        s6-setuidgid abc "$@"
    else
        "$@"
    fi
}

echo "Ensuring PIP is installed (as user abc)..."
if ! run_as_user wine python -m pip --version > /dev/null 2>&1; then
    echo "PIP not found. Bootstrapping..."
    curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
    run_as_user wine python get-pip.py
    rm get-pip.py
fi

echo "Checking modules..."
# Check if valid numpy is installed
if run_as_user wine python -c "import numpy; exit(0 if int(numpy.__version__.split('.')[0]) < 2 else 1)" > /dev/null 2>&1; then
    echo "Correct NumPy version detected. Checking other deps..."
    if run_as_user wine python -c "import rpyc; import MetaTrader5" > /dev/null 2>&1; then
         echo "All dependencies OK. Skipping install."
         exit 0
    fi
fi

echo "Installing/Fixing dependencies..."
# Force install of numpy<2 to support MetaTrader5 package
run_as_user wine python -m pip install --no-cache-dir --upgrade "numpy<2" "rpyc<6" MetaTrader5

echo ">>> DEPS-FIX COMPLETE <<<"
