#!/bin/bash
#
# install-apt-cacher-dialog.sh
#
# This script configures APT to use apt-cacher-ng as a proxy for HTTP downloads.
# It uses dialog boxes to interact with the user.
#
# It will:
#   - Ask if you want to update/upgrade packages.
#   - Prompt for the IP address of your apt-cacher-ng server.
#       * If left blank, the installer aborts.
#       * If the IP is in an unexpected format, it warns you.
#       * It then tests connectivity (using netcat, if available).
#         If the test fails, it loops back to ask for the IP again.
#   - Backup/create the APT configuration file and write the proxy configuration.
#   - Optionally update and upgrade packages.
#
# Usage (as root):
#   sudo ./install-apt-cacher-dialog.sh

set -e

# Check if running as root.
if [[ "$EUID" -ne 0 ]]; then
    dialog --msgbox "This installer must be run as root. Please run with sudo or as root." 8 50
    exit 1
fi

# Ask the user if they want to update and upgrade packages.
dialog --yesno "Would you like to update and upgrade your packages now?" 8 60
if [[ $? -eq 0 ]]; then
    DO_UPGRADE=true
else
    DO_UPGRADE=false
fi

# Display introduction.
dialog --msgbox "APT Cacher NG Installer\n\nThis script will configure APT to use apt-cacher-ng as a proxy for HTTP downloads." 10 60

# Loop until a valid IP is provided or the user aborts.
while true; do
    # Prompt the user for the apt-cacher-ng server IP address.
    APTCACHER_IP=$(dialog --stdout --inputbox "Enter the IP address of your apt-cacher-ng server (e.g. 192.168.1.100):" 8 60)

    # If the IP is left blank, abort the installer.
    if [[ -z "$APTCACHER_IP" ]]; then
        dialog --msgbox "No IP address provided. Aborting installer." 6 40
        clear
        exit 1
    fi

    # Optional: Validate the IP address format.
    if [[ ! "$APTCACHER_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        dialog --yesno "Warning: The entered IP address does not match a typical IPv4 format.\n\nDo you want to continue anyway?" 8 60
        # If the user chooses "No", loop back for a new input.
        if [[ $? -ne 0 ]]; then
            continue
        fi
    fi

    # Test connectivity to the apt-cacher-ng proxy (if netcat is installed).
    if command -v nc &>/dev/null; then
        if nc -z "$APTCACHER_IP" 3142; then
            dialog --msgbox "Successfully connected to apt-cacher-ng on $APTCACHER_IP:3142." 6 60
            break
        else
            dialog --msgbox "Could not connect to apt-cacher-ng on $APTCACHER_IP:3142.\n\nPlease ensure that the proxy is running and reachable. Try entering the IP address again." 8 60
        fi
    else
        dialog --msgbox "Netcat (nc) is not installed. Skipping connectivity test." 6 60
        break
    fi
done

# Define the target APT configuration file.
APT_CONF_FILE="/etc/apt/apt.conf.d/01apt-cacher-ng"

# Backup any existing configuration file.
if [[ -f "$APT_CONF_FILE" ]]; then
    dialog --msgbox "Backing up existing configuration file to ${APT_CONF_FILE}.bak" 6 60
    cp "$APT_CONF_FILE" "${APT_CONF_FILE}.bak"
fi

# Write the configuration.
cat <<EOF > "$APT_CONF_FILE"
Acquire::http::Proxy "http://$APTCACHER_IP:3142";
EOF

dialog --msgbox "Configuration written to $APT_CONF_FILE.\nAPT will now attempt to use apt-cacher-ng at http://$APTCACHER_IP:3142 for HTTP downloads." 8 60

# Run update and upgrade if requested.
if [ "$DO_UPGRADE" = true ]; then
    dialog --infobox "Updating package list..." 4 50
    apt update
    dialog --infobox "Upgrading packages..." 4 50
    apt upgrade -y
    dialog --msgbox "Packages updated and upgraded." 6 40
fi

dialog --msgbox "Installation complete.\nIf you encounter issues with apt, you can remove or modify ${APT_CONF_FILE}." 8 60
clear
