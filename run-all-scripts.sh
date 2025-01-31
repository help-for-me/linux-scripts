#!/bin/bash
#
# run-all-scripts.sh
#
# This script performs the following actions:
#
# 1. Optionally runs apt-cacher-ng_mapper.sh to configure apt-cacher-ng.
# 2. Checks if jq (a JSON processor) is installed; if not, prompts the user twice to install it.
# 3. Fetches a list of shell scripts (.sh) from the GitHub repository
#    https://github.com/help-for-me/linux-scripts (only from the repository's root),
#    excluding run-all-scripts.sh and apt-cacher-ng_mapper.sh.
# 4. Displays a menu of the remaining scripts and allows the user to select one or more scripts to run.
#
# Usage:
#   bash run-all-scripts.sh

# --------------------------------------------------
# Step 0: Ask the user if they want to run apt-cacher-ng_mapper.sh.
# --------------------------------------------------
APT_MAPPER_URL="https://raw.githubusercontent.com/help-for-me/linux-scripts/refs/heads/main/apt-cacher-ng_mapper.sh"

read -p "Would you like to run apt-cacher-ng_mapper.sh to configure apt-cacher-ng? (Y/n): " run_mapper_choice
if [[ -z "$run_mapper_choice" || "$run_mapper_choice" =~ ^[Yy]$ ]]; then
    echo "Attempting to run apt-cacher-ng_mapper.sh..."
    if curl -s --head --fail "$APT_MAPPER_URL" > /dev/null; then
        curl -sSL "$APT_MAPPER_URL" | bash
        echo "Finished running apt-cacher-ng_mapper.sh."
    else
        echo "apt-cacher-ng_mapper.sh not found at $APT_MAPPER_URL. Skipping..."
    fi
    echo
else
    echo "Skipping apt-cacher-ng_mapper.sh as per user request."
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
# Step 2: Fetch repository contents from GitHub.
# --------------------------------------------------
REPO_API_URL="https://api.github.com/repos/help-for-me/linux-scripts/contents"
echo "Fetching list of shell scripts from the repository..."
RESPONSE=$(curl -sSL "$REPO_API_URL")
if [ -z "$RESPONSE" ]; then
    echo "Error: Could not fetch repository information."
    exit 1
fi

# --------------------------------------------------
# Step 3: Process repository contents.
# --------------------------------------------------
# Prepare associative arrays to store selectable scripts.
declare -A script_names
declare -A script_urls
index=1

# Filter for files that end with .sh in the repository's root.
# Exclude run-all-scripts.sh (to avoid self-execution) and
# apt-cacher-ng_mapper.sh (since it has been handled above).
SCRIPTS=$(echo "$RESPONSE" | jq -r '.[] | select(.type=="file") | select(.name|endswith(".sh")) | "\(.name) \(.download_url)"')

while IFS= read -r line; do
    # Assume the script name does not include spaces.
    script_name=$(echo "$line" | awk '{print $1}')
    script_url=$(echo "$line" | awk '{print $2}')

    # Exclude run-all-scripts.sh and apt-cacher-ng_mapper.sh
    if [[ "$script_name" == "run-all-scripts.sh" || "$script_name" == "apt-cacher-ng_mapper.sh" ]]; then
        continue
    fi

    # Add the script to our selectable list.
    script_names[$index]="$script_name"
    script_urls[$index]="$script_url"
    ((index++))
done <<< "$SCRIPTS"

# --------------------------------------------------
# Step 4: Display and execute the remaining scripts.
# --------------------------------------------------
if [ ${#script_names[@]} -eq 0 ]; then
    echo "No additional shell scripts found to run."
    exit 0
fi

echo "Available shell scripts:"
for i in "${!script_names[@]}"; do
    echo "  [$i] ${script_names[$i]}"
done

echo
read -p "Enter the number(s) of the script(s) you want to run (e.g., 1 3 5): " selection
selected=($selection)

if [ ${#selected[@]} -eq 0 ]; then
    echo "No scripts selected. Exiting."
    exit 0
fi

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
