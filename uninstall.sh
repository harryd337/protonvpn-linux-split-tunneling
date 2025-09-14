#!/bin/bash
# uninstall.sh - Uninstallation script for ProtonVPN split tunneling
#
# This script removes all components of the ProtonVPN split tunnel system:
# - Stops and disables systemd services
# - Removes installed scripts and configuration files
# - Cleans up systemd service files

set -euo pipefail

# Constants
readonly BIN_DIR="/usr/local/bin"
readonly ETC_DIR="/usr/local/etc"
readonly SYSTEMD_DIR="/etc/systemd/system"
readonly SERVICE_NAME="protonvpn-split-tunnel.service"

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

# Stop and disable services
stop_services() {
    log "Stopping and disabling services..."
    
    if systemctl is-active --quiet "${SERVICE_NAME}"; then
        systemctl stop "${SERVICE_NAME}" || log "Warning: Failed to stop ${SERVICE_NAME}"
        log "Stopped ${SERVICE_NAME}"
    fi
    
    if systemctl is-enabled --quiet "${SERVICE_NAME}" 2>/dev/null; then
        systemctl disable "${SERVICE_NAME}" || log "Warning: Failed to disable ${SERVICE_NAME}"
        log "Disabled ${SERVICE_NAME}"
    fi
}

# Remove scripts
remove_scripts() {
    log "Removing scripts..."
    
    local scripts=(
        "protonvpn-split-tunnel-add.sh"
        "protonvpn-split-tunnel-remove.sh"
        "protonvpn-split-tunnel-monitor.sh"
    )
    
    for script in "${scripts[@]}"; do
        local script_path="${BIN_DIR}/${script}"
        if [[ -f "${script_path}" ]]; then
            rm -f "${script_path}" || log "Warning: Failed to remove ${script_path}"
            log "Removed ${script_path}"
        fi
    done
}

# Remove configuration files
remove_config() {
    log "Removing configuration files..."
    
    local config_file="${ETC_DIR}/protonvpn-split-tunnel.conf"
    if [[ -f "${config_file}" ]]; then
        echo "Configuration file found: ${config_file}"
        read -p "Do you want to remove the configuration file? [y/N]: " -r response
        if [[ "${response,,}" =~ ^y(es)?$ ]]; then
            rm -f "${config_file}" || log "Warning: Failed to remove ${config_file}"
            log "Removed ${config_file}"
        else
            log "Kept configuration file: ${config_file}"
        fi
    fi
}

# Remove systemd service files
remove_services() {
    log "Removing systemd service files..."
    
    local services=(
        "${SERVICE_NAME}"
    )
    
    for service in "${services[@]}"; do
        local service_path="${SYSTEMD_DIR}/${service}"
        if [[ -f "${service_path}" ]]; then
            rm -f "${service_path}" || log "Warning: Failed to remove ${service_path}"
            log "Removed ${service_path}"
        fi
    done
    
    systemctl daemon-reload || log "Warning: Failed to reload systemd daemon"
    log "Reloaded systemd daemon"
}

# Clean up any remaining routes
cleanup_routes() {
    log "Attempting to clean up any remaining split tunnel routes..."
    
    local remove_script="${BIN_DIR}/protonvpn-split-tunnel-remove.sh"
    if [[ -x "${remove_script}" ]]; then
        "${remove_script}" || log "Warning: Failed to clean up routes"
    else
        log "Remove script not found, skipping route cleanup"
    fi
}

# Main uninstallation function
main() {
    log "Starting ProtonVPN split tunnel uninstallation..."
    
    check_root
    stop_services
    cleanup_routes
    remove_scripts
    remove_config
    remove_services
    
    log "ProtonVPN split tunnel uninstallation complete!"
    log ""
    log "All components have been removed from your system."
    log "If you kept the configuration file, you can find it at:"
    log "  ${ETC_DIR}/protonvpn-split-tunnel.conf"
}

# Run main function
main "$@"
