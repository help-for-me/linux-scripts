#!/bin/bash
#
# run-all-scripts.sh
#
# This script performs the following actions:
#
# 1. Optionally runs apt-cacher-ng_mapper.sh to configure apt-cacher-ng.
# 2. Ensures that jq (a JSON processor) is installed; if not, it uses a dialog prompt to offer installation.
# 3. Ensures that dialog is installed (auto-installs it if missing) so that all interactive prompts use dialog.
# 4. Fetches a list of shell scripts (.sh) from the GitHub repository
#    https://github.com/help-for-me/linux-scripts (only from the repository's root),
#    excluding run-all-scripts.sh and apt-cacher-ng_mapper.sh.
# 5. Displays a dialog checklist of the remaining scripts and allows the user to select one or more to run.
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
# Step 0: Optionally run apt-cacher-ng_mapper.sh using dialog.
#         Use a flag file to prevent re-running this section.
# --------------------------------------------------
APT_MAPPER_URL="https://raw.githubusercontent.com/help-for-me/linux-scripts/refs/heads/main/apt-cacher-ng_mapper.sh"
APT_MAPPER_FLAG="/tmp/apt_mapper_ran"

if [ ! -f "$APT_MAPPER_FLAG" ]; then
    dialog --title "APT Cacher NG Mapper" --yesno "Would you like to run apt-cacher-ng_mapper.sh to configure apt-cacher-ng?" 7 60
    response=$?
    clear
    if [ $response -eq 0 ]; then
        dialog --title "Running Mapper" --infobox "Attempting to run apt-cacher-ng_mapper.sh..." 5 50
        if curl -s --head --fail "$APT_MAPPER_URL" > /dev/null; then
            # Download to a temporary file and run it.
            temp_file=$(mktemp)
            curl -sSL "$APT_MAPPER_URL" -o "$temp_file"
            bash "$temp_file"
            rm -f "$temp_file"
            # Create a flag file to indicate the mapper has been run.
            touch "$APT_MAPPER_FLAG"
            dialog --title "Mapper Finished" --msgbox "Finished running apt-cacher-ng_mapper.sh." 7 50
        else
            dialog --title "Error" --msgbox "apt-cacher-ng_mapper.sh not found at $APT_MAPPER_URL. Skipping..." 7 50
        fi
    else
        dialog --title "Skipped" --msgbox "Skipping apt-cacher-ng_mapper.sh as per user request." 7 50
    fi
    clear
fi

# --------------------------------------------------
# Step 1: Ensure that jq is installed.
# --------------------------------------------------
sudo apt update && sudo apt install jq -y

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
# Add --extra-button and --extra-label "Exit" to allow exiting directly.
cmd=(dialog --clear --stdout --extra-button --extra-label "Exit" --checklist "Select the scripts to run:" 15 50 "$list_count")
for key in $(echo "${!script_names[@]}" | tr ' ' '\n' | sort -n); do
    cmd+=("$key" "${script_names[$key]}" "off")
done

selections=$("${cmd[@]}")
ret_code=$?
clear

# If the user pressed the extra button, exit.
if [ $ret_code -eq 3 ]; then
    dialog --title "Exit Selected" --msgbox "Exiting without running any scripts." 7 50
    clear
    exit 0
fi

if [ $ret_code -ne 0 ] || [ -z "$selections" ]; then
    dialog --title "No Selection" --msgbox "No scripts selected. Exiting." 7 50
    exit 0
fi

# --------------------------------------------------
# Step 5: Run the selected scripts.
# --------------------------------------------------
selected=($selections)

for num in "${selected[@]}"; do
    if [[ -z "${script_names[$num]}" ]]; then
        dialog --title "Invalid Selection" --msgbox "Invalid selection: $num. Skipping." 7 50
        continue
    fi
    # Inform the user which script is running.
    dialog --title "Running Script" --infobox "Running script ${script_names[$num]}..." 5 50
    sleep 2  # Optional pause so the user can read the message.
    
    # Download the script to a temporary file.
    temp_file=$(mktemp)
    curl -sSL "${script_urls[$num]}" -o "$temp_file"
    
    if [ ! -s "$temp_file" ]; then
        dialog --title "Download Error" --msgbox "Failed to download ${script_names[$num]}. Skipping." 7 50
        rm -f "$temp_file"
        continue
    fi
    
    # Make the script executable and run it.
    chmod +x "$temp_file"
    bash "$temp_file"
    
    # Remove the temporary file after execution.
    rm -f "$temp_file"
done

dialog --title "All Done" --msgbox "Finished running the selected scripts." 7 50
clear
