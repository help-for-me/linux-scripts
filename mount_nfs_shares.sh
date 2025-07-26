#!/usr/bin/env bash
# mount_nfs_shares.sh
#
# Maps NFS shares from a single NAS.
# Validates IP, shows exports, lets user mount selected shares with summaries.

set -e

LOG_FILE="/var/log/nfs_mounts.log"
FSTAB_BACKUP="/etc/fstab.bak.$(date +%F_%T)"

# Ensure root
if [ "$(id -u)" -ne 0 ]; then
    dialog --msgbox "Error: This script must be run as root." 7 50
    exit 1
fi

# Install requirements
apt update && apt install -y nfs-common dialog

# Ask for NAS IP/hostname
NAS_HOST=$(dialog --stdout --inputbox "Enter the IP address or hostname of the NAS:" 8 50)

# Test showmount and capture output properly
if ! showmount -e "$NAS_HOST" > /tmp/showmount_out 2>&1; then
    dialog --yesno "No NFS server found at $NAS_HOST. Would you like to modify the address?" 7 60
    if [ $? -eq 0 ]; then
        exec "$0"
    else
        dialog --msgbox "Exiting script." 6 40
        clear
        exit 1
    fi
fi

# Validate that showmount actually returned usable export lines
if ! grep -q '^/' /tmp/showmount_out; then
    dialog --msgbox "No NFS exports found on $NAS_HOST, or the server response was empty." 7 60
    exit 1
fi

# Prompt for (optional) credentials
NAS_USER=$(dialog --stdout --inputbox "Enter your NAS username (optional):" 8 40)
NAS_PASS=$(dialog --stdout --passwordbox "Enter your NAS password (optional):" 8 40)

# Parse exports
EXPORT_LIST=$(grep '^/' /tmp/showmount_out | awk '{print $1}')
IFS=$'\n' read -rd '' -a EXPORT_ARRAY <<<"$EXPORT_LIST"

if [ ${#EXPORT_ARRAY[@]} -eq 0 ]; then
    dialog --msgbox "No NFS exports found on $NAS_HOST." 7 50
    exit 1
fi

# Build checklist
CHECKLIST_ITEMS=()
for export in "${EXPORT_ARRAY[@]}"; do
    CHECKLIST_ITEMS+=("$export" "$NAS_HOST:$export" "off")
done

SELECTED_EXPORTS=$(dialog --stdout --checklist "Select NFS exports to mount from $NAS_HOST:" 15 60 5 "${CHECKLIST_ITEMS[@]}")
[ -z "$SELECTED_EXPORTS" ] && dialog --msgbox "No shares selected. Exiting." 6 40 && exit 1
SELECTED_EXPORTS=$(echo "$SELECTED_EXPORTS" | tr -d '"')

# Backup fstab
cp /etc/fstab "$FSTAB_BACKUP"

# Loop through selections
for export in $SELECTED_EXPORTS; do
    default_mount="/mnt/$(basename "$export")"
    MOUNT_POINT=$(dialog --stdout --inputbox "Enter mount point for $export (default: $default_mount):" 8 60 "$default_mount")

    # Validate
    if [[ ! "$MOUNT_POINT" =~ ^/ ]]; then
        dialog --msgbox "Invalid mount point: $MOUNT_POINT" 6 50
        continue
    fi

    mkdir -p "$MOUNT_POINT"
    NFS_SOURCE="${NAS_HOST}:${export}"

    # Prevent dupes
    if grep -qs "$NFS_SOURCE $MOUNT_POINT nfs" /etc/fstab; then
        dialog --msgbox "Entry for $MOUNT_POINT already exists. Skipping." 6 60
        continue
    fi

    # Write to fstab
    echo "$NFS_SOURCE $MOUNT_POINT nfs defaults,timeo=900,retrans=5,_netdev,nofail 0 0" >> /etc/fstab
    echo "$(date): Added $NFS_SOURCE to $MOUNT_POINT" >> "$LOG_FILE"
done

# Apply mounts
systemctl daemon-reexec
mount -a

# Summary
MSG="Mount summary:\n\n"
for export in $SELECTED_EXPORTS; do
    MP="/mnt/$(basename "$export")"
    if mountpoint -q "$MP"; then
        USAGE=$(df -h "$MP" | awk 'NR==2 {print "Size: " $2 ", Used: " $3 ", Avail: " $4 ", Use%: " $5}')
        MSG+="Mount point: $MP — Mounted\n$USAGE\n"
    else
        MSG+="Mount point: $MP — Failed to mount\n"
    fi
    MSG+="-------------------------\n"
done

dialog --msgbox "$MSG" 20 70
clear
echo "Script execution completed."
