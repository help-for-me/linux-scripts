#!/bin/bash
# package_info_update_remove.sh - Lists installed packages, checks for updates, allows removal, and cleans up the system.

# Ensure script is run as root
if [ "$(id -u)" -ne 0 ]; then
dialog --title "Permission Denied" --msgbox "This script must be run as root. Please use sudo or run as root." 7 50
exit 1
fi

# Ensure `dialog` is installed
if ! command -v dialog &> /dev/null; then
echo "'dialog' is not installed. Installing dialog..."
apt-get update && apt-get install -y dialog
fi

# Refresh package lists
dialog --title "Updating Package Information" --infobox "Fetching latest package versions..." 5 50
apt update -y &>/dev/null

# Get list of installed packages and available updates
INSTALLED_PACKAGES=$(dpkg-query -W -f='${binary:Package} ${Version}\n')
AVAILABLE_UPDATES=$(apt list --upgradable 2>/dev/null | grep -v "Listing...")

# Format package list for display
PACKAGE_INFO="Installed Packages & Versions:\n\n"
while read -r pkg version; do
AVAILABLE_VERSION=$(echo "$AVAILABLE_UPDATES" | grep "^$pkg/" | awk '{print $2}')
if [[ -n "$AVAILABLE_VERSION" ]]; then
PACKAGE_INFO+="$pkg (Installed: $version → Available: $AVAILABLE_VERSION)\n"
else
PACKAGE_INFO+="$pkg (Installed: $version)\n"
fi
done <<< "$INSTALLED_PACKAGES"

# Display package list
dialog --title "Installed Packages" --msgbox "$PACKAGE_INFO" 25 90

# Check if updates are available
if [[ -n "$AVAILABLE_UPDATES" ]]; then
# Ask if the user wants to upgrade all packages
dialog --title "Upgrade Packages" --yesno "Some packages have available updates.\n\nWould you like to update all packages now?" 8 60
if [ $? -eq 0 ]; then
dialog --title "Upgrading Packages" --infobox "Updating all packages. This may take a while..." 5 50
apt upgrade -y &>/dev/null
dialog --title "Upgrade Complete" --msgbox "All packages have been updated successfully!" 7 50
else
dialog --title "Upgrade Skipped" --msgbox "No changes made. Packages remain unchanged." 7 50
fi
fi

# Ask if the user wants to remove any packages
dialog --title "Package Removal" --yesno "Would you like to remove any installed packages?" 8 50
if [ $? -eq 0 ]; then
# Build list for package removal selection
PACKAGE_LIST=()
while read -r pkg version; do
PACKAGE_LIST+=("$pkg" "$version" "off")
done <<< "$INSTALLED_PACKAGES"

# Show selection menu
SELECTED_PACKAGES=$(dialog --title "Select Packages to Remove" --checklist "Use SPACE to select packages to uninstall. Press ENTER to confirm." 20 70 15 "${PACKAGE_LIST[@]}" 2>&1 >/dev/tty)

if [[ -n "$SELECTED_PACKAGES" ]]; then
# Confirm package removal
dialog --title "Confirm Removal" --yesno "Are you sure you want to remove the following packages?\n\n$SELECTED_PACKAGES" 10 60
if [ $? -eq 0 ]; then
dialog --title "Removing Packages" --infobox "Removing selected packages..." 5 50
apt remove -y $SELECTED_PACKAGES &>/dev/null
dialog --title "Removal Complete" --msgbox "Selected packages have been removed." 7 50
else
dialog --title "Removal Canceled" --msgbox "No packages were removed." 7 50
fi
else
dialog --title "No Selection" --msgbox "No packages were selected for removal." 7 50
fi
fi

# Check if there are unnecessary packages that can be removed
if [[ -n $(apt list --autoremove 2>/dev/null | grep -v "Listing...") ]]; then
dialog --title "Auto-remove Packages" --yesno "There are unnecessary packages that can be removed.\n\nWould you like to remove them now?" 8 60
if [ $? -eq 0 ]; then
dialog --title "Removing Unnecessary Packages" --infobox "Running 'apt autoremove'..." 5 50
apt autoremove -y &>/dev/null
dialog --title "Cleanup Complete" --msgbox "Unnecessary packages have been removed." 7 50
fi
fi

# Check if there is cached package data that can be cleaned
if [[ $(du -sh /var/cache/apt/archives 2>/dev/null | awk '{print $1}') != "0" ]]; then
dialog --title "Clean Package Cache" --yesno "There is cached package data that can be cleaned.\n\nWould you like to clean it now?" 8 60
if [ $? -eq 0 ]; then
dialog --title "Cleaning Package Cache" --infobox "Running 'apt clean'..." 5 50
apt clean &>/dev/null
dialog --title "Cache Cleaned" --msgbox "Package cache has been cleaned." 7 50
fi
fi

clear
exit 0
