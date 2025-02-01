#!/bin/bash
# host_name_update.sh - Reviews and updates the system hostname with validation.

# Ensure script is run as root
if [ "$(id -u)" -ne 0 ]; then
dialog --title "Permission Denied" --msgbox "This script must be run as root. Please use sudo or run as root." 7 50
exit 1
fi

# Get current hostname
CURRENT_HOSTNAME=$(hostname)

# Function to validate hostname
is_valid_hostname() {
local name="$1"
if [[ -z "$name" || ${#name} -gt 253 ]]; then
return 1
fi
IFS='.' read -ra PARTS <<< "$name"
for part in "${PARTS[@]}" do
if [[ ${#part} -gt 63 || ! "$part" =~ ^[a-zA-Z0-9][-a-zA-Z0-9]*$ || "$part" =~ -- || "$part" =~ ^- || "$part" =~ -$ ]]; then
return 1
fi
done
return 0 # Valid hostname
}

# Loop until a valid hostname is provided or the user cancels
while true; do
dialog --title "Hostname Update" --inputbox \
"Current hostname: $CURRENT_HOSTNAME\n\nEnter a new hostname or leave blank to keep the current one:" 10 50 2> /tmp/new_hostname

NEW_HOSTNAME=$(cat /tmp/new_hostname)
rm -f /tmp/new_hostname

if [[ -z "$NEW_HOSTNAME" || "$NEW_HOSTNAME" == "$CURRENT_HOSTNAME" ]]; then
dialog --title "No Changes" --msgbox "Hostname remains unchanged: $CURRENT_HOSTNAME" 7 50
exit 0
fi

if is_valid_hostname "$NEW_HOSTNAME" then
break
else
dialog --title "Invalid Hostname" --msgbox \
"The hostname '$NEW_HOSTNAME' is invalid.\n\nHostnames can only contain letters, numbers, and hyphens (-),\nand cannot start or end with a hyphen.\n\nPlease enter a valid hostname." 10 60
fi
done

# Update hostname
echo "$NEW_HOSTNAME" > /etc/hostname
sed -i "s/$CURRENT_HOSTNAME/$NEW_HOSTNAME/g" /etc/hosts

dialog --title "Hostname Updated" --msgbox "Hostname has been updated to: $NEW_HOSTNAME" 7 50

# Ask for reboot
dialog --title "Reboot Required" --yesno "A reboot is required for changes to fully apply.\n\nWould you like to reboot now?" 8 50
if [ $? -eq 0 ]; then
reboot
else
dialog --title "Reminder" --msgbox "Changes will take effect after the next reboot." 7 50
fi

clear
exit 0
