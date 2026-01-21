#!/bin/bash
# startup.sh - Fix Dependencies for MT5Linux
# gmag11/metatrader5_vnc runs an internal RPyC server which fails with numpy 2.x
# This script ensures we have numpy<2 installed and manages MT5 initialization.

set -euo pipefail  # Exit on error, undefined vars, pipe failures

readonly SCRIPT_NAME="$(basename "$0")"
readonly USER_ABC="abc"
readonly MT5_BASE="/config/.wine/drive_c/Program Files/MetaTrader 5"
readonly EXPERTS_PATH="${MT5_BASE}/MQL5/Experts"
readonly SIDECAR_PORT=8001
readonly LOG_PREFIX="[MT5-INIT]"

# Logging helpers
log_info() {
    echo "${LOG_PREFIX} INFO: $*" >&2
}

log_error() {
    echo "${LOG_PREFIX} ERROR: $*" >&2
}

log_success() {
    echo "${LOG_PREFIX} ✓ $*" >&2
}

# Run command as user 'abc' (UID 911) which owns the wine prefix
run_as_user() {
    if [ "$(id -u)" = "0" ]; then
        s6-setuidgid "${USER_ABC}" "$@"
    else
        "$@"
    fi
}

# Wait for a directory to exist with timeout
wait_for_directory() {
    local dir="$1"
    local timeout_seconds="$2"
    local check_interval="${3:-5}"
    local elapsed=0

    log_info "Waiting for directory: ${dir}"
    
    while [ $elapsed -lt "$timeout_seconds" ]; do
        if [ -d "$dir" ]; then
            log_success "Directory found: ${dir}"
            return 0
        fi
        sleep "$check_interval"
        elapsed=$((elapsed + check_interval))
        log_info "Still waiting... (${elapsed}s/${timeout_seconds}s)"
    done
    
    log_error "Timeout waiting for directory: ${dir}"
    return 1
}

# Link Expert Advisors
link_expert_advisors() {
    log_info "Starting Expert Advisor Linker"
    
    if ! wait_for_directory "$EXPERTS_PATH" 300 5; then
        log_error "EA-LINK: Failed to find MT5 Experts directory"
        return 1
    fi
    
    local target_link="${EXPERTS_PATH}/PortfolioManager"
    local source_dir="/mnt/experts"
    
    # Ensure source directory exists
    if [ ! -d "$source_dir" ]; then
        log_error "Source directory does not exist: ${source_dir}"
        return 1
    fi
    
    # Remove existing link if it exists
    if [ -L "$target_link" ] || [ -e "$target_link" ]; then
        log_info "Removing existing link/directory: ${target_link}"
        run_as_user rm -rf "$target_link"
    fi
    
    # Create the symbolic link
    if run_as_user ln -sfn "$source_dir" "$target_link"; then
        log_success "Experts linked: ${source_dir} -> ${target_link}"
        return 0
    else
        log_error "Failed to create symbolic link"
        return 1
    fi
}

# Setup Python dependencies for sidecar and Wine environment
setup_python_deps() {
    log_info "Setting up Python dependencies"
    
    # 1. Linux Environment (Sidecar)
    local pip_packages=(
        "rpyc==5.3.1"
        "numpy<2"
    )
    
    if run_as_user python3 -m pip install --user --upgrade --break-system-packages "${pip_packages[@]}"; then
        log_success "Linux Python dependencies installed"
    else
        log_error "Failed to install Linux Python dependencies"
        return 1
    fi

    # 2. Wine Environment (Internal Bridge)
    log_info "Attempting to FORCE upgrade MetaTrader5 and RPyC inside Wine..."
    
    # Path to Wine Python
    local wine_python="wine C:/Program Files (x86)/Python39-32/python.exe"
    
    # We use --force-reinstall to ensure we get off 5.0.36
    if run_as_user ${wine_python} -m pip install --upgrade --force-reinstall rpyc==5.3.1 "MetaTrader5>=5.0.45"; then
        log_success "Wine Python dependencies upgraded to latest"
        run_as_user ${wine_python} -m pip show MetaTrader5
    else
        log_warning "Wine upgrade failed. Checking version..."
        run_as_user ${wine_python} -m pip show MetaTrader5 || true
    fi
    
    return 0
}

log_warning() {
    echo "${LOG_PREFIX} WARNING: $*" >&2
}

# Start MT5 Bridge sidecar server
start_sidecar_server() {
    log_info "Starting MT5 Bridge Extender"
    
    # Wait for MT5 installation
    if ! wait_for_directory "$MT5_BASE" 600 5; then
        log_error "SIDECAR: MT5 installation not found"
        return 1
    fi
    
    # PERMISSION FIX: Ensure 'abc' user owns the Tester and History directories
    # This fixes "base file open error [3]" and "history synchronization error"
    log_info "Fixing permissions for Tester and History..."
    if [ "$(id -u)" = "0" ]; then
        chown -R ${USER_ABC}:${USER_ABC} "${MT5_BASE}/Tester" || true
        chown -R ${USER_ABC}:${USER_ABC} "${MT5_BASE}/bases" || true
        log_success "Permissions repaired"
    fi

    
    # Setup dependencies
    if ! setup_python_deps; then
        log_error "SIDECAR: Failed to setup dependencies"
        return 1
    fi
    
    # Change to app directory
    if [ ! -d "/app" ]; then
        log_error "SIDECAR: /app directory not found"
        return 1
    fi
    cd /app
    
    # Check if server script exists
    if [ ! -f "mt5_server.py" ]; then
        log_error "SIDECAR: mt5_server.py not found in /app"
        return 1
    fi
    
    # Set Python path to include user site-packages
    local python_version
    python_version=$(run_as_user python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
    export PYTHONPATH="${PYTHONPATH:-}:/home/${USER_ABC}/.local/lib/python${python_version}/site-packages"
    
    log_info "Launching mt5_server.py on port ${SIDECAR_PORT}"
    if run_as_user python3 mt5_server.py; then
        log_success "Sidecar server started"
        return 0
    else
        log_error "Sidecar server exited with error code $?"
        return 1
    fi
}

# Main execution
main() {
    log_info "MT5 Custom Initialization Starting"
    
    # Start background tasks with proper error handling
    (
        if link_expert_advisors; then
            log_success "EA-LINK task completed"
        else
            log_error "EA-LINK task failed"
        fi
    ) &
    
    (
        if start_sidecar_server; then
            log_success "SIDECAR task completed"
        else
            log_error "SIDECAR task failed"
        fi
    ) &
    
    log_success "Background tasks launched"
    log_info "Use 'docker logs -f <container>' to monitor progress"
}

# Execute main function
main

exit 0