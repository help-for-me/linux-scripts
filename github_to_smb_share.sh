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

# Step 1: Get GitHub credentials
GITHUB_TOKEN=$(get_input "GitHub Authentication" "Enter your **GitHub Personal Access Token**:")
GITHUB_USER=$(get_input "GitHub Username" "Enter your **GitHub username**:")

# Step 2: Fetch all repositories from GitHub
show_info "Fetching Repositories" "Retrieving your GitHub repositories..."
REPO_LIST=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/user/repos?per_page=100" | jq -r '.[].name')

# Step 3: Ask the user to select repositories to share
CHOICES=()
for REPO in $REPO_LIST; do
    CHOICES+=("$REPO" "Share this repo" "off")
done

SELECTED_REPOS=$(get_checklist "Select Repositories" "Use space to select which repositories to share over SMB:" "${CHOICES[@]}")

# Step 4: Install dependencies
show_info "Installing Dependencies" "Installing Git, Samba, and jq..."
sudo apt update && sudo apt install -y git samba jq

# Step 5: Process each selected repository
for REPO_NAME in $SELECTED_REPOS; do
    SMB_SHARE_NAME=$REPO_NAME
    SMB_PATH="/srv/smb/$SMB_SHARE_NAME"

    # Clone the repository
    show_info "Cloning GitHub Repository" "Fetching private repository: $REPO_NAME..."
    if [ ! -d "$SMB_PATH/.git" ]; then
        sudo mkdir -p "$SMB_PATH"
        sudo git clone https://$GITHUB_TOKEN@github.com/$GITHUB_USER/$REPO_NAME.git "$SMB_PATH"
    else
        show_info "Repository Exists" "Skipping clone, $REPO_NAME already exists."
    fi

    # Setup auto-update script
    show_info "Setting Up Auto-Pull" "Creating a script to update $REPO_NAME every 10 minutes..."
    echo "#!/bin/bash
    cd $SMB_PATH
    git pull origin main" | sudo tee /usr/local/bin/update_repo_$REPO_NAME.sh > /dev/null
    sudo chmod +x /usr/local/bin/update_repo_$REPO_NAME.sh

    # Add cron job for auto-pull
    (crontab -l 2>/dev/null | grep -q "update_repo_$REPO_NAME.sh") || (crontab -l 2>/dev/null; echo "*/10 * * * * /usr/local/bin/update_repo_$REPO_NAME.sh") | crontab -

    # Configure SMB share
    show_info "Configuring Samba" "Adding SMB share entry for $REPO_NAME..."
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
    show_info "Setting Permissions" "Adjusting directory and file permissions for $REPO_NAME..."
    sudo chown -R nobody:nogroup "$SMB_PATH"
    sudo chmod -R 755 "$SMB_PATH"

done

# Restart Samba
show_info "Restarting Samba" "Applying changes..."
sudo systemctl restart smbd
sudo systemctl enable smbd

# Show completion message
show_info "Setup Complete" "SMB Shares are ready! Access them via:
Windows:  \\\\$(hostname -I | awk '{print $1}')\\<REPO_NAME>
Linux/Mac: smb://$(hostname -I | awk '{print $1}')/<REPO_NAME>
"
