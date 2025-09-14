#!/bin/bash
# /usr/local/bin/protonvpn-split-tunnel-add.sh
#
# Adds route exclusions for ProtonVPN to bypass the VPN tunnel for specific IPs/networks.
# This script waits for network availability and then adds the configured exclusions.

set -euo pipefail

# Constants
readonly CONFIG_FILE="/usr/local/etc/protonvpn-split-tunnel.conf"
readonly MAX_NETWORK_WAIT_ATTEMPTS=6
readonly NETWORK_WAIT_INTERVAL=5

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

# Sanitize and validate a single exclusion entry
sanitize_exclusion() {
    local exclusion="$1"
    
    # Remove any potentially dangerous characters
    exclusion=$(echo "${exclusion}" | sed 's/[^0-9.\/]//g')
    
    # Ensure it's not empty after sanitization
    if [[ -z "${exclusion}" ]]; then
        return 1
    fi
    
    echo "${exclusion}"
    return 0
}

# Load and validate configuration
load_config() {
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        log_error "Configuration file not found: ${CONFIG_FILE}"
        exit 1
    fi
    
    # Check file permissions for security
    local file_perms
    file_perms=$(stat -c "%a" "${CONFIG_FILE}")
    if [[ "${file_perms}" != "644" && "${file_perms}" != "600" ]]; then
        log_warn "Configuration file has unusual permissions: ${file_perms}"
    fi
    
    # shellcheck source=/dev/null
    source "${CONFIG_FILE}"
    
    if [[ -z "${EXCLUSIONS:-}" ]] || [[ ${#EXCLUSIONS[@]} -eq 0 ]]; then
        log_error "No exclusions defined in ${CONFIG_FILE}"
        exit 1
    fi
    
    # Sanitize all exclusions
    local sanitized_exclusions=()
    for exclusion in "${EXCLUSIONS[@]}"; do
        local sanitized
        if sanitized=$(sanitize_exclusion "${exclusion}"); then
            sanitized_exclusions+=("${sanitized}")
        else
            log_warn "Skipping invalid exclusion after sanitization: ${exclusion}"
        fi
    done
    
    # Replace original array with sanitized version
    EXCLUSIONS=("${sanitized_exclusions[@]}")
    
    if [[ ${#EXCLUSIONS[@]} -eq 0 ]]; then
        log_error "No valid exclusions found after sanitization"
        exit 1
    fi
    
    log_info "Loaded ${#EXCLUSIONS[@]} exclusion(s) from configuration"
}

# Wait for network to be available and get network parameters
get_network_parameters() {
    local gateway interface route
    
    for i in $(seq 1 ${MAX_NETWORK_WAIT_ATTEMPTS}); do
        if [[ ${i} -gt 1 ]]; then
            log_info "Waiting for network... attempt ${i}/${MAX_NETWORK_WAIT_ATTEMPTS}"
            sleep ${NETWORK_WAIT_INTERVAL}
        fi
        
        route=$(ip route show default | grep -v 'tun0\|proton0' | head -n1)
        
        if [[ -n "${route}" ]]; then
            gateway=$(echo "${route}" | awk '{print $3}')
            interface=$(echo "${route}" | awk '{print $5}')
            
            if [[ -n "${gateway}" && -n "${interface}" ]]; then
                echo "${gateway}" "${interface}"
                return 0
            fi
        fi
    done
    
    log_error "Could not determine gateway or interface after ${MAX_NETWORK_WAIT_ATTEMPTS} attempts"
    return 1
}

# Validate IP address or CIDR notation
validate_exclusion() {
    local exclusion="$1"
    local ip_part cidr_part=""
    
    # Handle empty input
    if [[ -z "${exclusion}" ]]; then
        log_warn "Empty exclusion provided"
        return 1
    fi
    
    # Split IP and CIDR if present
    if [[ "${exclusion}" == *"/"* ]]; then
        ip_part="${exclusion%/*}"
        cidr_part="${exclusion##*/}"
    else
        ip_part="${exclusion}"
    fi
    
    # Basic format check - should only contain numbers, dots, and slash
    if [[ ! "${exclusion}" =~ ^[0-9./]+$ ]]; then
        log_warn "Invalid characters in IP/CIDR format: ${exclusion}"
        return 1
    fi
    
    # Validate IP address octets
    IFS='.' read -r -a octets <<< "${ip_part}"
    if [[ ${#octets[@]} -ne 4 ]]; then
        log_warn "Invalid IP address format: ${ip_part} (must have 4 octets)"
        return 1
    fi
    
    for octet in "${octets[@]}"; do
        # Check if octet is a valid number
        if [[ ! "${octet}" =~ ^[0-9]+$ ]]; then
            log_warn "Invalid IP octet (not a number): ${octet} in ${ip_part}"
            return 1
        fi
        
        # Check for leading zeros (except for "0" itself)
        if [[ "${octet}" =~ ^0[0-9]+ ]]; then
            log_warn "IP octet has leading zeros: ${octet} in ${ip_part}"
            return 1
        fi
        
        # Check range (0-255)
        if [[ ${octet} -lt 0 ]] || [[ ${octet} -gt 255 ]]; then
            log_warn "Invalid IP octet range: ${octet} in ${ip_part} (must be 0-255)"
            return 1
        fi
    done
    
    # Validate CIDR if present
    if [[ -n "${cidr_part}" ]]; then
        if [[ ! "${cidr_part}" =~ ^[0-9]+$ ]]; then
            log_warn "Invalid CIDR notation (not a number): /${cidr_part}"
            return 1
        fi
        
        if [[ ${cidr_part} -lt 0 ]] || [[ ${cidr_part} -gt 32 ]]; then
            log_warn "Invalid CIDR range: /${cidr_part} (must be 0-32)"
            return 1
        fi
    fi
    
    return 0
}

# Add a single route exclusion
add_route_exclusion() {
    local exclusion="$1"
    local gateway="$2"
    local interface="$3"
    
    if ! validate_exclusion "${exclusion}"; then
        return 1
    fi
    
    log_info "Adding exclusion for ${exclusion}"
    
    if ip route show "${exclusion}" | grep -q "via ${gateway} dev ${interface}"; then
        log_info "Route for ${exclusion} already exists"
        return 0
    fi
    
    local add_output
    if add_output=$(ip route add "${exclusion}" via "${gateway}" dev "${interface}" 2>&1); then
        log_info "✓ Added route for ${exclusion} via ${gateway} dev ${interface}"
        return 0
    else
        local exit_code=$?
        # Check if route already exists (different error message)
        if [[ "${add_output}" =~ "File exists" ]]; then
            log_info "Route for ${exclusion} already exists (detected via error message)"
            return 0
        else
            log_error "✗ Failed to add route for ${exclusion}: ${add_output}"
            return ${exit_code}
        fi
    fi
}

# Main function
main() {
    local gateway interface network_params
    local success_count=0
    local total_count=0
    
    log_info "Starting ProtonVPN split tunnel setup..."
    
    load_config
    
    if ! network_params=$(get_network_parameters); then
        exit 1
    fi
    
    read -r gateway interface <<< "${network_params}"
    log_info "Using gateway: ${gateway}, interface: ${interface}"
    
    for exclusion in "${EXCLUSIONS[@]}"; do
        total_count=$((total_count + 1))
        if add_route_exclusion "${exclusion}" "${gateway}" "${interface}"; then
            success_count=$((success_count + 1))
        fi
    done
    
    log_info "ProtonVPN split tunnel setup complete: ${success_count}/${total_count} routes added successfully"
    
    if [[ ${success_count} -ne ${total_count} ]]; then
        exit 1
    fi
}

# Run main function
main "$@"
