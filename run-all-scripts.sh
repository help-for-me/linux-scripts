#!/bin/bash
#
# run-all-scripts.sh
#
# This script performs the following actions:
# - Ensures dialog and jq are installed.
# - Asks the user which branch to fetch scripts from.
# - Lists shell scripts in that branch (excluding itself).
# - Lets user pick scripts to run, with apt-cacher-ng_mapper.sh prioritized.
# - Runs selected scripts in isolated subshells.
# Usage: sudo bash run-all-scripts.sh

# --------------------------------------------------
# Prevent recursion
# --------------------------------------------------
if [ "$RUN_ALL_SCRIPTS_RAN" == "1" ]; then
    exit 0
fi
export RUN_ALL_SCRIPTS_RAN=1

# --------------------------------------------------
# Ensure running as root
# --------------------------------------------------
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root: sudo bash $0"
    exit 1
fi

# --------------------------------------------------
# Setup temp file tracking and cleanup
# --------------------------------------------------
temp_files=()
trap 'rm -f "${temp_files[@]}"' EXIT

# --------------------------------------------------
# Remove apt-cacher-ng flag
# --------------------------------------------------
rm -f /tmp/apt_mapper_ran

# --------------------------------------------------
# Ensure dialog and jq are installed
# --------------------------------------------------
missing_pkgs=()
for pkg in dialog jq; do
    if ! command -v "$pkg" &>/dev/null; then
        missing_pkgs+=("$pkg")
    fi
done

if [ ${#missing_pkgs[@]} -ne 0 ]; then
    echo "Installing missing packages: ${missing_pkgs[*]}"
    apt update && apt install -y "${missing_pkgs[@]}"
    for pkg in "${missing_pkgs[@]}"; do
        if ! command -v "$pkg" &>/dev/null; then
            echo "Error: $pkg installation failed. Exiting."
            exit 1
        fi
    done
fi

# --------------------------------------------------
# Ask for branch
# --------------------------------------------------
BRANCH_CHOICE=$(dialog --clear --stdout --menu "Select the branch to fetch scripts from:" 10 50 2 \
    "main" "Stable - Main branch" \
    "test-branch" "Testing - Experimental branch")

clear
if [ -z "$BRANCH_CHOICE" ]; then
    dialog --title "No Selection" --msgbox "No branch selected. Exiting." 7 50
    exit 1
fi

REPO_API_URL="https://api.github.com/repos/help-for-me/linux-scripts/contents?ref=$BRANCH_CHOICE"

# --------------------------------------------------
# Fetch script list
# --------------------------------------------------
dialog --title "Fetching Scripts" --infobox "Fetching list of shell scripts from the $BRANCH_CHOICE branch..." 5 60
RESPONSE=$(curl -sSL -H "Cache-Control: no-cache" "$REPO_API_URL")
if [ -z "$RESPONSE" ]; then
    dialog --title "Error" --msgbox "Error: Could not fetch repository information from $BRANCH_CHOICE branch." 8 50
    exit 1
fi
clear

# --------------------------------------------------
# Parse response into script names + URLs
# --------------------------------------------------
declare -A script_names
declare -A script_urls
index=1

SCRIPTS=$(echo "$RESPONSE" | jq -r '.[] | select(.type=="file") | select(.name|endswith(".sh")) | "\(.name) \(.download_url)"')

while IFS= read -r line; do
    script_name=$(echo "$line" | awk '{print $1}')
    script_url=$(echo "$line" | awk '{print $2}')
    [[ "$script_name" == "run-all-scripts.sh" ]] && continue
    script_names[$index]="$script_name"
    script_urls[$index]="$script_url"
    ((index++))
done <<< "$SCRIPTS"

# --------------------------------------------------
# Let user select scripts
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

selected=($selections)

# --------------------------------------------------
# Run apt-cacher-ng_mapper.sh first if selected
# --------------------------------------------------
for num in "${selected[@]}"; do
    if [[ "${script_names[$num]}" == "apt-cacher-ng_mapper.sh" ]]; then
        dialog --title "Running Script" --infobox "Running apt-cacher-ng_mapper.sh..." 5 50
        sleep 2
        temp_file=$(mktemp)
        temp_files+=("$temp_file")
        curl -sSL -H "Cache-Control: no-cache" "${script_urls[$num]}" -o "$temp_file"
        if [ ! -s "$temp_file" ]; then
            dialog --title "Download Error" --msgbox "Failed to download apt-cacher-ng_mapper.sh. Skipping." 7 50
        else
            chmod +x "$temp_file"
            ( bash "$temp_file" )
        fi
        selected=("${selected[@]/$num}")
        break
    fi
done

# --------------------------------------------------
# Run remaining selected scripts in subshells
# --------------------------------------------------
for num in "${selected[@]}"; do
    [[ -z "$num" ]] && continue
    [[ -z "${script_names[$num]}" ]] && {
        dialog --title "Invalid Selection" --msgbox "Invalid selection: $num. Skipping." 7 50
        continue
    }
    dialog --title "Running Script" --infobox "Running script ${script_names[$num]}..." 5 50
    sleep 2
    temp_file=$(mktemp)
    temp_files+=("$temp_file")
    curl -sSL -H "Cache-Control: no-cache" "${script_urls[$num]}" -o "$temp_file"
    if [ ! -s "$temp_file" ]; then
        dialog --title "Download Error" --msgbox "Failed to download ${script_names[$num]}. Skipping." 7 50
        continue
    fi
    chmod +x "$temp_file"
    ( bash "$temp_file" )
done

dialog --title "All Done" --msgbox "Finished running the selected scripts from $BRANCH_CHOICE." 7 50
clear
