#!/bin/bash
# /usr/local/bin/protonvpn-split-tunnel-remove.sh
#
# Removes route exclusions for ProtonVPN that were previously added.
# This script cleans up all configured exclusion routes.

set -euo pipefail

# Constants
readonly CONFIG_FILE="/usr/local/etc/protonvpn-split-tunnel.conf"

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
        log_warn "No exclusions defined in ${CONFIG_FILE}"
        return 1
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
        log_warn "No valid exclusions found after sanitization"
        return 1
    fi
    
    log_info "Loaded ${#EXCLUSIONS[@]} exclusion(s) from configuration"
    return 0
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

# Remove a single route exclusion
remove_route_exclusion() {
    local exclusion="$1"
    
    if ! validate_exclusion "${exclusion}"; then
        return 1
    fi
    
    log_info "Removing exclusion for ${exclusion}"
    
    # Extract IP address (remove CIDR notation if present)
    local ip_only="${exclusion%/*}"
    
    # Check if route exists (try both formats)
    local route_info
    route_info=$(ip route show "${exclusion}" 2>/dev/null || ip route show "${ip_only}" 2>/dev/null || true)
    
    if [[ -z "${route_info}" ]]; then
        log_info "No route found for ${exclusion} (already removed or never existed)"
        return 0
    fi
    
    log_info "Found route: ${route_info}"
    
    # Try to delete the route (try both formats)
    local delete_success=false
    local delete_output
    
    # First try with original format
    if delete_output=$(ip route del "${exclusion}" 2>&1); then
        delete_success=true
        log_info "✓ Successfully removed route for ${exclusion}"
    else
        # Try with IP only format
        if delete_output=$(ip route del "${ip_only}" 2>&1); then
            delete_success=true
            log_info "✓ Successfully removed route for ${exclusion} (using IP format)"
        fi
    fi
    
    if [[ "${delete_success}" == "true" ]]; then
        return 0
    else
        log_error "✗ Failed to remove route for ${exclusion}"
        log_error "Last error: ${delete_output}"
        return 1
    fi
}

# Main function
main() {
    local success_count=0
    local total_count=0
    
    log_info "Starting ProtonVPN split tunnel cleanup..."
    
    if ! load_config; then
        log_info "No exclusions to remove"
        exit 0
    fi
    
    for exclusion in "${EXCLUSIONS[@]}"; do
        total_count=$((total_count + 1))
        if remove_route_exclusion "${exclusion}"; then
            success_count=$((success_count + 1))
        else
            log_warn "Failed to remove route for ${exclusion}"
        fi
    done
    
    log_info "ProtonVPN split tunnel cleanup complete: ${success_count}/${total_count} routes removed successfully"
    
    if [[ ${success_count} -ne ${total_count} ]]; then
        exit 1
    fi
}

# Run main function
main "$@"
