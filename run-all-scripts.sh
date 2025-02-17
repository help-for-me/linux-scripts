#!/bin/bash
#
# run-all-scripts.sh
#
# This script performs the following actions:
#
# 1. Ensures that jq (a JSON processor) is installed.
# 2. Ensures that dialog is installed (auto-installs it if missing) for interactive prompts.
# 3. Asks the user whether to fetch scripts from the 'main' or 'test-branch'.
# 4. Fetches a list of shell scripts (.sh) from the selected branch of the GitHub repository
#    https://github.com/help-for-me/linux-scripts, excluding run-all-scripts.sh.
# 5. Displays a dialog checklist of the scripts and allows the user to select one or more to run.
# 6. If selected, runs apt-cacher-ng_mapper.sh first (after clearing any local cache),
#    then runs the remaining scripts.
#
# Usage:
#   sudo bash run-all-scripts.sh

# --------------------------------------------------
# Prevent recursion: if this script is re-invoked, exit immediately.
# --------------------------------------------------
if [ "$RUN_ALL_SCRIPTS_RAN" == "1" ]; then
    exit 0
fi
export RUN_ALL_SCRIPTS_RAN=1

# --------------------------------------------------
# Clear any cached/local copies
#
# Remove the apt-cacher-ng_mapper.sh flag file (if exists) to ensure a fresh run.
# --------------------------------------------------
rm -f /tmp/apt_mapper_ran

# --------------------------------------------------
# Preliminary: Ensure that 'dialog' is installed (auto-install if missing)
# --------------------------------------------------
if ! command -v dialog &>/dev/null; then
    echo "Dialog is not installed. Installing dialog..."
    sudo apt update && sudo apt install dialog -y
    if ! command -v dialog &>/dev/null; then
        echo "Error: dialog installation failed. Exiting."
        exit 1
    fi
fi

# --------------------------------------------------
# Step 1: Ask the user which branch to use.
# --------------------------------------------------
BRANCH_CHOICE=$(dialog --clear --stdout --menu "Select the branch to fetch scripts from:" 10 50 2 \
    "main" "Stable - Main branch" \
    "test-branch" "Testing - Experimental branch")

clear
if [ -z "$BRANCH_CHOICE" ]; then
    dialog --title "No Selection" --msgbox "No branch selected. Exiting." 7 50
    exit 1
fi

# Set the repository API URL based on user selection
REPO_API_URL="https://api.github.com/repos/help-for-me/linux-scripts/contents?ref=$BRANCH_CHOICE"

# --------------------------------------------------
# Step 2: Ensure that jq is installed.
# --------------------------------------------------
sudo apt update && sudo apt install jq -y

# --------------------------------------------------
# Step 3: Fetch repository contents from the selected branch.
# --------------------------------------------------
dialog --title "Fetching Scripts" --infobox "Fetching list of shell scripts from the $BRANCH_CHOICE branch..." 5 60
# Use Cache-Control: no-cache to force fetching the latest version
RESPONSE=$(curl -sSL -H "Cache-Control: no-cache" "$REPO_API_URL")
if [ -z "$RESPONSE" ]; then
    dialog --title "Error" --msgbox "Error: Could not fetch repository information from $BRANCH_CHOICE branch." 8 50
    exit 1
fi
clear

# --------------------------------------------------
# Step 4: Process repository contents.
# --------------------------------------------------
declare -A script_names
declare -A script_urls
index=1

# Only exclude run-all-scripts.sh so that apt-cacher-ng_mapper.sh is included.
SCRIPTS=$(echo "$RESPONSE" | jq -r '.[] | select(.type=="file") | select(.name|endswith(".sh")) | "\(.name) \(.download_url)"')

while IFS= read -r line; do
    script_name=$(echo "$line" | awk '{print $1}')
    script_url=$(echo "$line" | awk '{print $2}')
    
    if [[ "$script_name" == "run-all-scripts.sh" ]]; then
        continue
    fi
    
    script_names[$index]="$script_name"
    script_urls[$index]="$script_url"
    ((index++))
done <<< "$SCRIPTS"

# --------------------------------------------------
# Step 5: Display and allow the user to select scripts to run.
# --------------------------------------------------
if [ ${#script_names[@]} -eq 0 ]; then
    dialog --title "No Scripts Found" --msgbox "No additional shell scripts found in the $BRANCH_CHOICE branch." 7 50
    exit 0
fi

list_count=${#script_names[@]}
cmd=(dialog --clear --stdout --extra-button --extra-label "Exit" --checklist "Select the scripts to run from $BRANCH_CHOICE:" 15 50 "$list_count")
for key in $(echo "${!script_names[@]}" | tr ' ' '\n' | sort -n); do
    cmd+=("$key" "${script_names[$key]}" "off")
done

selections=$("${cmd[@]}")
ret_code=$?
clear

if [ $ret_code -eq 3 ]; then
    dialog --title "Exit Selected" --msgbox "Exiting without running any scripts." 7 50
    clear
    exit 0
fi

if [ $ret_code -ne 0 ] || [ -z "$selections" ]; then
    dialog --title "No Selection" --msgbox "No scripts selected. Exiting." 7 50
    exit 0
fi

# Convert selections (space-delimited string) into an array.
selected=($selections)

# --------------------------------------------------
# Step 6: Execute selected scripts.
#
# Run apt-cacher-ng_mapper.sh first if selected, then the remaining scripts.
# --------------------------------------------------
# First, run apt-cacher-ng_mapper.sh if it is among the selections.
for num in "${selected[@]}"; do
    if [[ "${script_names[$num]}" == "apt-cacher-ng_mapper.sh" ]]; then
        dialog --title "Running Script" --infobox "Running apt-cacher-ng_mapper.sh..." 5 50
        sleep 2
        
        temp_file=$(mktemp)
        # Use no-cache header to force downloading the latest version
        curl -sSL -H "Cache-Control: no-cache" "${script_urls[$num]}" -o "$temp_file"
        if [ ! -s "$temp_file" ]; then
            dialog --title "Download Error" --msgbox "Failed to download apt-cacher-ng_mapper.sh. Skipping." 7 50
            rm -f "$temp_file"
        else
            chmod +x "$temp_file"
            bash "$temp_file"
            rm -f "$temp_file"
        fi
        # Remove apt-cacher-ng_mapper.sh from the selection array so it won't run twice.
        selected=("${selected[@]/$num}")
        break
    fi
done

# Now, run all other selected scripts.
for num in "${selected[@]}"; do
    # Skip empty entries (in case the previous loop removed one)
    if [[ -z "$num" ]]; then
        continue
    fi
    if [[ -z "${script_names[$num]}" ]]; then
        dialog --title "Invalid Selection" --msgbox "Invalid selection: $num. Skipping." 7 50
        continue
    fi
    dialog --title "Running Script" --infobox "Running script ${script_names[$num]}..." 5 50
    sleep 2
    
    temp_file=$(mktemp)
    curl -sSL -H "Cache-Control: no-cache" "${script_urls[$num]}" -o "$temp_file"
    
    if [ ! -s "$temp_file" ]; then
        dialog --title "Download Error" --msgbox "Failed to download ${script_names[$num]}. Skipping." 7 50
        rm -f "$temp_file"
        continue
    fi
    
    chmod +x "$temp_file"
    bash "$temp_file"
    rm -f "$temp_file"
done

dialog --title "All Done" --msgbox "Finished running the selected scripts from $BRANCH_CHOICE." 7 50
clear
