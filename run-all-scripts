#!/bin/bash
#
# run-all-scripts.sh
#
# This script checks the GitHub repository at:
#   https://github.com/help-for-me/linux-scripts
# and retrieves a list of all shell scripts (.sh) in the repository's root directory.
#
# It then asks the user which script(s) they would like to run, and once the
# user has made their selection(s), downloads and immediately executes the chosen
# script(s) by piping them to Bash.
#
# Usage:
#   bash run-all-scripts.sh

# Ensure that jq is installed.
if ! command -v jq &>/dev/null; then
    echo "Error: 'jq' is required for this script to run."
    echo "Please install jq (e.g., 'sudo apt install jq') and try again."
    exit 1
fi

# Define the GitHub API URL for the repository contents.
REPO_API_URL="https://api.github.com/repos/help-for-me/linux-scripts/contents"

echo "Fetching list of shell scripts from the repository..."
# Get the repository contents in JSON.
RESPONSE=$(curl -sSL "$REPO_API_URL")
if [ -z "$RESPONSE" ]; then
    echo "Error: Could not fetch repository information."
    exit 1
fi

# Filter the JSON for files ending in .sh (in the root directory)
SCRIPTS=$(echo "$RESPONSE" | jq -r '.[] | select(.type=="file") | select(.name|endswith(".sh")) | "\(.name) \(.download_url)"')

# Check if any scripts were found.
if [ -z "$SCRIPTS" ]; then
    echo "No shell scripts found in the repository."
    exit 0
fi

echo "Available shell scripts:"
declare -A script_names
declare -A script_urls

index=1
while IFS= read -r line; do
    # Assume the script name does not include spaces.
    script_name=$(echo "$line" | awk '{print $1}')
    script_url=$(echo "$line" | awk '{print $2}')
    script_names[$index]="$script_name"
    script_urls[$index]="$script_url"
    echo "  [$index] $script_name"
    ((index++))
done <<< "$SCRIPTS"

echo
# Prompt the user to select one or more scripts to run.
read -p "Enter the number(s) of the script(s) you want to run (e.g., 1 3 5): " selection
selected=($selection)

if [ ${#selected[@]} -eq 0 ]; then
    echo "No scripts selected. Exiting."
    exit 0
fi

# Execute each selected script immediately.
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
