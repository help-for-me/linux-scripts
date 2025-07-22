#!/bin/bash
#
# install-apt-cacher-dialog.sh
#
# This script configures APT to use apt-cacher-ng as a proxy.
# If unreachable, the user can fall back to direct APT access.
# Existing proxy configs are detected and managed.

set -e

APT_CONF_FILE="/etc/apt/apt.conf.d/01apt-cacher-ng"

# Must be root
if [[ "$EUID" -ne 0 ]]; then
    dialog --msgbox "This installer must be run as root. Please run with sudo or as root." 8 50
    exit 1
fi

# Welcome
dialog --msgbox "APT Cacher NG Installer\n\nThis script configures APT to use apt-cacher-ng as a proxy." 10 60

# Optional upgrade
dialog --yesno "Would you like to update and upgrade your packages after configuration?" 8 60
DO_UPGRADE=$([[ $? -eq 0 ]] && echo "true" || echo "false")

# Check for existing config
if [[ -f "$APT_CONF_FILE" ]]; then
    CURRENT_PROXY=$(grep -oP 'http://\K[^"]+' "$APT_CONF_FILE" || true)
    dialog --yesno --title "Existing Proxy Found" \
        "An existing proxy configuration was found:\n\n$CURRENT_PROXY\n\nWould you like to keep this configuration?" 10 60
    case $? in
        0)
            USE_PROXY=true
            APTCACHER_IP="${CURRENT_PROXY%%:*}"
            SKIP_CONFIG=true
            ;;
        1)
            dialog --yesno --title "Overwrite or Remove?" \
                "Would you like to overwrite the existing configuration?\n\nChoose 'No' to remove it and use direct access." 10 60
            case $? in
                0) SKIP_CONFIG=false ;;   # Overwrite
                1)
                    rm -f "$APT_CONF_FILE"
                    dialog --msgbox "Removed existing APT proxy configuration." 6 50
                    USE_PROXY=false
                    SKIP_CONFIG=true
                    ;;
            esac
            ;;
    esac
fi

# Prompt for IP if not skipping config
if [[ "$SKIP_CONFIG" != true ]]; then
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

        # Connection test
        if nc -z -w3 "$APTCACHER_IP" 3142 || curl -s --connect-timeout 3 "http://$APTCACHER_IP:3142/" | grep -q '.'; then
            dialog --msgbox "Successfully connected to apt-cacher-ng on $APTCACHER_IP:3142." 6 60
            USE_PROXY=true
            break
        else
            dialog --yesno --title "Connection Failed" --yes-label "Use Direct APT" --no-label "Retry" \
            "Could not connect to apt-cacher-ng at $APTCACHER_IP:3142.\n\nFallback to direct APT instead?" 10 60
            [[ $? -eq 0 ]] && USE_PROXY=false && break
        fi
    done
fi

# Write proxy config if using
if [[ "$SKIP_CONFIG" != true ]]; then
    if [[ "$USE_PROXY" == true ]]; then
        [[ -f "$APT_CONF_FILE" ]] && cp "$APT_CONF_FILE" "${APT_CONF_FILE}.bak"
        cat <<EOF > "$APT_CONF_FILE"
Acquire::http::Proxy "http://$APTCACHER_IP:3142";
EOF
        dialog --msgbox "APT is now configured to use apt-cacher-ng at http://$APTCACHER_IP:3142" 8 60
    else
        [[ -f "$APT_CONF_FILE" ]] && rm -f "$APT_CONF_FILE"
        dialog --msgbox "APT is now configured to use direct downloads (no proxy)." 6 50
    fi
fi

# Package updates
if [[ "$DO_UPGRADE" == "true" ]]; then
    dialog --infobox "Running apt update..." 4 50
    apt update
    dialog --infobox "Running apt upgrade..." 4 50
    apt upgrade -y
    dialog --msgbox "Packages have been updated and upgraded." 6 50
fi

# Final message
dialog --msgbox "Installation complete.\nYou can modify or remove the APT proxy at:\n\n$APT_CONF_FILE" 8 60
clear