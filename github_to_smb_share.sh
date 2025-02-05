#!/bin/bash

# Function to display a dialog-based menu
show_menu() {
    dialog --clear --title "$1" --menu "$2" 15 60 4 "${@:3}" 2>&1 >/dev/tty
}

# Function to get user input
get_input() {
    dialog --clear --title "$1" --inputbox "$2" 10 60 2>&1 >/dev/tty
}

# Function to display a checklist
get_checklist() {
    dialog --clear --title "$1" --checklist "$2" 15 60 10 "${@:3}" 2>&1 >/dev/tty
}

# Function to show an info box
show_info() {
    dialog --clear --title "$1" --msgbox "$2" 10 60
}

# Step 1: Ask the user if they want to map a public repo or all private repos
CHOICE=$(show_menu "Repository Mapping" "Do you want to map a public repo or all personal repositories?" \
    1 "Map a Public Repo (Enter Link)" \
    2 "Map All Personal Repositories")

if [ "$CHOICE" == "1" ]; then
    # Public Repo Mode
    PUBLIC_REPO_URL=$(get_input "Public Repo URL" "Enter the full GitHub repository URL (e.g., https://github.com/user/repo):")
    GITHUB_USER=$(echo "$PUBLIC_REPO_URL" | awk -F'/' '{print $(NF-1)}')
    GITHUB_REPO=$(echo "$PUBLIC_REPO_URL" | awk -F'/' '{print $NF}' | sed 's/.git$//')

    # Ensure variables are set
    if [[ -z "$GITHUB_USER" || -z "$GITHUB_REPO" ]]; then
        show_info "Error" "Invalid GitHub repository URL provided."
        exit 1
    fi

    SELECTED_REPOS=("$GITHUB_REPO")
    
elif [ "$CHOICE" == "2" ]; then
    # Private Repo Mode
    GITHUB_TOKEN=$(get_input "GitHub Authentication" "Enter your **GitHub Personal Access Token**:")
    GITHUB_USER=$(get_input "GitHub Username" "Enter your **GitHub username**:")

    # Step 2: Fetch all repositories from GitHub
    show_info "Fetching Repositories" "Retrieving your GitHub repositories..."
    PAGE=1
    REPO_LIST=()
    
    while true; do
        RESPONSE=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/user/repos?per_page=100&page=$PAGE")
        COUNT=$(echo "$RESPONSE" | jq length)
        
        if [ "$COUNT" -eq 0 ]; then
            break
        fi

        REPO_NAMES=$(echo "$RESPONSE" | jq -r '.[].name')
        for REPO in $REPO_NAMES; do
            REPO_LIST+=("$REPO" "Share this repo" "off")
        done

        PAGE=$((PAGE + 1))
    done

    # Step 3: Ask the user to select repositories to share
    SELECTED_REPOS=$(get_checklist "Select Repositories" "Use space to
