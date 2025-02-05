#!/bin/bash

# Function to display a dialog-based menu
show_menu() {
    dialog --clear --title "$1" --menu "$2" 15 60 4 "${@:3}" 2>&1 >/dev/tty
}

# Function to get user input
get_input() {
    dialog --clear --title "$1" --inputbox "$2" 10 60 2>&1 >/dev/tty
}

# Function to display a checklist
get_checklist() {
    dialog --clear --title "$1" --checklist "$2" 15 60 10 "${@:3}" 2>&1 >/dev/tty
}

# Function to show an info box
show_info() {
    dialog --clear --title "$1" --msgbox "$2" 10 60
}

# Detect if the script has been run before
if grep -q "\[.*\]" /etc/samba/smb.conf; then
    EXISTING_SHARES=$(grep "^\[.*\]" /etc/samba/smb.conf | sed 's/\[\(.*\)\]/\1/')
    CHOICES=()
    for SHARE in $EXISTING_SHARES; do
        CHOICES+=("$SHARE" "Delete" "off")
    done

    REMOVE_SHARES=$(get_checklist "Existing SMB Shares" "Select shares to delete (Space to toggle):" "${CHOICES[@]}")
    if [ -n "$REMOVE_SHARES" ]; then
        for SHARE in $REMOVE_SHARES; do
            sudo sed -i "/^\[$SHARE\]/,/^$/d" /etc/samba/smb.conf
            sudo rm -rf "/srv/smb/$SHARE"
        done
        show_info "SMB Shares Deleted" "Selected shares have been removed."
    fi
fi

# Get user input
GITHUB_TOKEN=$(get_input "GitHub Authentication" "Enter your **GitHub Personal Access Token**:")
GITHUB_USER=$(get_input "GitHub Username" "Enter your **GitHub username**:")
GITHUB_REPO=$(get_input "GitHub Repository" "Enter the **repository name**:")
SMB_SHARE_NAME=$(get_input "SMB Share Name" "Enter a **name** for the SMB share:")

# Define paths
SMB_PATH="/srv/smb/$SMB_SHARE_NAME"

# Install dependencies
show_info "Installing Dependencies" "Installing Git and Samba..."
sudo apt update && sudo apt install -y git samba

# Clone the private GitHub repo
show_info "Cloning GitHub Repository" "Fetching the private repository..."
if [ ! -d "$SMB_PATH/.git" ]; then
    sudo mkdir -p "$SMB_PATH"
    sudo git clone https://$GITHUB_TOKEN@github.com/$GITHUB_USER/$GITHUB_REPO.git "$SMB_PATH"
else
    show_info "Repository Exists" "Skipping clone, repo already exists."
fi

# Setup auto-update script
show_info "Setting Up Auto-Pull" "Creating a script to update the repo every 10 minutes..."
echo "#!/bin/bash
cd $SMB_PATH
git pull origin main" | sudo tee /usr/local/bin/update_repo.sh > /dev/null
sudo chmod +x /usr/local/bin/update_repo.sh

# Add cron job for auto-pull
(crontab -l 2>/dev/null | grep -q "update_repo.sh") || (crontab -l 2>/dev/null; echo "*/10 * * * * /usr/local/bin/update_repo.sh") | crontab -

# Configure SMB share
show_info "Configuring Samba" "Adding SMB share entry..."
sudo tee -a /etc/samba/smb.conf > /dev/null <<EOL

[$SMB_SHARE_NAME]
   path = $SMB_PATH
   browseable = yes
   read only = yes
   guest ok = yes
   create mask = 0644
   directory mask = 0755
   force user = nobody
   force group = nogroup
EOL

# Set permissions
show_info "Setting Permissions" "Adjusting directory and file permissions..."
sudo chown -R nobody:nogroup "$SMB_PATH"
sudo chmod -R 755 "$SMB_PATH"

# Restart Samba
show_info "Restarting Samba" "Applying changes..."
sudo systemctl restart smbd
sudo systemctl enable smbd

# Show completion message
show_info "Setup Complete" "SMB Share is ready! Access it via:
Windows:  \\\\$(hostname -I | awk '{print $1}')\\$SMB_SHARE_NAME
Linux/Mac: smb://$(hostname -I | awk '{print $1}')/$SMB_SHARE_NAME
"
