#!/bin/bash

GITHUB_TOKEN="YOUR_GITHUB_TOKEN"  # Replace with your GitHub token
GITHUB_USER="YOUR_GITHUB_USERNAME"  # Replace with your GitHub username
SMB_BASE_PATH="/srv/smb"
CRON_JOB_PATH="/usr/local/bin/github_auto_sync.sh"

# Function to display a dialog-based menu
show_menu() {
    dialog --clear --title "$1" --menu "$2" 15 60 4 "${@:3}" 2>&1 >/dev/tty
}

# Function to get user input
get_input() {
    dialog --clear --title "$1" --inputbox "$2" 10 60 2>&1 >/dev/tty
}

# Function to show an info box
show_info() {
    dialog --clear --title "$1" --msgbox "$2" 10 60
}

# Fetch the current cron job (if any)
CURRENT_CRON=$(crontab -l 2>/dev/null | grep "$CRON_JOB_PATH")

# If the script has been run before, ask if the user wants to update the schedule
if [[ -n "$CURRENT_CRON" ]]; then
    CHANGE_SCHEDULE=$(show_menu "Cron Job Detected" "You already have a scheduled sync. Do you want to change it?" \
        1 "Yes - Change Sync Frequency" \
        2 "No - Keep Existing Schedule")

    if [[ "$CHANGE_SCHEDULE" == "2" ]]; then
        show_info "Keeping Existing Schedule" "Your existing sync schedule will remain unchanged."
        exit 0
    fi
fi

# Ask the user how often they want to sync
SYNC_FREQUENCY=$(show_menu "Set Sync Frequency" "How often should GitHub repos sync?" \
    "*/5 * * * *" "Every 5 minutes" \
    "*/10 * * * *" "Every 10 minutes (Default)" \
    "*/15 * * * *" "Every 15 minutes" \
    "0 * * * *" "Every hour" \
    "0 */6 * * *" "Every 6 hours" \
    "0 0 * * *" "Once per day")

# Remove any existing cron job
crontab -l | grep -v "$CRON_JOB_PATH" | crontab -

# Add the new cron job
(crontab -l 2>/dev/null; echo "$SYNC_FREQUENCY $CRON_JOB_PATH") | crontab -

show_info "Sync Frequency Set" "GitHub repo sync will now run on the following schedule:\n$SYNC_FREQUENCY"

# Step 1: Fetch the latest repository list from GitHub
echo "🔄 Fetching repository list from GitHub..."
PAGE=1
REMOTE_REPOS=()

while true; do
    RESPONSE=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/user/repos?per_page=100&page=$PAGE")
    COUNT=$(echo "$RESPONSE" | jq length)
    
    if [ "$COUNT" -eq 0 ]; then
        break
    fi

    REPO_NAMES=$(echo "$RESPONSE" | jq -r '.[].name')
    for REPO in $REPO_NAMES; do
        REMOTE_REPOS+=("$REPO")
    done

    PAGE=$((PAGE + 1))
done

echo "✅ Found ${#REMOTE_REPOS[@]} repositories."

# Get the list of currently shared SMB repositories
LOCAL_REPOS=($(ls "$SMB_BASE_PATH"))

# Find repositories to remove (exist locally but not on GitHub)
REMOVE_REPOS=()
for LOCAL_REPO in "${LOCAL_REPOS[@]}"; do
    if [[ ! " ${REMOTE_REPOS[*]} " =~ " $LOCAL_REPO " ]]; then
        REMOVE_REPOS+=("$LOCAL_REPO")
    fi
done

# Find repositories to add (exist on GitHub but not locally)
ADD_REPOS=()
for REMOTE_REPO in "${REMOTE_REPOS[@]}"; do
    if [[ ! " ${LOCAL_REPOS[*]} " =~ " $REMOTE_REPO " ]]; then
        ADD_REPOS+=("$REMOTE_REPO")
    fi
done

# Remove repositories that no longer exist on GitHub
for REPO in "${REMOVE_REPOS[@]}"; do
    echo "❌ Removing $REPO from SMB share..."
    sudo sed -i "/^\[$REPO\]/,/^$/d" /etc/samba/smb.conf
    sudo rm -rf "$SMB_BASE_PATH/$REPO"
done

# Add new repositories
for REPO in "${ADD_REPOS[@]}"; do
    echo "➕ Adding $REPO to SMB share..."
    REPO_PATH="$SMB_BASE_PATH/$REPO"
    sudo mkdir -p "$REPO_PATH"
    sudo git clone "https://$GITHUB_TOKEN@github.com/$GITHUB_USER/$REPO.git" "$REPO_PATH"

    # Configure Samba for the new repo
    echo "[$REPO]
    path = $REPO_PATH
    browseable = yes
    read only = yes
    guest ok = yes
    create mask = 0644
    directory mask = 0755
    force user = nobody
    force group = nogroup
    " | sudo tee -a /etc/samba/smb.conf > /dev/null
done

# Restart Samba if changes were made
if [[ ${#REMOVE_REPOS[@]} -gt 0 || ${#ADD_REPOS[@]} -gt 0 ]]; then
    echo "♻️ Restarting Samba service..."
    sudo systemctl restart smbd
fi

echo "✅ SMB share sync complete!"
