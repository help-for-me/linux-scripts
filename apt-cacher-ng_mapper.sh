#!/bin/bash
# apt-cacher-ng_mapper.sh
# This script configures APT to use an apt-cacher-ng proxy.
# It prompts for the proxy IP address (optionally with port).
# If no port is specified, the script uses the default port 3142.
# Before applying the configuration, it verifies that the server is reachable
# by accepting either a 406 (usage information) or any 2xx HTTP response.

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

# Verify that the apt-cacher-ng server is reachable by checking for a valid HTTP response.
# We accept either a 406 (the expected usage page response) or any 2xx response.
check_url="http://${proxy}/"
http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$check_url")

# For debugging, you could uncomment the next line:
# echo "Received HTTP code: $http_code"

if [[ "$http_code" != "406" && "${http_code:0:1}" != "2" ]]; then
    echo "Error: Could not connect to apt-cacher-ng server at ${check_url}."
    echo "Received HTTP status code: ${http_code}. Please verify the IP address and port, then try again."
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
