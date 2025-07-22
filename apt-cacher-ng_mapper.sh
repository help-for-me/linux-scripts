#!/bin/bash
#
# install-apt-cacher-dialog.sh
#
# This script configures APT to use apt-cacher-ng as a proxy for HTTP downloads.
# If the server is unreachable, the user can choose to proceed without proxy (fallback).
#
# Usage (as root):
#   sudo ./install-apt-cacher-dialog.sh

set -e

# Check if running as root.
if [[ "$EUID" -ne 0 ]]; then
    dialog --msgbox "This installer must be run as root. Please run with sudo or as root." 8 50
    exit 1
fi

# Display introduction.
dialog --msgbox "APT Cacher NG Installer\n\nThis script will configure APT to use apt-cacher-ng as a proxy for HTTP downloads." 10 60

# Ask if the user wants to upgrade packages after setup.
dialog --yesno "Would you like to update and upgrade your packages once everything is set up?" 8 60
DO_UPGRADE=$([[ $? -eq 0 ]] && echo "true" || echo "false")

# Function to test APT Cacher NG availability.
test_apt_cacher() {
    local ip=$1
    echo "Testing connection to APT Cacher NG at $ip:3142..." >&2

    if command -v nc &>/dev/null; then
        nc -z -w3 "$ip" 3142 && return 0
    fi

    if command -v curl &>/dev/null; then
        local response
        response=$(curl -s -o /dev/null -w "%{http_code}" "http://$ip:3142/")
        [[ "$response" == "200" || "$response" == "406" ]] && return 0
    fi

    if command -v telnet &>/dev/null; then
        echo "quit" | timeout 5 telnet "$ip" 3142 2>&1 | grep -q "Connected" && return 0
    fi

    return 1
}

# Prompt for the apt-cacher-ng server IP address.
while true; do
    APTCACHER_IP=$(dialog --stdout --inputbox "Enter the IP address of your apt-cacher-ng server (e.g. 192.168.1.100):" 8 60)

    # Cancelled or empty input
    if [[ -z "$APTCACHER_IP" ]]; then
        dialog --msgbox "No IP address provided. Installation cancelled." 6 40
        clear
        exit 1
    fi

    # Warn if IP doesn't look valid
    if [[ ! "$APTCACHER_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        dialog --yesno "The IP address doesn't match a typical IPv4 format.\n\nContinue anyway?" 8 60
        [[ $? -ne 0 ]] && continue
    fi

    # Try to connect
    if test_apt_cacher "$APTCACHER_IP"; then
        dialog --msgbox "Successfully connected to apt-cacher-ng on $APTCACHER_IP:3142." 6 60
        USE_PROXY=true
        break
    else
        dialog --yesno --title "Connection Failed" --yes-label "Fallback to Direct APT" --no-label "Retry" \
        "Could not connect to apt-cacher-ng on $APTCACHER_IP:3142.\n\nWould you like to skip proxy configuration and continue with direct APT downloads?" 10 60
        if [[ $? -eq 0 ]]; then
            USE_PROXY=false
            break
        fi
    fi
done

APT_CONF_FILE="/etc/apt/apt.conf.d/01apt-cacher-ng"

# If using proxy, write the configuration
if [[ "$USE_PROXY" == true ]]; then
    if [[ -f "$APT_CONF_FILE" ]]; then
        dialog --msgbox "Backing up existing configuration file to ${APT_CONF_FILE}.bak" 6 60
        cp "$APT_CONF_FILE" "${APT_CONF_FILE}.bak"
    fi

    cat <<EOF > "$APT_CONF_FILE"
Acquire::http::Proxy "http://$APTCACHER_IP:3142";
EOF

    dialog --msgbox "APT is now configured to use APT Cacher NG at http://$APTCACHER_IP:3142 for package downloads." 8 60
else
    if [[ -f "$APT_CONF_FILE" ]]; then
        dialog --msgbox "Removing existing proxy config so APT will use direct internet access." 6 60
        rm -f "$APT_CONF_FILE"
    fi
    dialog --msgbox "APT will use direct access with no proxy." 6 50
fi

# Optional package update
if [[ "$DO_UPGRADE" == "true" ]]; then
    dialog --infobox "Updating package list..." 4 50
    apt update
    dialog --infobox "Upgrading packages..." 4 50
    apt upgrade -y
    dialog --msgbox "Packages updated and upgraded." 6 40
fi

dialog --msgbox "Installation complete.\nYou can modify or remove the APT proxy at ${APT_CONF_FILE} if needed." 8 60
clear