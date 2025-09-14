#!/bin/bash
# dev-test.sh - Development and testing script
#
# This script provides various testing and development utilities for the
# ProtonVPN exclusions system.

set -euo pipefail

# Constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Show usage information
show_usage() {
    cat << EOF
Usage: $0 [COMMAND]

Development and testing utilities for ProtonVPN exclusions system.

Commands:
  syntax-check    Check all scripts for syntax errors
  test-config     Test configuration file loading
  show-routes     Display current routing table
  show-vpn        Show VPN connection status
  show-exclusions Show configured exclusions
  simulate-add    Simulate adding exclusions (dry run)
  help           Show this help message

Examples:
  $0 syntax-check
  $0 test-config
  $0 show-routes | grep -E "(default|192\.168)"
EOF
}

# Check syntax of all bash scripts
syntax_check() {
    log_info "Checking syntax of all bash scripts..."
    
    local scripts=(
        "install.sh"
        "uninstall.sh"
        "scripts/protonvpn-split-tunnel-add.sh"
        "scripts/protonvpn-split-tunnel-remove.sh"
        "scripts/protonvpn-split-tunnel-monitor.sh"
        "config/protonvpn-split-tunnel.conf"
        "config/protonvpn-split-tunnel.conf.example"
        "systemd/protonvpn-split-tunnel.service"
    )
    
    local error_count=0
    
    for script in "${scripts[@]}"; do
        local script_path="${SCRIPT_DIR}/${script}"
        if [[ -f "${script_path}" ]]; then
            if bash -n "${script_path}"; then
                log_info "✓ ${script}"
            else
                log_error "✗ ${script}"
                ((error_count++))
            fi
        else
            log_warn "? ${script} (not found)"
        fi
    done
    
    if [[ ${error_count} -eq 0 ]]; then
        log_info "All scripts passed syntax check!"
    else
        log_error "${error_count} script(s) failed syntax check"
        return 1
    fi
}

# Test configuration loading
test_config() {
    log_info "Testing configuration file loading..."
    
    local config_file="/usr/local/etc/protonvpn-split-tunnel.conf"
    
    if [[ ! -f "${config_file}" ]]; then
        log_error "Configuration file not found: ${config_file}"
        return 1
    fi
    
    if (
        # shellcheck source=/dev/null
        source "${config_file}"
        
        if [[ -z "${EXCLUSIONS:-}" ]]; then
            echo "ERROR: EXCLUSIONS variable not defined"
            exit 1
        fi
        
        if [[ ${#EXCLUSIONS[@]} -eq 0 ]]; then
            echo "WARNING: EXCLUSIONS array is empty"
            exit 2
        fi
        
        echo "INFO: Found ${#EXCLUSIONS[@]} exclusion(s):"
        for exclusion in "${EXCLUSIONS[@]}"; do
            echo "  - ${exclusion}"
        done
    ); then
        log_info "✓ Configuration loaded successfully"
    else
        local exit_code=$?
        if [[ ${exit_code} -eq 2 ]]; then
            log_warn "Configuration loaded but EXCLUSIONS array is empty"
        else
            log_error "Failed to load configuration"
            return 1
        fi
    fi
}

# Show current routing table
show_routes() {
    log_info "Current routing table:"
    echo ""
    ip route show | while read -r route; do
        if [[ "${route}" =~ default ]]; then
            echo -e "${GREEN}${route}${NC}"
        elif [[ "${route}" =~ 192\.168\.|10\.|172\. ]]; then
            echo -e "${YELLOW}${route}${NC}"
        else
            echo "${route}"
        fi
    done
}

# Show VPN connection status
show_vpn() {
    log_info "VPN connection status:"
    echo ""
    
    echo "ProtonVPN processes:"
    if pgrep -f "protonvpn" >/dev/null 2>&1; then
        pgrep -af "protonvpn" || true
    else
        echo "  No ProtonVPN processes found"
    fi
    
    echo ""
    
    echo "VPN interfaces:"
    local found_interface=false
    for interface in proton0 tun0; do
        if ip link show "${interface}" >/dev/null 2>&1; then
            ip link show "${interface}"
            found_interface=true
        fi
    done
    
    if [[ "${found_interface}" == "false" ]]; then
        echo "  No VPN interfaces found"
    fi
}

# Show configured exclusions
show_exclusions() {
    log_info "Configured exclusions:"
    echo ""
    
    local config_file="/usr/local/etc/protonvpn-split-tunnel.conf"
    
    if [[ -f "${config_file}" ]]; then
        (
            # shellcheck source=/dev/null
            source "${config_file}"
            
            if [[ -n "${EXCLUSIONS:-}" && ${#EXCLUSIONS[@]} -gt 0 ]]; then
                for exclusion in "${EXCLUSIONS[@]}"; do
                    echo "  ${exclusion}"
                    
                    if ip route show "${exclusion}" >/dev/null 2>&1; then
                        echo -e "    ${GREEN}✓ Route exists${NC}"
                    else
                        echo -e "    ${RED}✗ Route not found${NC}"
                    fi
                done
            else
                echo "  No exclusions configured"
            fi
        )
    else
        log_error "Configuration file not found: ${config_file}"
    fi
}

# Simulate adding exclusions (dry run)
simulate_add() {
    log_info "Simulating exclusion addition (dry run)..."
    echo ""
    
    local route gateway interface
    route=$(ip route show default | grep -v 'tun0\|proton0' | head -n1)
    
    if [[ -z "${route}" ]]; then
        log_error "No non-VPN default route found"
        return 1
    fi
    
    gateway=$(echo "${route}" | awk '{print $3}')
    interface=$(echo "${route}" | awk '{print $5}')
    
    log_info "Would use gateway: ${gateway}, interface: ${interface}"
    
    local config_file="/usr/local/etc/protonvpn-split-tunnel.conf"
    
    if [[ -f "${config_file}" ]]; then
        (
            # shellcheck source=/dev/null
            source "${config_file}"
            
            if [[ -n "${EXCLUSIONS:-}" && ${#EXCLUSIONS[@]} -gt 0 ]]; then
                for exclusion in "${EXCLUSIONS[@]}"; do
                    echo "Would execute: ip route add ${exclusion} via ${gateway} dev ${interface}"
                done
            else
                echo "No exclusions to add"
            fi
        )
    else
        log_error "Configuration file not found: ${config_file}"
    fi
}

# Main function
main() {
    case "${1:-help}" in
        syntax-check)
            syntax_check
            ;;
        test-config)
            test_config
            ;;
        show-routes)
            show_routes
            ;;
        show-vpn)
            show_vpn
            ;;
        show-exclusions)
            show_exclusions
            ;;
        simulate-add)
            simulate_add
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            log_error "Unknown command: $1"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
