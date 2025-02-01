#!/bin/bash
# system_info.sh - Displays system information and exports it to Discord.

# Ensure `dialog` is installed
if ! command -v dialog &> /dev/null; then
  echo "'dialog' is not installed. Installing dialog..."
  apt-get update && apt-get install -y dialog
fi

# Get CPU details
CPU_MODEL=$(lscpu | grep "Model name" | awk -F: '{print $2}' | sed 's/^[ \t]*//')
CPU_CORES=$(nproc)
CPU_SPEED=$(lscpu | grep "CPU MHz" | awk -F: '{print $2}' | sed 's/^[ \t]*//')

# Get Memory details
MEM_TOTAL=$(free -h | awk '/^Mem:/{print $2}')
MEM_SPEED=$(dmidecode -t memory | grep -m 1 "Speed" | awk -F: '{print $2}' | sed 's/^[ \t]*//')

# Get Disk details
DISK_INFO=$(lsblk -o NAME,SIZE,TYPE | grep "disk" | awk '{print "Disk: "$1" - "$2}')

# Get IP address & Active Interfaces
ACTIVE_INTERFACES=$(ip -o -4 addr show | awk '{print $2 " - " $4}')
IP_ADDRESS=$(hostname -I | awk '{print $1}')

# Get OS details
OS_NAME=$(lsb_release -d | awk -F: '{print $2}' | sed 's/^[ \t]*//')
KERNEL_VERSION=$(uname -r)

# Get System Uptime
UPTIME_INFO=$(uptime -p | sed 's/up //')

# Get GPU information (if available)
if command -v lspci &> /dev/null; then
  GPU_INFO=$(lspci | grep -i "VGA" | awk -F': ' '{print $2}')
else
  GPU_INFO="Not available"
fi

# Get Temperature Sensors (if available)
if command -v sensors &> /dev/null; then
  TEMP_INFO=$(sensors | grep -E "Core|temp" | awk '{$1=$1};1')
else
  TEMP_INFO="Temperature sensors not available"
fi

# Get Network Link Speeds
INTERFACES=$(ip -o link show | awk -F': ' '{print $2}')
LINK_SPEEDS=""
for iface in $INTERFACES; do
  if ethtool "$iface" &>/dev/null; then
    SPEED=$(ethtool "$iface" | grep "Speed" | awk -F': ' '{print $2}')
    LINK_SPEEDS+="$iface: ${SPEED:-Unknown}\n"
  fi
done

# Get DNS Servers
DNS_SERVERS=$(grep "nameserver" /etc/resolv.conf | awk '{print $2}')

# Get Wi-Fi SSID & Signal Strength (if connected via Wi-Fi)
WIFI_INFO=""
if command -v iwconfig &> /dev/null; then
  WIFI_INTERFACE=$(iwconfig 2>/dev/null | grep "ESSID" | awk '{print $1}')
  if [[ -n "$WIFI_INTERFACE" ]]; then
    WIFI_SSID=$(iwconfig "$WIFI_INTERFACE" | grep "ESSID" | awk -F'"' '{print $2}')
    WIFI_SIGNAL=$(iwconfig "$WIFI_INTERFACE" | grep -o "Signal level=.*" | awk '{print $3}')
    WIFI_INFO="SSID: ${WIFI_SSID:-Unknown}\nSignal Strength: ${WIFI_SIGNAL:-Unknown}"
  else
    WIFI_INFO="No Wi-Fi connection detected"
  fi
fi

# Format information for dialog box
INFO_TEXT="\
System Information:
------------------------
OS: $OS_NAME
Kernel: $KERNEL_VERSION
Uptime: $UPTIME_INFO

CPU:
------------------------
Model: $CPU_MODEL
Cores: $CPU_CORES
Speed: ${CPU_SPEED} MHz

Memory:
------------------------
Total: $MEM_TOTAL
Speed: ${MEM_SPEED:-Unknown}

Drives:
------------------------
$DISK_INFO

Network:
------------------------
IP Address: $IP_ADDRESS
Active Interfaces:
$ACTIVE_INTERFACES

Link Speeds:
$LINK_SPEEDS

DNS Servers:
$DNS_SERVERS

Wi-Fi Information:
------------------------
$WIFI_INFO

GPU:
------------------------
$GPU_INFO

Temperature Sensors:
------------------------
$TEMP_INFO
"

# Display system information
dialog --title "System Information" --msgbox "$INFO_TEXT" 35 90

clear

# -------------------------
# Export system information to Discord
# -------------------------
# Set your Discord webhook URL
WEBHOOK_URL="https://discord.com/api/webhooks/1335160467705827418/p8CV3AhYQeTK0PHh9iCQ2sIA5KrDlwi6_RM4CCHoj71qeO_aAlP3WX3y-Et9nDgr2jXs"

# Construct JSON payload.
# Use echo -e to interpret \n as newlines and sed to escape any double quotes.
PAYLOAD="{\"content\": \"$(echo -e "$INFO_TEXT" | sed 's/"/\\"/g')\"}"

# Debug: Print the payload to the terminal
echo "DEBUG: Payload being sent to Discord:"
echo "$PAYLOAD"

# Send the payload to Discord using curl.
# The -v flag enables verbose output so you can see connection details.
DISCORD_RESPONSE=$(curl -v -H "Content-Type: application/json" -X POST -d "$PAYLOAD" "$WEBHOOK_URL")
echo "DEBUG: Discord response:"
echo "$DISCORD_RESPONSE"

exit 0
