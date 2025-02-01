#!/bin/bash
#
# run-all-scripts.sh
#
# This script performs the following actions:
#
# Step 0: Optionally run the APT Cacher NG Installer (install-apt-cacher-dialog.sh) to configure apt-cacher-ng.
# Step 1: Ensure that jq (a JSON processor) is installed.
# Step 2: Optionally ensure that dialog is installed for interactive script selection.
# Step 3: Fetch a list of shell scripts (.sh) from the GitHub repository
#         https://github.com/help-for-me/linux-scripts (only from the repository's root),
#         excluding run-all-scripts.sh and install-apt-cacher-dialog.sh.
# Step 4: Display a checklist of the remaining scripts and allow the user to select one or more scripts to run.
#
# Usage:
#   bash run-all-scripts.sh

# --------------------------------------------------
# Step 0: Ask the user if they want to run the APT Cacher NG Installer.
# --------------------------------------------------
# Updated URL now points to install-apt-cacher-dialog.sh.
APT_INSTALLER_URL="https://raw.githubusercontent.com/help-for-me/linux-scripts/refs/heads/main/install-apt-cacher-dialog.sh"

read -p "Would you like to run the APT Cacher NG Installer (install-apt-cacher-dialog.sh) to configure apt-cacher-ng? (Y/n): " run_installer_choice
if [[ -z "$run_installer_choice" || "$run_installer_choice" =~ ^[Yy]$ ]]; then
    echo "Attempting to run install-apt-cacher-dialog.sh..."
    # Create a temporary file for the installer.
    TMP_INSTALLER=$(mktemp)
    
    # Download the installer to the temporary file.
    curl -sSL "$APT_INSTALLER_URL" -o "$TMP_INSTALLER"
    
    # Run the installer using sudo.
    sudo bash "$TMP_INSTALLER" || true
    
    # Remove the temporary file.
    rm -f "$TMP_INSTALLER"
    
    echo "Finished running install-apt-cacher-dialog.sh."
    echo
else
    echo "Skipping the APT Cacher NG Installer as per user request."
    echo
fi

# --------------------------------------------------
# Step 1: Ensure that jq is installed.
# --------------------------------------------------
if ! command -v jq &>/dev/null; then
    echo "This script requires jq (a JSON processor) to function."
    echo "Without jq, we cannot parse the repository contents."
    read -p "Would you like to install jq? (Y/n): " install_jq
    if [[ -z "$install_jq" || "$install_jq" =~ ^[Yy]$ ]]; then
        echo "Installing jq..."
        sudo apt update && sudo apt install jq -y
        if ! command -v jq &>/dev/null; then
            echo "Error: jq installation failed. Aborting."
            exit 1
        fi
    else
        echo "jq is required for this script. Without installing jq, the script will be aborted."
        read -p "Would you like to install jq now? (Y/n): " install_jq_again
        if [[ -z "$install_jq_again" || "$install_jq_again" =~ ^[Yy]$ ]]; then
            echo "Installing jq..."
            sudo apt update && sudo apt install jq -y
            if ! command -v jq &>/dev/null; then
                echo "Error: jq installation failed. Aborting."
                exit 1
            fi
        else
            echo "jq is required for this script. Aborting."
            exit 1
        fi
    fi
fi

# --------------------------------------------------
# Step 2: Ensure that dialog is installed (optional).
# --------------------------------------------------
if ! command -v dialog &>/dev/null; then
    read -p "The script uses 'dialog' for interactive selection, which is not installed. Would you like to install it? (Y/n): " install_dialog
    if [[ -z "$install_dialog" || "$install_dialog" =~ ^[Yy]$ ]]; then
        echo "Installing dialog..."
        sudo apt update && sudo apt install dialog -y
        if ! command -v dialog &>/dev/null; then
            echo "Error: dialog installation failed. Falling back to text-based selection."
        fi
    else
        echo "dialog is not installed. Falling back to text-based selection."
    fi
fi

# --------------------------------------------------
# Step 3: Fetch repository contents from GitHub.
# --------------------------------------------------
REPO_API_URL="https://api.github.com/repos/help-for-me/linux-scripts/contents"
echo "Fetching list of shell scripts from the repository..."
RESPONSE=$(curl -sSL "$REPO_API_URL")
if [ -z "$RESPONSE" ]; then
    echo "Error: Could not fetch repository information."
    exit 1
fi

# --------------------------------------------------
# Step 4: Process repository contents.
# --------------------------------------------------
# We'll store selectable scripts using associative arrays.
declare -A script_names
declare -A script_urls
index=1

# Filter for files that end with .sh in the repository's root.
# Exclude run-all-scripts.sh (to avoid self-execution) and
# install-apt-cacher-dialog.sh (since it has been handled above).
SCRIPTS=$(echo "$RESPONSE" | jq -r '.[] | select(.type=="file") | select(.name|endswith(".sh")) | "\(.name) \(.download_url)"')

while IFS= read -r line; do
    # Assume the script name does not include spaces.
    script_name=$(echo "$line" | awk '{print $1}')
    script_url=$(echo "$line" | awk '{print $2}')

    # Exclude run-all-scripts.sh and install-apt-cacher-dialog.sh
    if [[ "$script_name" == "run-all-scripts.sh" || "$script_name" == "install-apt-cacher-dialog.sh" ]]; then
        continue
    fi

    # Add the script to our selectable list.
    script_names[$index]="$script_name"
    script_urls[$index]="$script_url"
    ((index++))
done <<< "$SCRIPTS"

# --------------------------------------------------
# Step 5: Display and execute the remaining scripts.
# --------------------------------------------------
if [ ${#script_names[@]} -eq 0 ]; then
    echo "No additional shell scripts found to run."
    exit 0
fi

# Use dialog if available; otherwise, fallback to text input.
if command -v dialog &>/dev/null; then
    # Prepare the checklist items.
    list_count=${#script_names[@]}
    cmd=(dialog --clear --stdout --checklist "Select the scripts to run:" 15 50 "$list_count")
    # Loop over keys in numerical order.
    for key in $(echo "${!script_names[@]}" | tr ' ' '\n' | sort -n); do
        cmd+=("$key" "${script_names[$key]}" "off")
    done

    selections=$("${cmd[@]}")
    ret_code=$?
    # Clear the dialog from the screen.
    clear
    if [ $ret_code -ne 0 ] || [ -z "$selections" ]; then
        echo "No scripts selected. Exiting."
        exit 0
    fi

    # The selections are returned as a space-separated list of keys.
    selected=($selections)
else
    echo "Available shell scripts:"
    for key in $(echo "${!script_names[@]}" | tr ' ' '\n' | sort -n); do
        echo "  [$key] ${script_names[$key]}"
    done
    echo
    read -p "Enter the number(s) of the script(s) you want to run (e.g., 1 3 5): " selection
    selected=($selection)
fi

# Execute each selected script.
for num in "${selected[@]}"; do
    if [[ -z "${script_names[$num]}" ]]; then
        echo "Invalid selection: $num. Skipping."
        continue
    fi
    echo "----------------------------------------"
    echo "Running script: ${script_names[$num]}"
    echo "----------------------------------------"
    curl -sSL "${script_urls[$num]}" | bash
    echo "Finished running ${script_names[$num]}"
    echo
done

echo "All selected scripts have been executed."
