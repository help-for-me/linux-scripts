#!/bin/bash
#
# run-all-scripts.sh
#
# This script performs the following actions:
#
# 1. Runs apt-cacher-ng_mapper.sh first (if user agrees).
# 2. Ensures `curl` and `jq` are installed.
# 3. Fetches shell scripts from GitHub and presents a `dialog` selection UI.
# 4. Executes the selected scripts, logging output and handling errors.
#
# Usage:
#   sudo bash run-all-scripts.sh
#

LOCK_FILE="/tmp/run-all-scripts.lock"
TEMP_DIR=$(mktemp -d)  # Create a temp directory for downloaded scripts
LOG_FILE="/var/log/run-all-scripts.log"

# --------------------------------------------------
# Prevent multiple instances
# --------------------------------------------------
if [ -f "$LOCK_FILE" ]; then
    dialog --title "Error" --msgbox "Another instance of this script is already running. Exiting." 7 50
    exit 1
fi
touch "$LOCK_FILE"
trap "rm -f $LOCK_FILE; rm -rf $TEMP_DIR" EXIT  # Cleanup on exit

# --------------------------------------------------
# Ensure curl is installed
# --------------------------------------------------
if ! command -v curl &>/dev/null; then
    echo "curl is missing. Installing it now..."
    sudo apt update && sudo apt install curl -y
    if ! command -v curl &>/dev/null; then
        dialog --title "Error" --msgbox "Failed to install curl. Aborting." 7 50
        exit 1
    fi
fi

# --------------------------------------------------
# Step 1: Run apt-cacher-ng_mapper.sh first
# --------------------------------------------------
APT_MAPPER_URL="https://raw.githubusercontent.com/help-for-me/linux-scripts/refs/heads/main/apt-cacher-ng_mapper.sh"
APT_MAPPER_FLAG="/tmp/apt_mapper_ran"

if [ ! -f "$APT_MAPPER_FLAG" ]; then
    dialog --title "APT Cacher NG Mapper" --yesno "Would you like to run apt-cacher-ng_mapper.sh to configure apt-cacher-ng?" 7 60
    response=$?
    clear
    if [ $response -eq 0 ]; then
        dialog --title "Running Mapper" --infobox "Configuring apt-cacher-ng..." 5 50
        if curl -s --head --fail "$APT_MAPPER_URL" > /dev/null; then
            temp_file=$(mktemp)
            curl -sSL "$APT_MAPPER_URL" -o "$temp_file"
            bash "$temp_file"
            rm -f "$temp_file"
            touch "$APT_MAPPER_FLAG"
            dialog --title "Success" --msgbox "APT Cacher NG is configured!" 7 50
        else
            dialog --title "Error" --msgbox "Could not download apt-cacher-ng_mapper.sh. Skipping..." 7 50
        fi
    else
        dialog --title "Skipped" --msgbox "Skipping apt-cacher-ng_mapper.sh." 7 50
    fi
    clear
fi

# --------------------------------------------------
# Step 2: Ensure jq is installed quietly
# --------------------------------------------------
if ! command -v jq &>/dev/null; then
    # Quietly attempt to install jq
    sudo apt update -qq && sudo apt install -y jq > /dev/null 2>&1
    if ! command -v jq &>/dev/null; then
        dialog --title "Error" --msgbox "Failed to install jq. Aborting." 8 50
        exit 1
    fi
fi
clear

# --------------------------------------------------
# Step 3: Fetch Repository Scripts from GitHub
# --------------------------------------------------
REPO_API_URL="https://api.github.com/repos/help-for-me/linux-scripts/contents"
dialog --title "Fetching Scripts" --infobox "Fetching script list from GitHub..." 5 60

RESPONSE=$(curl -sSL --fail "$REPO_API_URL")
if [ $? -ne 0 ] || [ -z "$RESPONSE" ]; then
    dialog --title "Error" --msgbox "Could not fetch scripts.\nPossible reasons:\n- Network issue\n- GitHub API rate limit exceeded\n\nTry again later." 10 60
    exit 1
fi
clear

# --------------------------------------------------
# Step 4: Process Repository Contents
# --------------------------------------------------
declare -A script_names
declare -A script_urls

SCRIPTS=$(echo "$RESPONSE" | jq -r 'try .[] | select(.type=="file") | select(.name|endswith(".sh")) | "\(.name) \(.download_url)"' 2>/dev/null)
if [ -z "$SCRIPTS" ]; then
    dialog --title "Error" --msgbox "Failed to retrieve scripts from GitHub.\nTry again later." 10 50
    exit 1
fi

while IFS= read -r line; do
    script_name=$(echo "$line" | awk '{print $1}')
    script_url=$(echo "$line" | awk '{print $2}')
    
    if [[ "$script_name" == "run-all-scripts.sh" || "$script_name" == "apt-cacher-ng_mapper.sh" ]]; then
        continue
    fi
    
    script_names["$script_name"]="$script_name"
    script_urls["$script_name"]="$script_url"
done <<< "$SCRIPTS"

# --------------------------------------------------
# Step 5: Select Scripts to Run
# --------------------------------------------------
cmd=(dialog --clear --stdout --title "Select Scripts to Run" \
    --checklist "Use [SPACE] to select scripts. Press [ENTER] to confirm." 20 70 15)

for script_name in "${!script_names[@]}"; do
    cmd+=("$script_name" "" "off")
done

selections=$("${cmd[@]}")
ret_code=$?
clear

if [ $ret_code -eq 1 ] || [ -z "$selections" ]; then
    dialog --title "Exit" --msgbox "No scripts selected. Exiting." 7 50
    exit 0
fi
selected=($selections)

# --------------------------------------------------
# Step 6: Execute Selected Scripts
# --------------------------------------------------
for script_name in "${selected[@]}"; do
    script_url="${script_urls[$script_name]}"
    dialog --title "Running Script" --infobox "Downloading and executing $script_name..." 5 50

    script_path="$TEMP_DIR/$script_name"
    curl -sSL "$script_url" -o "$script_path"

    if [ ! -f "$script_path" ]; then
        dialog --title "Error" --msgbox "Failed to download $script_name. Skipping." 7 50
        echo "$(date): ERROR - Failed to download $script_name" >> "$LOG_FILE"
        continue
    fi

    chmod +x "$script_path"
    output=$("$script_path" 2>&1)
    exit_code=$?

    echo "$(date): Executed $script_name (Exit Code: $exit_code)" >> "$LOG_FILE"
    echo "$output" >> "$LOG_FILE"

    if [ $exit_code -eq 0 ]; then
        dialog --title "Success" --msgbox "$script_name ran successfully." 7 50
    else
        dialog --title "Error" --msgbox "Error running $script_name.\nCheck $LOG_FILE for details." 7 50
    fi
done

dialog --title "Complete" --msgbox "All selected scripts have finished running!" 7 50
