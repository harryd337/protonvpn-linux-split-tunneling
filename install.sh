#!/bin/bash
# install.sh - Automated setup script for ProtonVPN split tunneling
#
# This script installs the ProtonVPN split tunnel system including:
# - Copying scripts to system locations
# - Installing systemd services
# - Setting up configuration files

set -euo pipefail

# Constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BIN_DIR="/usr/local/bin"
readonly ETC_DIR="/usr/local/etc"
readonly SYSTEMD_DIR="/etc/systemd/system"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

# Error handling function
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root (use sudo)"
    fi
}

# Validate source files exist
validate_files() {
    local files=(
        "scripts/protonvpn-split-tunnel-add.sh"
        "scripts/protonvpn-split-tunnel-remove.sh"
        "scripts/protonvpn-split-tunnel-monitor.sh"
        "examples/protonvpn-split-tunnel.conf.example"
        "systemd/protonvpn-split-tunnel.service"
    )
    
    for file in "${files[@]}"; do
        if [[ ! -f "${SCRIPT_DIR}/${file}" ]]; then
            error_exit "Required file not found: ${file}"
        fi
    done
}

# Create directories if they don't exist
create_directories() {
    mkdir -p "${ETC_DIR}" || error_exit "Failed to create ${ETC_DIR}"
}

# Copy scripts and set permissions
install_scripts() {
    log "Installing scripts..."
    
    local scripts=(
        "protonvpn-split-tunnel-add.sh"
        "protonvpn-split-tunnel-remove.sh"
        "protonvpn-split-tunnel-monitor.sh"
    )
    
    for script in "${scripts[@]}"; do
        cp "${SCRIPT_DIR}/scripts/${script}" "${BIN_DIR}/" || error_exit "Failed to copy ${script}"
        chmod +x "${BIN_DIR}/${script}" || error_exit "Failed to set permissions on ${script}"
        log "Installed ${script}"
    done
}

# Check configuration file exists
check_config() {
    log "Checking for configuration file..."
    
    if [[ ! -f "${ETC_DIR}/protonvpn-split-tunnel.conf" ]]; then
        log "ERROR: Configuration file not found!"
        log ""
        log "You must create a configuration file before installing the split tunnel system."
        log ""
        log "Steps to create the configuration:"
        log "1. Copy the example configuration:"
        log "   sudo cp ${SCRIPT_DIR}/examples/protonvpn-split-tunnel.conf.example ${ETC_DIR}/protonvpn-split-tunnel.conf"
        log ""
        log "2. Edit the configuration file:"
        log "   sudo nano ${ETC_DIR}/protonvpn-split-tunnel.conf"
        log ""
        log "3. Configure your split tunnel routes (replace the example IPs with your own)"
        log ""
        log "4. Run this installer again:"
        log "   sudo ./install.sh"
        log ""
        error_exit "Configuration file required before installation"
    else
        log "Configuration file found: ${ETC_DIR}/protonvpn-split-tunnel.conf"
    fi
}

# Install systemd services
install_services() {
    log "Installing systemd services..."
    
    local services=(
        "protonvpn-split-tunnel.service"
    )
    
    for service in "${services[@]}"; do
        cp "${SCRIPT_DIR}/systemd/${service}" "${SYSTEMD_DIR}/" || error_exit "Failed to copy ${service}"
        log "Installed ${service}"
    done
    
    systemctl daemon-reload || error_exit "Failed to reload systemd daemon"
    systemctl enable protonvpn-split-tunnel.service || error_exit "Failed to enable service"
    
    log "Systemd services installed and enabled"
}

# Start the service
start_service() {
    log "Starting ProtonVPN split tunnel service..."
    systemctl start protonvpn-split-tunnel.service || error_exit "Failed to start service"
    log "Service started successfully"
}

# Main installation function
main() {
    log "Starting ProtonVPN split tunnel installation..."
    
    check_root
    validate_files
    create_directories
    check_config
    install_scripts
    install_services
    start_service
    
    log "ProtonVPN split tunnel setup complete!"
    log "Service status: $(systemctl is-active protonvpn-split-tunnel.service)"
}

# Run main function
main "$@"