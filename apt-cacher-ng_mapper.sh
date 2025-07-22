#!/bin/bash
#
# install-apt-cacher-dialog.sh
#
# This script configures APT to use apt-cacher-ng as a proxy.
# If the server is unreachable, it offers to fall back to direct APT.
# If a proxy is already configured, the user can choose to keep or change it.

set -e

APT_CONF_FILE="/etc/apt/apt.conf.d/01apt-cacher-ng"

# Ensure root privileges
if [[ "$EUID" -ne 0 ]]; then
    dialog --msgbox "This installer must be run as root. Please run with sudo or as root." 8 50
    exit 1
fi

# Welcome message
dialog --msgbox "APT Cacher NG Installer\n\nThis script configures APT to use apt-cacher-ng as a proxy server for package downloads." 10 60

# Check for existing config
if [[ -f "$APT_CONF_FILE" ]]; then
    CURRENT_PROXY=$(grep -oP 'http://\K[^"]+' "$APT_CONF_FILE" || true)
    dialog --yesno --title "Existing Proxy Found" \
        "APT is already configured to use the following proxy:\n\n$CURRENT_PROXY\n\nWould you like to change it?" 10 60

    if [[ $? -ne 0 ]]; then
        dialog --msgbox "No changes made. APT will continue using the existing proxy:\n\n$CURRENT_PROXY" 8 60
        clear
        exit 0
    fi
fi

# Ask if the user wants to upgrade packages later
dialog --yesno "Would you like to update and upgrade your packages after configuration?" 8 60
DO_UPGRADE=$([[ $? -eq 0 ]] && echo "true" || echo "false")

# Function to test apt-cacher-ng server
test_apt_cacher() {
    local ip=$1

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

# Prompt for new apt-cacher-ng server IP
while true; do
    APTCACHER_IP=$(dialog --stdout --inputbox "Enter the IP address of your apt-cacher-ng server (e.g. 192.168.1.100):" 8 60)

    if [[ -z "$APTCACHER_IP" ]]; then
        dialog --msgbox "No IP address provided. Installation cancelled." 6 40
        clear
        exit 1
    fi

    if [[ ! "$APTCACHER_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        dialog --yesno "The IP address doesn't match a typical IPv4 format.\n\nContinue anyway?" 8 60
        [[ $? -ne 0 ]] && continue
    fi

    if test_apt_cacher "$APTCACHER_IP"; then
        dialog --msgbox "Successfully connected to apt-cacher-ng at $APTCACHER_IP:3142." 6 60
        USE_PROXY=true
        break
    else
        dialog --yesno --title "Connection Failed" --yes-label "Use Direct APT" --no-label "Retry" \
        "Could not connect to apt-cacher-ng at $APTCACHER_IP:3142.\n\nFallback to direct APT instead?" 10 60
        [[ $? -eq 0 ]] && USE_PROXY=false && break
    fi
done

# Apply configuration
if [[ "$USE_PROXY" == true ]]; then
    [[ -f "$APT_CONF_FILE" ]] && cp "$APT_CONF_FILE" "${APT_CONF_FILE}.bak"
    cat <<EOF > "$APT_CONF_FILE"
Acquire::http::Proxy "http://$APTCACHER_IP:3142";
EOF
    dialog --msgbox "APT is now configured to use apt-cacher-ng at http://$APTCACHER_IP:3142." 8 60
else
    [[ -f "$APT_CONF_FILE" ]] && rm -f "$APT_CONF_FILE"
    dialog --msgbox "APT is now configured to use direct access (no proxy)." 6 50
fi

# Optional upgrade
if [[ "$DO_UPGRADE" == "true" ]]; then
    dialog --infobox "Running apt update..." 4 50
    apt update
    dialog --infobox "Running apt upgrade..." 4 50
    apt upgrade -y
    dialog --msgbox "Packages have been updated and upgraded." 6 50
fi

# Wrap up
dialog --msgbox "Installation complete.\nYou can modify or remove the APT proxy at:\n\n$APT_CONF_FILE" 8 60
clear