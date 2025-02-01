#!/bin/bash
#
# run-all-scripts.sh
#
# This script performs the following actions:
#
# 1. Optionally runs apt-cacher-ng_mapper.sh to configure apt-cacher-ng.
# 2. Ensures that jq (a JSON processor) is available; if not, it exits with an error.
# 3. Ensures that dialog is installed (auto-installs it if missing) so that all interactive prompts use dialog.
# 4. Fetches a list of shell scripts (.sh) from the GitHub repository
#    https://github.com/help-for-me/linux-scripts (only from the repository's root),
#    excluding run-all-scripts.sh and apt-cacher-ng_mapper.sh.
# 5. Displays a dialog checklist of the remaining scripts and allows the user to select one or more to run.
#
# Usage:
#   sudo bash run-all-scripts.sh

# --------------------------------------------------
# Prevent re-running if already launched (for example, if apt-cacher-ng_mapper.sh
# ends by re-invoking run-all-scripts.sh). If the environment variable is already set,
# we assume that we’re in a recursive call and simply exit.
# --------------------------------------------------
if [ -n "$RUN_ALL_SCRIPTS_ALREADY_RUNNING" ]; then
    exit 0
fi
export RUN_ALL_SCRIPTS_ALREADY_RUNNING=1

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
# Step 0: Ask the user if they want to run apt-cacher-ng_mapper.sh using dialog.
# --------------------------------------------------
APT_MAPPER_URL="https://raw.githubusercontent.com/help-for-me/linux-scripts/refs/heads/main/apt-cacher-ng_mapper.sh"

dialog --title "APT Cacher NG Mapper" --yesno "Would you like to run apt-cacher-ng_mapper.sh to configure apt-cacher-ng?" 7 60
response=$?
clear
if [ $response -eq 0 ]; then
    dialog --title "Running Mapper" --infobox "Attempting to run apt-cacher-ng_mapper.sh..." 5 50
    if curl -s --head --fail "$APT_MAPPER_URL" > /dev/null; then
        # Run the mapper. (If the mapper calls run-all-scripts.sh at the end,
        # our guard at the top of this script will prevent a loop.)
        curl -sSL "$APT_MAPPER_URL" | bash
        dialog --title "Mapper Finished" --msgbox "Finished running apt-cacher-ng_mapper.sh." 7 50
    else
        dialog --title "Error" --msgbox "apt-cacher-ng_mapper.sh not found at $APT_MAPPER_URL. Skipping..." 7 50
    fi
else
    dialog --title "Skipped" --msgbox "Skipping apt-cacher-ng_mapper.sh as per user request." 7 50
fi
clear

# --------------------------------------------------
# Step 1: Ensure that jq is installed.
# --------------------------------------------------
if ! command -v jq &>/dev/null; then
    dialog --title "jq Not Found" --msgbox "Error: jq (a JSON processor) is required for this script but is not installed. Aborting." 8 50
    exit 1
fi
clear

# --------------------------------------------------
# Step 2: Fetch repository contents from GitHub.
# --------------------------------------------------
REPO_API_URL="https://api.github.com/repos/help-for-me/linux-scripts/contents"
dialog --title "Fetching Scripts" --infobox "Fetching list of shell scripts from the repository..." 5 60
RESPONSE=$(curl -sSL "$REPO_API_URL")
if [ -z "$RESPONSE" ]; then
    dialog --title "Error" --msgbox "Error: Could not fetch repository information." 8 50
    exit 1
fi
clear

# --------------------------------------------------
# Step 3: Process repository contents.
# --------------------------------------------------
declare -A script_names
declare -A script_urls
index=1

# Get files ending with .sh, excluding run-all-scripts.sh and apt-cacher-ng_mapper.sh.
SCRIPTS=$(echo "$RESPONSE" | jq -r '.[] | select(.type=="file") | select(.name|endswith(".sh")) | "\(.name) \(.download_url)"')

while IFS= read -r line; do
    script_name=$(echo "$line" | awk '{print $1}')
    script_url=$(echo "$line" | awk '{print $2}')
    
    if [[ "$script_name" == "run-all-scripts.sh" || "$script_name" == "apt-cacher-ng_mapper.sh" ]]; then
        continue
    fi
    
    script_names[$index]="$script_name"
    script_urls[$index]="$script_url"
    ((index++))
done <<< "$SCRIPTS"

# --------------------------------------------------
# Step 4: Display and execute the remaining scripts.
# --------------------------------------------------
if [ ${#script_names[@]} -eq 0 ]; then
    dialog --title "No Scripts Found" --msgbox "No additional shell scripts found to run." 7 50
    exit 0
fi

# Build checklist options for dialog.
list_count=${#script_names[@]}
cmd=(dialog --clear --stdout --checklist "Select the scripts to run:" 15 50 "$list_count")
for key in $(echo "${!script_names[@]}" | tr ' ' '\n' | sort -n); do
    cmd+=("$key" "${script_names[$key]}" "off")
done

selections=$("${cmd[@]}")
ret_code=$?
clear
if [ $ret_code -ne 0 ] || [ -z "$selections" ]; then
    dialog --title "No Selection" --msgbox "No scripts selected. Exiting." 7 50
    exit 0
fi

selected=($selections)

for num in "${selected[@]}"; do
    if [[ -z "${script_names[$num]}" ]]; then
        dialog --title "Invalid Selection" --msgbox "Invalid selection: $num. Skipping." 7 50
        continue
    fi
    dialog --title "Running Script" --infobox "Running script: ${script_names[$num]}..." 5 50
    curl -sSL "${script_urls[$num]}" | bash
    dialog --title "Finished" --msgbox "Finished running ${script_names[$num]}." 7 50
    clear
done

dialog --title "Done" --msgbox "All selected scripts have been executed." 7 50
clear
