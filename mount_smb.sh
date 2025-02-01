#!/bin/bash
# mount_smb_dialog.sh
#
# This script automates the installation of CIFS utilities, configuration of SMB shares,
# creation of a credentials file, updating /etc/fstab, and mounting of the shares using dialog boxes.
#
# It will prompt for:
#   - SMB username and password (used for all shares)
#   - The number of SMB shares to configure
#   - The server IP address
#   - For each share: the share location on the server and the local mount point.
#
# The script must be run as root.
# Example usage: sudo ./mount_smb_dialog.sh

# Ensure the script is run as root
if [ "$(id -u)" -ne 0 ]; then
    dialog --msgbox "Error: This script must be run as root (e.g. using sudo)." 8 40
    exit 1
fi

# Update package list and install required packages
apt update && apt install -y cifs-utils dialog

# Prompt for SMB credentials
smb_user=$(dialog --stdout --inputbox "Enter SMB username:" 8 40)
smb_pass=$(dialog --stdout --passwordbox "Enter SMB password:" 8 40)

# Create the credentials file
cred_file="/etc/credentials"
cat <<EOF > "$cred_file"
username=${smb_user}
password=${smb_pass}
EOF
chmod 600 "$cred_file"

# Ask for the number of SMB shares to configure
num_shares=$(dialog --stdout --inputbox "Enter the number of SMB shares to configure:" 8 40)

# Ask for the server IP address (to be used for all shares)
server_ip=$(dialog --stdout --inputbox "Enter the IP address of the server:" 8 40)

# Backup /etc/fstab before modifying
cp /etc/fstab /etc/fstab.bak

# Declare an array to store mount points for later verification
declare -a mount_points

# Loop for each share configuration
for (( i=1; i<=num_shares; i++ )); do
    share_location=$(dialog --stdout --inputbox "Share #$i: Enter the share location (the name of the share on the server):" 8 50)
    mount_point=$(dialog --stdout --inputbox "Share #$i: Enter the local mount point (e.g. /mnt/share):" 8 50)
    
    # Combine server IP and share location to form the complete SMB share path
    smb_share="//${server_ip}/${share_location}"
    
    # Save the mount point in the array for later verification
    mount_points[i]="$mount_point"
    
    # Create the mount point directory if it doesn't exist
    mkdir -p "$mount_point"
    
    # Build the fstab entry with the given options
    fstab_entry="${smb_share} ${mount_point} cifs credentials=${cred_file},uid=1000,gid=1000,iocharset=utf8,vers=3.0 0 0"
    echo "$fstab_entry" >> /etc/fstab
done

# Reload systemd configuration
systemctl daemon-reload

# Mount all filesystems defined in /etc/fstab
mount -a

# Build a summary message with the mounted filesystems
msg="Verifying mounted filesystems:\n\n"
for (( i=1; i<=num_shares; i++ )); do
    msg+="Mount point: ${mount_points[i]}\n"
    msg+="$(df -h ${mount_points[i]})\n"
    msg+="-------------------------\n"
done

# Display the summary in a dialog message box
dialog --msgbox "$msg" 20 70

# Clear the dialog artifacts from the screen
clear
echo "Script execution completed."
