#!/bin/bash
# apt-cacher-ng_mapper.sh
# This script configures APT to use an apt-cacher-ng proxy.
# It prompts for the proxy IP address (optionally with port).
# If no port is specified, the script uses the default port 3142.

# Check if 'dialog' is installed
if ! command -v dialog &>/dev/null; then
    echo "The 'dialog' utility is required. Install it with:"
    echo "  sudo apt-get install dialog"
    exit 1
fi

# Create a temporary file and ensure it gets cleaned up on exit
tempfile=$(mktemp /tmp/apt-proxy.XXXX)
trap 'rm -f "$tempfile"' EXIT

# Use dialog to prompt for the IP address (and optionally, port)
dialog --title "Configure Apt Proxy" \
       --inputbox "Enter your apt-cacher-ng server IP (optionally with port, e.g., 192.168.1.100:3142):" \
       8 60 2> "$tempfile"

# Capture the exit status and the entered value
response=$?
input=$(cat "$tempfile")

# If the user pressed Cancel or Esc, exit the script
if [ $response -ne 0 ]; then
    echo "Operation cancelled."
    exit 1
fi

# If the input does not contain a colon, append the default port 3142
if [[ "$input" != *:* ]]; then
    proxy="$input:3142"
else
    proxy="$input"
fi

# Define the proxy configuration line for APT
proxy_conf="Acquire::http::Proxy \"http://${proxy}/\";"

# Define the configuration file path
config_file="/etc/apt/apt.conf.d/02proxy"

# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root. Please run with sudo."
    exit 1
fi

# Backup existing configuration file if it exists
if [ -f "$config_file" ]; then
    cp "$config_file" "${config_file}.bak"
    echo "Existing configuration backed up to ${config_file}.bak"
fi

# Write the proxy configuration to the file
echo "$proxy_conf" > "$config_file"

# Inform the user of the successful configuration
echo "APT is now configured to use the proxy: http://${proxy}/"
