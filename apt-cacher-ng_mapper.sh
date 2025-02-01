#!/bin/bash
# apt-cacher-ng_mapper.sh
# This script configures APT to use an apt-cacher-ng proxy.
# It prompts for the proxy IP address (optionally with port).
# If no port is specified, the script uses the default port 3142.
# Before applying the configuration, it verifies that the server is reachable
# by accepting either a 406 (usage information) or any 2xx HTTP response.
# If the check fails, you are given the option to retry or abort.

# Check if 'dialog' is installed
if ! command -v dialog &>/dev/null; then
    echo "The 'dialog' utility is required. Install it with:"
    echo "  sudo apt-get install dialog"
    exit 1
fi

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
    dialog --msgbox "This script must be run as root. Please run with sudo." 6 50
    exit 1
fi

# Define the configuration file path
config_file="/etc/apt/apt.conf.d/02proxy"

# Function to prompt the user for the proxy IP (and optional port)
prompt_proxy() {
    local tmpfile
    tmpfile=$(mktemp /tmp/apt-proxy.XXXX)
    trap 'rm -f "$tmpfile"' EXIT

    dialog --title "Configure Apt Proxy" \
           --inputbox "Enter your apt-cacher-ng server IP (optionally with port, e.g., 192.168.1.100:3142):" \
           8 60 2> "$tmpfile"

    local response=$?
    local input
    input=$(cat "$tmpfile")
    rm -f "$tmpfile"
    trap - EXIT

    # If the user pressed Cancel or Esc, abort
    if [ $response -ne 0 ]; then
        dialog --msgbox "Operation cancelled." 6 40
        exit 1
    fi

    # If no port is provided, default to 3142
    if [[ "$input" != *:* ]]; then
        echo "${input}:3142"
    else
        echo "$input"
    fi
}

# Loop to prompt and check the server until it succeeds or the user aborts
while true; do
    proxy=$(prompt_proxy)
    check_url="http://${proxy}/"
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$check_url")

    # Accept either a 406 or any 2xx HTTP response as valid.
    if [[ "$http_code" == "406" || "${http_code:0:1}" == "2" ]]; then
        break  # Valid proxy found; exit loop.
    else
        # Offer the user a choice to retry or abort.
        dialog --yesno "Error: Could not connect to apt-cacher-ng server at ${check_url}.\nReceived HTTP status code: ${http_code}.\n\nWould you like to retry?" 10 60
        choice=$?
        if [ $choice -ne 0 ]; then
            # User chose "No" (or pressed Esc)
            dialog --msgbox "Operation aborted." 6 40
            exit 1
        fi
        # Otherwise, loop again to re-prompt.
    fi
done

# Define the proxy configuration line for APT
proxy_conf="Acquire::http::Proxy \"http://${proxy}/\";"

# Backup existing configuration file if it exists
if [ -f "$config_file" ]; then
    cp "$config_file" "${config_file}.bak"
    dialog --msgbox "Existing configuration backed up to ${config_file}.bak" 6 50
fi

# Write the proxy configuration to the file
echo "$proxy_conf" > "$config_file"

# Inform the user of the successful configuration
dialog --msgbox "APT is now configured to use the proxy: http://${proxy}/" 6 60
