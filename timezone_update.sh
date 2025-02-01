#!/bin/bash
# timezone_update.sh - Reviews and updates the system timezone.

# Ensure script is run as root
if [ "$(id -u)" -ne 0 ]; then
dialog --title "Permission Denied" --msgbox "This script must be run as root. Please use sudo or run as root." 7 50
exit 1
fi

# Get current timezone
CURRENT_TIMEZONE=$(timedatectl show --property=Timezone --value)

# Ask user if they want to change the timezone
dialog --title "Timezone Review" --yesno "Current Timezone: $CURRENT_TIMEZONE\n\nWould you like to change it?" 8 60
if [ $? -ne 0 ]; then
dialog --title "No Changes" --msgbox "Timezone remains unchanged: $CURRENT_TIMEZONE" 7 50
exit 0
fi

# Let the user select a new timezone
NEW_TIMEZONE=$(tzselect 2>/dev/null | tail -n 1)

if [[ -z "$NEW_TIMEZONE" || "$NEW_TIMEZONE" == "$CURRENT_TIMEZONE" ]]; then
dialog --title "No Changes" --msgbox "Timezone remains unchanged: $CURRENT_TIMEZONE" 7 50
exit 0
fi

# Apply the new timezone
timedatectl set-timezone "$NEW_TIMEZONE"

dialog --title "Timezone Updated" --msgbox "Timezone has been updated to: $NEW_TIMEZONE" 7 50

# Ask for reboot
dialog --title "Reboot Required" --yesno "A reboot is recommended to fully apply timezone changes.\n\nWould you like to reboot now?" 8 50
if [ $? -eq 0 ]; then
reboot
else
dialog --title "Reminder" --msgbox "Changes will take effect after the next reboot." 7 50
fi

clear
exit 0
