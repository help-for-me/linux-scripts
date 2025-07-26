#!/usr/bin/env bash
# mount_smb_shares.sh

set -e

LOG_FILE="/var/log/smb_mounts.log"
CRED_DIR="/etc/smb-credentials"
CRED_FILE="$CRED_DIR/cred"
FSTAB_BACKUP="/etc/fstab.bak.$(date +%F_%T)"

# Ensure root
if [ "$(id -u)" -ne 0 ]; then
    dialog --msgbox "This script must be run as root." 6 40
    exit 1
fi

apt update && apt install -y cifs-utils smbclient dialog

mkdir -p "$CRED_DIR"

SERVER_IP=$(dialog --stdout --inputbox "Enter the IP address or hostname of the SMB server:" 8 50)
[ -z "$SERVER_IP" ] && dialog --msgbox "No server address entered. Exiting." 6 40 && exit 1

SMB_USER=$(dialog --stdout --inputbox "Enter your SMB username:" 8 40)
SMB_PASS=$(dialog --stdout --passwordbox "Enter your SMB password:" 8 40)

echo -e "username=${SMB_USER}\npassword=${SMB_PASS}" > "$CRED_FILE"
chmod 600 "$CRED_FILE"

mapfile -t SHARE_LIST < <(smbclient -L "$SERVER_IP" -U "$SMB_USER%$SMB_PASS" 2>/dev/null | awk '/^[[:space:]]*[A-Za-z0-9_\$-]+[[:space:]]+Disk/ {print $1}')

if [[ ${#SHARE_LIST[@]} -eq 0 ]]; then
    dialog --msgbox "No shares found or authentication failed." 7 60
    exit 1
fi

CHECKLIST_ITEMS=()
for share in "${SHARE_LIST[@]}"; do
    CHECKLIST_ITEMS+=("$share" "//$SERVER_IP/$share" "off")
done

SELECTED_SHARES=$(dialog --stdout --checklist "Select SMB shares to mount from $SERVER_IP:" 20 60 10 "${CHECKLIST_ITEMS[@]}")
[ -z "$SELECTED_SHARES" ] && dialog --msgbox "No shares selected. Exiting." 6 40 && exit 1
SELECTED_SHARES=$(echo "$SELECTED_SHARES" | tr -d '"')

cp /etc/fstab "$FSTAB_BACKUP"

MOUNT_POINTS=()

for share in $SELECTED_SHARES; do
    clean_share=$(echo "$share" | tr -d '$')
    default_mount="/mnt/$clean_share"
    MOUNT_POINT=$(dialog --stdout --inputbox "Enter local mount point for $share:" 8 60 "$default_mount")
    [ -z "$MOUNT_POINT" ] && dialog --msgbox "No mount point entered. Skipping $share." 6 50 && continue

    mkdir -p "$MOUNT_POINT"
    SHARE_PATH="//$SERVER_IP/$share"

    if grep -qs "$SHARE_PATH $MOUNT_POINT cifs" /etc/fstab; then
        dialog --msgbox "$MOUNT_POINT already in fstab. Skipping." 6 50
        continue
    fi

    echo "$SHARE_PATH $MOUNT_POINT cifs credentials=$CRED_FILE,uid=1000,gid=1000,iocharset=utf8,vers=3.0,nofail,_netdev 0 0" >> /etc/fstab
    echo "$(date): Added $SHARE_PATH to $MOUNT_POINT" >> "$LOG_FILE"
    MOUNT_POINTS+=("$MOUNT_POINT")
done

systemctl daemon-reexec
mount -a

MSG="Mount summary:\n\n"
for MP in "${MOUNT_POINTS[@]}"; do
    if mountpoint -q "$MP"; then
        USAGE=$(df -h "$MP" | awk 'NR==2 {print "Size: " $2 ", Used: " $3 ", Avail: " $4 ", Use%: " $5}')
        MSG+="Mount point: $MP — Mounted\n$USAGE\n"
    else
        MSG+="Mount point: $MP — Failed to mount\n"
    fi
    MSG+="-------------------------\n"
done

dialog --msgbox "$MSG" 20 70

# Ask if user wants to map another NAS
dialog --yesno "Would you like to mount shares from another NAS?" 7 50
if [ $? -eq 0 ]; then
    exec "$0"
else
    dialog --msgbox "All done. Goodbye!" 6 30
    clear
    echo "Script complete."
    exit 0
fi
