#!/bin/bash

# Function to display a checklist
get_checklist() {
    dialog --clear --title "$1" --checklist "$2" 15 60 10 "${@:3}" 2>&1 >/dev/tty
}

# Function to get user input
get_input() {
    dialog --clear --title "$1" --inputbox "$2" 10 60 2>&1 >/dev/tty
}

# Function to show an info box
show_info() {
    dialog --clear --title "$1" --msgbox "$2" 10 60
}

# Step 1: Get GitHub credentials
GITHUB_TOKEN=$(get_input "GitHub Authentication" "Enter your **GitHub Personal Access Token**:")
GITHUB_USER=$(get_input "GitHub Username" "Enter your **GitHub username**:")

# Step 2: Fetch user's repositories from GitHub (with pagination)
show_info "Fetching Repositories" "Retrieving your GitHub repositories..."
PAGE=1
USER_REPOS=()
while true; do
    RESPONSE=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/user/repos?per_page=100&page=$PAGE")
    COUNT=$(echo "$RESPONSE" | jq length)
    
    if [ "$COUNT" -eq 0 ]; then
        break
    fi

    while IFS= read -r REPO_NAME; do
        USER_REPOS+=("$REPO_NAME" "Owned by $GITHUB_USER" "off")
    done < <(echo "$RESPONSE" | jq -r '.[].name')

    PAGE=$((PAGE + 1))
done

# Step 3: Allow the user to select their own repositories
SELECTED_USER_REPOS=$(get_checklist "Select Your Repositories" "Use space to select which repositories to share:" "${USER_REPOS[@]}")

# Step 4: Ask user for additional public repositories
PUBLIC_REPOS=()
while true; do
    PUBLIC_REPO=$(get_input "Add Public Repo" "Enter a public GitHub repo in the format **owner/repo** (or leave blank to finish):")
    if [[ -z "$PUBLIC_REPO" ]]; then
        break
    fi
    PUBLIC_REPOS+=("$PUBLIC_REPO")
done

# Step 5: Install dependencies
show_info "Installing Dependencies" "Installing Git, Samba, and jq..."
sudo apt update && sudo apt install -y git samba jq

# Step 6: Set up directories
USER_REPO_PATH="/srv/smb/user_repos"
PUBLIC_REPO_PATH="/srv/smb/public_repos"

sudo mkdir -p "$USER_REPO_PATH"
sudo mkdir -p "$PUBLIC_REPO_PATH"

# Step 7: Clone and set up user's repositories
for REPO_NAME in $SELECTED_USER_REPOS; do
    REPO_PATH="$USER_REPO_PATH/$REPO_NAME"

    show_info "Cloning Repository" "Fetching $REPO_NAME into $USER_REPO_PATH..."
    if [ ! -d "$REPO_PATH/.git" ]; then
        sudo git clone https://$GITHUB_TOKEN@github.com/$GITHUB_USER/$REPO_NAME.git "$REPO_PATH"
    else
        show_info "Repository Exists" "Skipping clone, $REPO_NAME already exists."
    fi

    # Set up auto-update script
    echo "#!/bin/bash
cd $REPO_PATH
git pull origin main" | sudo tee /usr/local/bin/update_repo_$REPO_NAME.sh > /dev/null
    sudo chmod +x /usr/local/bin/update_repo_$REPO_NAME.sh

    # Add cron job for auto-pull
    (crontab -l 2>/dev/null | grep -q "update_repo_$REPO_NAME.sh") || (crontab -l 2>/dev/null; echo "*/10 * * * * /usr/local/bin/update_repo_$REPO_NAME.sh") | crontab -
done

# Step 8: Clone and set up public repositories
for PUBLIC_REPO in "${PUBLIC_REPOS[@]}"; do
    REPO_NAME=$(basename "$PUBLIC_REPO")
    REPO_PATH="$PUBLIC_REPO_PATH/$REPO_NAME"

    show_info "Cloning Public Repository" "Fetching $PUBLIC_REPO into $PUBLIC_REPO_PATH..."
    if [ ! -d "$REPO_PATH/.git" ]; then
        sudo git clone https://github.com/$PUBLIC_REPO.git "$REPO_PATH"
    else
        show_info "Repository Exists" "Skipping clone, $REPO_NAME already exists."
    fi

    # Set up auto-update script
    echo "#!/bin/bash
cd $REPO_PATH
git pull origin main" | sudo tee /usr/local/bin/update_repo_$REPO_NAME.sh > /dev/null
    sudo chmod +x /usr/local/bin/update_repo_$REPO_NAME.sh

    # Add cron job for auto-pull
    (crontab -l 2>/dev/null | grep -q "update_repo_$REPO_NAME.sh") || (crontab -l 2>/dev/null; echo "*/10 * * * * /usr/local/bin/update_repo_$REPO_NAME.sh") | crontab -
done

# Step 9: Configure Samba for both repo folders
show_info "Configuring Samba" "Setting up SMB shares..."
sudo tee -a /etc/samba/smb.conf > /dev/null <<EOL

[user_repos]
   path = $USER_REPO_PATH
   browseable = yes
   read only = yes
   guest ok = yes
   create mask = 0644
   directory mask = 0755
   force user = nobody
   force group = nogroup

[public_repos]
   path = $PUBLIC_REPO_PATH
   browseable = yes
   read only = yes
   guest ok = yes
   create mask = 0644
   directory mask = 0755
   force user = nobody
   force group = nogroup
EOL

# Step 10: Set permissions and restart Samba
show_info "Applying Permissions" "Adjusting directory and file permissions..."
sudo chown -R nobody:nogroup "$USER_REPO_PATH"
sudo chmod -R 755 "$USER_REPO_PATH"
sudo chown -R nobody:nogroup "$PUBLIC_REPO_PATH"
sudo chmod -R 755 "$PUBLIC_REPO_PATH"

show_info "Restarting Samba" "Applying changes..."
sudo systemctl restart smbd
sudo systemctl enable smbd

# Step 11: Show success message with share paths
show_info "Setup Complete" "SMB Shares are ready! Access them via:
Windows:  \\\\$(hostname -I | awk '{print $1}')\\user_repos
Linux/Mac: smb://$(hostname -I | awk '{print $1}')/user_repos
Windows:  \\\\$(hostname -I | awk '{print $1}')\\public_repos
Linux/Mac: smb://$(hostname -I | awk '{print $1}')/public_repos"