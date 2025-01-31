#!/bin/bash
# mount_smb.sh
#
# This script automates the installation of CIFS utilities, configuration of SMB shares,
# creation of a credentials file, updating /etc/fstab, and mounting of the shares.
#
# It will prompt for:
#   - SMB username and password (used for all shares)
#   - The number of SMB shares to configure
#   - For each share: the remote SMB share path and the local mount point.
#
# The script must be run as root.
# Example usage: sudo ./mount_smb.sh

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root (e.g. using sudo)."
    exit 1
fi

echo "Updating package list and installing cifs-utils..."
apt update && apt install -y cifs-utils

# Prompt for SMB credentials
read -p "Enter SMB username: " smb_user
read -s -p "Enter SMB password: " smb_pass
echo  # For newline after password prompt

# Create the credentials file
cred_file="/etc/credentials"
echo "Creating credentials file at $cred_file..."
cat <<EOF > "$cred_file"
username=${smb_user}
password=${smb_pass}
EOF
chmod 600 "$cred_file"
echo "Credentials file created and permissions set to 600."

# Ask for the number of SMB shares to configure
read -p "Enter the number of SMB shares to configure: " num_shares

# Backup /etc/fstab before modifying
cp /etc/fstab /etc/fstab.bak
echo "Backup of /etc/fstab saved as /etc/fstab.bak."

# Declare an array to store mount points for later verification
declare -a mount_points

# Loop for each share configuration
for (( i=1; i<=num_shares; i++ )); do
    echo "-------------------------------"
    echo "Configuring share #$i:"
    read -p "  Enter SMB share path (e.g. //10.18.1.4/Content): " smb_share
    read -p "  Enter local mount point (e.g. /mnt/content): " mount_point

    # Save mount point in array for later verification
    mount_points[i]="$mount_point"

    # Create the mount point directory if it doesn't exist
    mkdir -p "$mount_point"
    echo "  Created mount point directory: $mount_point"

    # Build the fstab entry with the given options
    fstab_entry="${smb_share} ${mount_point} cifs credentials=${cred_file},uid=1000,gid=1000,iocharset=utf8,vers=3.0 0 0"
    echo "$fstab_entry" >> /etc/fstab
    echo "  Added the following entry to /etc/fstab:"
    echo "    $fstab_entry"
done

echo "-------------------------------"
echo "Reloading systemd configuration..."
systemctl daemon-reload

echo "Mounting all filesystems defined in /etc/fstab..."
mount -a

echo "Verifying mounted filesystems:"
for (( i=1; i<=num_shares; i++ )); do
    echo "--------------------------------"
    echo "Mount point: ${mount_points[i]}"
    df -h "${mount_points[i]}"
done

echo "Script execution completed."
