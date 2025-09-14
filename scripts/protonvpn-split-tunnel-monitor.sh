#!/bin/bash
# /usr/local/bin/protonvpn-split-tunnel-monitor.sh
#
# Monitors ProtonVPN connection status and automatically applies/removes route exclusions.
# This script runs continuously and handles:
# - VPN connection state changes
# - Network interface changes after suspend/resume
# - Automatic re-application of exclusions when missing

set -euo pipefail

# Constants
readonly CONFIG_FILE="/usr/local/etc/protonvpn-split-tunnel.conf"
readonly ADD_EXCLUSIONS_SCRIPT="/usr/local/bin/protonvpn-split-tunnel-add.sh"
readonly VPN_CHECK_INTERVAL_CONNECTED=30
readonly VPN_CHECK_INTERVAL_DISCONNECTED=5
readonly MAX_CONSECUTIVE_FAILURES=3

# Global state variables
previous_vpn_state="false"
exclusions_applied="false"
consecutive_failures=0

# Logging functions
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*" >&2
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $*" >&2
}

log_debug() {
    # Only log debug messages if DEBUG environment variable is set
    if [[ "${DEBUG:-}" == "1" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] DEBUG: $*" >&2
    fi
}

# Load configuration for exclusion checking
load_config() {
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        log_error "Configuration file not found: ${CONFIG_FILE}"
        return 1
    fi
    
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}"
    
    if [[ -z "${EXCLUSIONS:-}" ]] || [[ ${#EXCLUSIONS[@]} -eq 0 ]]; then
        log_warn "No exclusions defined in ${CONFIG_FILE}"
        return 1
    fi
    
    return 0
}

# Apply exclusions by calling the dedicated script
apply_exclusions() {
    log_info "Applying ProtonVPN split tunnel routes..."
    
    if [[ ! -x "${ADD_EXCLUSIONS_SCRIPT}" ]]; then
        log_error "Add exclusions script not found or not executable: ${ADD_EXCLUSIONS_SCRIPT}"
        return 1
    fi
    
    if "${ADD_EXCLUSIONS_SCRIPT}"; then
        log_info "Exclusions applied successfully"
        consecutive_failures=0
        return 0
    else
        consecutive_failures=$((consecutive_failures + 1))
        log_error "Failed to apply exclusions (failure ${consecutive_failures}/${MAX_CONSECUTIVE_FAILURES})"
        
        if [[ ${consecutive_failures} -ge ${MAX_CONSECUTIVE_FAILURES} ]]; then
            log_error "Maximum consecutive failures reached. Service may need manual intervention."
            # Reset counter to avoid spam
            consecutive_failures=0
        fi
        return 1
    fi
}

# Check if ProtonVPN is running by looking for the process and interface
is_protonvpn_running() {
    local vpn_process_found=false
    
    # Look for specific ProtonVPN processes (more restrictive)
    if pgrep -x "protonvpn" >/dev/null 2>&1 || \
       pgrep -x "protonvpn-cli" >/dev/null 2>&1 || \
       pgrep -x "proton-vpn" >/dev/null 2>&1 || \
       pgrep -x "protonvpn-app" >/dev/null 2>&1 || \
       pgrep -f "protonvpn.*connect" >/dev/null 2>&1; then
        vpn_process_found=true
    fi
    
    local vpn_interface_found=false
    
    # Check for VPN interfaces and routes
    if ip link show proton0 >/dev/null 2>&1 || \
       ip link show tun0 >/dev/null 2>&1 || \
       ip route show | grep -E "tun0|proton0" | grep -v "192.168\|10\.|172\." >/dev/null 2>&1; then
        vpn_interface_found=true
    fi
    
    # Additional check: Look for VPN-specific routing changes
    local vpn_routes_found=false
    if ip route show default | grep -E "tun0|proton0" >/dev/null 2>&1; then
        vpn_routes_found=true
    fi
    
    if [[ "${vpn_process_found}" == "true" && ("${vpn_interface_found}" == "true" || "${vpn_routes_found}" == "true") ]]; then
        log_debug "ProtonVPN detected as running (process: ${vpn_process_found}, interface: ${vpn_interface_found}, routes: ${vpn_routes_found})"
        return 0
    else
        log_debug "ProtonVPN not detected (process: ${vpn_process_found}, interface: ${vpn_interface_found}, routes: ${vpn_routes_found})"
        return 1
    fi
}

# Check if exclusions are properly applied
are_exclusions_applied() {
    if ! load_config; then
        return 1
    fi
    
    local route gateway interface
    route=$(ip route show default | grep -v 'tun0\|proton0' | head -n1)
    
    if [[ -z "${route}" ]]; then
        log_debug "No non-VPN default route found"
        return 1
    fi
    
    gateway=$(echo "${route}" | awk '{print $3}')
    interface=$(echo "${route}" | awk '{print $5}')
    
    if [[ -z "${gateway}" || -z "${interface}" ]]; then
        log_debug "Could not determine gateway (${gateway}) or interface (${interface})"
        return 1
    fi
    
    for exclusion in "${EXCLUSIONS[@]}"; do
        if ! ip route show "${exclusion}" | grep -q "via ${gateway} dev ${interface}"; then
            log_debug "Missing exclusion route for ${exclusion}"
            return 1
        fi
    done
    
    log_debug "All exclusions are properly applied"
    return 0
}

# Handle VPN state changes
handle_vpn_state_change() {
    local current_state="$1"
    
    if [[ "${current_state}" == "true" ]]; then
        if [[ "${previous_vpn_state}" == "false" ]]; then
            log_info "ProtonVPN started - applying split tunnel routes"
            if apply_exclusions; then
                exclusions_applied="true"
            else
                exclusions_applied="false"
            fi
        elif [[ "${exclusions_applied}" == "false" ]] || ! are_exclusions_applied; then
            log_info "ProtonVPN running but split tunnel routes missing - reapplying"
            if apply_exclusions; then
                exclusions_applied="true"
            else
                exclusions_applied="false"
            fi
        fi
    else
        if [[ "${previous_vpn_state}" == "true" ]]; then
            log_info "ProtonVPN stopped"
        fi
        exclusions_applied="false"
    fi
    
    previous_vpn_state="${current_state}"
}

# Signal handlers for graceful shutdown
cleanup() {
    log_info "Received shutdown signal - stopping monitor"
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT SIGQUIT

# Main monitoring loop
main() {
    log_info "Starting ProtonVPN split tunnel monitor (PID: $$)"
    log_info "Monitor intervals: connected=${VPN_CHECK_INTERVAL_CONNECTED}s, disconnected=${VPN_CHECK_INTERVAL_DISCONNECTED}s"
    
    previous_vpn_state="false"
    exclusions_applied="false"
    
    while true; do
        local current_vpn_state
        
        if is_protonvpn_running; then
            current_vpn_state="true"
        else
            current_vpn_state="false"
        fi
        
        handle_vpn_state_change "${current_vpn_state}"
        
        if [[ "${current_vpn_state}" == "true" ]]; then
            sleep ${VPN_CHECK_INTERVAL_CONNECTED}
        else
            sleep ${VPN_CHECK_INTERVAL_DISCONNECTED}
        fi
    done
}

# Run main function
main "$@"
