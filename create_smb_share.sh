#!/bin/bash

SMB_CONF="/etc/samba/smb.conf"
SYSTEMD_SERVICE="smbd"
SHARE_NAME="PublicShare"

# Ensure required packages are installed
install_packages() {
    local packages=("samba")
    local installed=()
    local updated=()

    echo "Checking for required packages..."
    for pkg in "${packages[@]}"; do
        if ! dpkg -s "$pkg" &>/dev/null; then
            installed+=("$pkg")
        fi
    done

    if [ ${#installed[@]} -ne 0 ]; then
        echo "Installing: ${installed[*]}"
        sudo apt update -y && sudo apt install -y "${installed[@]}"
    fi
}

# Function to let user choose folder to share
select_folder() {
    folder=$(dialog --title "Select Folder to Share" --dselect "$HOME/" 10 60 3>&1 1>&2 2>&3)
    
    if [ -z "$folder" ]; then
        dialog --msgbox "No folder selected. Exiting." 8 40
        exit 1
    fi
}

# Function to set share permissions
set_permissions() {
    dialog --title "Select Share Permission" --menu "Choose access level:" 10 40 2 \
        1 "Read-Only" \
        2 "Read-Write" 2> /tmp/smb_perm_choice

    choice=$(cat /tmp/smb_perm_choice)
    rm -f /tmp/smb_perm_choice

    case $choice in
        1) PERMISSION="read only = yes" ;;
        2) PERMISSION="read only = no" ;;
        *) dialog --msgbox "Invalid choice. Exiting." 8 40; exit 1 ;;
    esac
}

# Function to configure SMB share
configure_smb_share() {
    # Remove existing entry if reconfiguring
    sudo sed -i "/^\[$SHARE_NAME\]/,/^$/d" "$SMB_CONF"

    # Add new share configuration
    echo -e "\n[$SHARE_NAME]
    path = $folder
    browseable = yes
    guest ok = yes
    force user = nobody
    force group = nogroup
    create mask = 0777
    directory mask = 0777
    $PERMISSION" | sudo tee -a "$SMB_CONF" > /dev/null

    # Restart Samba service
    sudo systemctl restart "$SYSTEMD_SERVICE"
    sudo systemctl enable "$SYSTEMD_SERVICE"
}

# Function to remove the SMB share
remove_smb_share() {
    dialog --title "Remove SMB Share" --yesno "Are you sure you want to remove the SMB share?" 8 50
    if [ $? -eq 0 ]; then
        sudo sed -i "/^\[$SHARE_NAME\]/,/^$/d" "$SMB_CONF"
        sudo systemctl restart "$SYSTEMD_SERVICE"
        dialog --msgbox "SMB share removed." 8 40
    else
        dialog --msgbox "Operation cancelled." 8 40
    fi
}

# Display disclaimer about security risks
dialog --title "Security Warning" --msgbox "This script sets up an SMB share with NO authentication.
Anyone on your network will have access to this share.
Make sure you trust all devices on your network before proceeding!" 10 60

# Install required packages
install_packages

# Ask user to configure or remove the SMB share
dialog --title "SMB Share Setup" --menu "What do you want to do?" 10 40 3 \
    1 "Create or Modify SMB Share" \
    2 "Remove SMB Share" \
    3 "Exit" 2> /tmp/smb_action

action=$(cat /tmp/smb_action)
rm -f /tmp/smb_action

case $action in
    1)
        select_folder
        set_permissions
        configure_smb_share
        dialog --msgbox "SMB Share configured successfully!\nYou can now access it from any device on your network." 8 50
        ;;
    2) remove_smb_share ;;
    3) exit 0 ;;
    *) dialog --msgbox "Invalid selection. Exiting." 8 40 ;;
esac