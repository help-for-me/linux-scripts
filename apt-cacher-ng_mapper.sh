#!/bin/bash
#
# install-apt-cacher.sh
#
# This script configures APT to use apt-cacher-ng as a proxy for HTTP downloads.
# It asks at the very beginning if you would like to update and upgrade your packages.
# Then it prompts for the IP address of the apt-cacher-ng server and creates an
# APT configuration file to use the proxy.
#
# Usage (as root):
#   curl -sSL https://raw.githubusercontent.com/yourusername/yourrepo/main/install-apt-cacher.sh | sudo bash

set -e

# Ensure the script is running as root.
if [[ "$EUID" -ne 0 ]]; then
    echo "This installer must be run as root. Please run with sudo or as root."
    exit 1
fi

# Ask the user if they want to update and upgrade packages.
# The default response is Yes if the user presses Enter.
read -p "Would you like to update and upgrade your packages now? [Y/n]: " UPGRADE_CHOICE
if [[ -z "$UPGRADE_CHOICE" || "$UPGRADE_CHOICE" =~ ^[Yy]$ ]]; then
    DO_UPGRADE=true
else
    DO_UPGRADE=false
fi

echo
echo "APT Cacher NG Installer"
echo "------------------------"
echo "This script will configure APT to use apt-cacher-ng as a proxy for HTTP downloads."
echo

# Prompt the user for the apt-cacher-ng server IP address.
read -p "Enter the IP address of your apt-cacher-ng server (e.g. 192.168.1.100): " APTCACHER_IP

# (Optional) Validate the IP address format.
if [[ ! "$APTCACHER_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    echo "Warning: The entered IP address does not match a typical IPv4 format."
    read -p "Do you want to continue anyway? [y/N]: " CONTINUE
    if [[ "$CONTINUE" != "y" && "$CONTINUE" != "Y" ]]; then
        echo "Aborting installer."
        exit 1
    fi
fi

# Define the target APT configuration file.
APT_CONF_FILE="/etc/apt/apt.conf.d/01apt-cacher-ng"

# Backup any existing configuration file.
if [[ -f "$APT_CONF_FILE" ]]; then
    echo "Backing up existing configuration file to ${APT_CONF_FILE}.bak"
    cp "$APT_CONF_FILE" "${APT_CONF_FILE}.bak"
fi

# Write the configuration.
cat <<EOF > "$APT_CONF_FILE"
Acquire::http::Proxy "http://$APTCACHER_IP:3142";
EOF

echo
echo "Configuration written to $APT_CONF_FILE."
echo "APT will now attempt to use apt-cacher-ng at http://$APTCACHER_IP:3142 for HTTP downloads."

# (Optional) Test connectivity to the apt-cacher-ng proxy.
if command -v nc &>/dev/null; then
    if nc -z "$APTCACHER_IP" 3142; then
        echo "Successfully connected to apt-cacher-ng on $APTCACHER_IP:3142."
    else
        echo "Warning: Could not connect to apt-cacher-ng on $APTCACHER_IP:3142."
        echo "Ensure that the proxy is running and reachable, or remove the configuration file to disable the proxy."
    fi
else
    echo "Note: 'nc' (netcat) is not installed. Skipping connectivity test."
fi

echo

# Run update and upgrade if requested.
if [ "$DO_UPGRADE" = true ]; then
    echo "Updating package list..."
    apt update
    echo "Upgrading packages..."
    apt upgrade -y
    echo "Packages updated and upgraded."
fi

echo
echo "Installation complete. If you encounter issues with apt, you can remove or modify $APT_CONF_FILE."
