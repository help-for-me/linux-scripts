#!/usr/bin/env bash
# mount_nfs_shares.sh
#
# Interactive script to mount NFS exports from a NAS using dialog prompts.

set -e

LOG_FILE="/var/log/nfs_mounts.log"
FSTAB_BACKUP="/etc/fstab.bak.$(date +%F_%T)"

# Ensure script is run as root
if [ "$(id -u)" -ne 0 ]; then
    dialog --msgbox "You must run this script as root." 6 40
    exit 1
fi

# Install required packages
apt update && apt install -y nfs-common dialog

# Prompt for NAS IP/hostname
NAS_HOST=$(dialog --stdout --inputbox "Enter the IP address or hostname of the NAS:" 8 50)
[ -z "$NAS_HOST" ] && dialog --msgbox "No host entered. Exiting." 6 40 && exit 1

# Capture showmount output
if ! showmount -e "$NAS_HOST" > /tmp/showmount_out 2>&1; then
    dialog --yesno "Unable to reach NFS server at $NAS_HOST.\nWould you like to try again?" 8 60
    [ $? -eq 0 ] && exec "$0" || exit 1
fi

# Validate export lines
if ! grep -q '^/' /tmp/showmount_out; then
    dialog --msgbox "No NFS exports found on $NAS_HOST." 6 50
    exit 1
fi

# Prompt for (optional) username/password
NAS_USER=$(dialog --stdout --inputbox "Enter your NAS username (optional):" 8 40)
NAS_PASS=$(dialog --stdout --passwordbox "Enter your NAS password (optional):" 8 40)

# Parse export list
mapfile -t EXPORT_ARRAY < <(grep '^/' /tmp/showmount_out | awk '{print $1}')
if [ ${#EXPORT_ARRAY[@]} -eq 0 ]; then
    dialog --msgbox "Parsed export list was empty. Something went wrong." 6 50
    exit 1
fi

# Show checklist
CHECKLIST_ITEMS=()
for export in "${EXPORT_ARRAY[@]}"; do
    CHECKLIST_ITEMS+=("$export" "$NAS_HOST:$export" "off")
done

SELECTED_EXPORTS=$(dialog --stdout --checklist "Select NFS exports to mount from $NAS_HOST:" 15 60 6 "${CHECKLIST_ITEMS[@]}")
[ -z "$SELECTED_EXPORTS" ] && dialog --msgbox "No shares selected. Exiting." 6 40 && exit 1
SELECTED_EXPORTS=$(echo "$SELECTED_EXPORTS" | tr -d '"')

# Backup /etc/fstab
cp /etc/fstab "$FSTAB_BACKUP"

# Process each export
for export in $SELECTED_EXPORTS; do
    default_mount="/mnt/$(basename "$export")"
    MOUNT_POINT=$(dialog --stdout --inputbox "Enter mount point for $export:" 8 60 "$default_mount")
    [ -z "$MOUNT_POINT" ] && dialog --msgbox "No mount point entered. Skipping." 6 50 && continue

    mkdir -p "$MOUNT_POINT"
    NFS_SOURCE="${NAS_HOST}:${export}"

    if grep -qs "$NFS_SOURCE $MOUNT_POINT nfs" /etc/fstab; then
        dialog --msgbox "$MOUNT_POINT already in fstab. Skipping." 6 50
        continue
    fi

    echo "$NFS_SOURCE $MOUNT_POINT nfs defaults,timeo=900,retrans=5,_netdev,nofail 0 0" >> /etc/fstab
    echo "$(date): Added $NFS_SOURCE to $MOUNT_POINT" >> "$LOG_FILE"
done

# Reload and mount
systemctl daemon-reexec
mount -a

# Show summary
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

# Prompt to repeat
dialog --yesno "Would you like to mount shares from another NAS?" 7 50
if [ $? -eq 0 ]; then
    exec "$0"
else
    dialog --msgbox "All done. Goodbye!" 6 30
    clear
    echo "Script complete."
    exit 0
fi
