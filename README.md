# ProtonVPN Split Tunneling for Linux

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell](https://img.shields.io/badge/Shell-Bash-green.svg)](https://www.gnu.org/software/bash/)

Automated bash scripts for implementing split tunneling with ProtonVPN on Linux. This solution allows you to exclude specific IP addresses or network ranges from going through the VPN tunnel, routing them directly through your regular internet connection instead.

Split tunneling is a feature built-in to ProtonVPN on all other platforms, but unfortunately Proton have not prioritised implementing it for Linux, so this is my attempt to provide a workaround.

## 🚀 Features

- **Automatic Detection**: Monitors ProtonVPN connection status and applies exclusions automatically
- **Network Resilience**: Re-applies exclusions after system wake from suspension or network changes
- **Robust Monitoring**: Handles manual VPN restarts and connection interruptions
- **Headless Compatible**: Works on servers and headless systems with no desktop environment required
- **Systemd Integration**: Runs as a system service with proper logging and error handling
- **Configurable**: Easy-to-modify configuration file for managing exclusions

## 📋 Requirements

- Linux system with systemd
- ProtonVPN client installed and configured
- Root/sudo access for installation
- `ip`, `pgrep`, and `logger` utilities (typically pre-installed)

## ⚙️ Configuration

The configuration file is located at `/usr/local/etc/protonvpn-split-tunnel.conf` and must be created before installation.

It must contain an `EXCLUSIONS` variable defining an array of the IP addresses/networks you want to exclude from the VPN tunnel.

### Configuration Example

```bash
EXCLUSIONS=(
    "192.168.1.10/32"    # Single IP (local printer)
    "192.168.1.0/24"     # Entire local network
    "10.0.0.100/32"      # Work server
    "203.0.113.0/24"     # External service network
)
```

## ⚡ Installation

### Step 1: Clone and Prepare
```bash
git clone https://github.com/harryd337/protonvpn-linux-split-tunneling.git
cd protonvpn-linux-split-tunneling
chmod +x install.sh
```

### Step 2: Configure Your Split Tunnel Routes
**⚠️ Important: You must create your configuration file before running the installer.**

```bash
# Copy the example configuration
sudo cp config/protonvpn-split-tunnel.conf.example /usr/local/etc/protonvpn-split-tunnel.conf

# Edit the configuration file
sudo nano /usr/local/etc/protonvpn-split-tunnel.conf
```

**Configure your exclusions by editing the `EXCLUSIONS` array:**
```bash
EXCLUSIONS=(
    "192.168.1.10/32"    # Your local printer
    "192.168.1.0/24"     # Your entire local network
    # Add your specific IPs/networks here
)
```

### Step 3: Run the Installer
```bash
sudo ./install.sh
```

The installer will:
1. Verify your configuration file exists
2. Copy scripts to `/usr/local/bin/`
3. Set up systemd services
4. Enable and start the monitoring service

## 🔧 Manual Usage

### Start/Stop the Service

```bash
# Start the split tunnel service
sudo systemctl start protonvpn-split-tunnel.service

# Stop the split tunnel service
sudo systemctl stop protonvpn-split-tunnel.service

# Check service status
sudo systemctl status protonvpn-split-tunnel.service
```

### Remove All Routes (Clean Slate)

```bash
# Stop the split tunnel service
sudo systemctl stop protonvpn-split-tunnel.service

# Remove all existing exclusion routes
sudo /usr/local/bin/protonvpn-split-tunnel-remove.sh
```

### Manual Script Execution

```bash
# Apply exclusions manually
sudo /usr/local/bin/protonvpn-split-tunnel-add.sh

# Remove exclusions manually
sudo /usr/local/bin/protonvpn-split-tunnel-remove.sh
```

### View Logs

```bash
# View real-time logs
sudo journalctl -u protonvpn-split-tunnel.service -f

# View recent logs
sudo journalctl -u protonvpn-split-tunnel.service -n 50

# Enable debug logging (temporary for current session)
sudo systemctl stop protonvpn-split-tunnel.service
sudo DEBUG=1 /usr/local/bin/protonvpn-split-tunnel-monitor.sh

# Or enable debug logging permanently by editing the service
sudo systemctl edit protonvpn-split-tunnel.service
# Add the following lines:
# [Service]
# Environment="DEBUG=1"
# Then restart: sudo systemctl restart protonvpn-split-tunnel.service
```

## 🔄 Uninstallation

### Automated Uninstall (Recommended)

Use the provided uninstall script for safe and complete removal:

```bash
chmod +x uninstall.sh
sudo ./uninstall.sh
```

The uninstall script will:
- ✅ Stop and disable the systemd service
- ✅ Clean up any existing split tunnel routes
- ✅ Remove all installed scripts and service files
- ✅ Optionally preserve your configuration file
- ✅ Reload systemd daemon

### Manual Uninstall

If you prefer to remove components manually:

```bash
# Stop and disable service
sudo systemctl stop protonvpn-split-tunnel.service
sudo systemctl disable protonvpn-split-tunnel.service

# Clean up routes (optional - run the removal script first)
sudo /usr/local/bin/protonvpn-split-tunnel-remove.sh

# Remove files
sudo rm -f /usr/local/bin/protonvpn-split-tunnel-add.sh
sudo rm -f /usr/local/bin/protonvpn-split-tunnel-remove.sh
sudo rm -f /usr/local/bin/protonvpn-split-tunnel-monitor.sh
sudo rm -f /usr/local/etc/protonvpn-split-tunnel.conf
sudo rm -f /etc/systemd/system/protonvpn-split-tunnel.service

# Reload systemd
sudo systemctl daemon-reload
```

## 📁 Project Structure

```
protonvpn-linux-split-tunneling/
├── scripts/                                    # Main executable scripts
│   ├── protonvpn-split-tunnel-add.sh         # Adds route exclusions
│   ├── protonvpn-split-tunnel-remove.sh      # Removes route exclusions
│   └── protonvpn-split-tunnel-monitor.sh     # Main monitoring daemon
├── config/                                     # Configuration templates
│   └── protonvpn-split-tunnel.conf.example   # Example configuration
├── systemd/                                    # Systemd service files
│   └── protonvpn-split-tunnel.service        # Main monitoring service
└── install.sh                                 # Installation script
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

### Development

- Follow bash best practices and shellcheck recommendations
- Test on multiple Linux distributions
- Update documentation for any new features
- Ensure backward compatibility

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## ⚠️ Disclaimer

This software is provided as-is. Use at your own risk. Always test in a safe environment before deploying to production systems.

## 🙏 Acknowledgments

- ProtonVPN team for their excellent VPN service
- Linux networking community for routing documentation
- Contributors and users who provide feedback and improvements
