#!/bin/bash 
# install_ssh_fixed.sh
#
# This script ensures that OpenSSH Server is installed and properly configured so that:
#  - It listens on port 22
#  - It allows root login with password authentication (if enabled)
#
# It then displays the system's local IP for SSH access and ensures UFW allows SSH.

# --- Check for root privileges ---
if [ "$(id -u)" -ne 0 ]; then
  dialog --title "Permission Denied" --msgbox "This script must be run as root. Please use sudo or run as root." 7 50
  exit 1
fi

# --- Ensure 'dialog' is installed ---
if ! command -v dialog &> /dev/null; then
  echo "'dialog' is not installed. Installing dialog..."
  apt-get update && apt-get install -y dialog
fi

# --- Install OpenSSH Server if not installed ---
if ! dpkg -l | grep -qw openssh-server; then
  dialog --title "Installing OpenSSH" --infobox "Installing OpenSSH Server..." 5 50
  apt-get update && apt-get install -y openssh-server
fi

# --- Start and enable SSH if not already running ---
systemctl enable ssh
if ! systemctl is-active --quiet ssh; then
    systemctl start ssh
fi

# --- Configure SSH settings ---
SSH_CONFIG="/etc/ssh/sshd_config"

# 1. Ensure SSH listens on port 22
if grep -qE "^\s*#?\s*Port" "$SSH_CONFIG"; then
  sed -i 's/^\s*#\?\s*Port.*/Port 22/' "$SSH_CONFIG"
else
  echo "Port 22" >> "$SSH_CONFIG"
fi

# 2. Ensure SSH listens on all interfaces
sed -i '/^[[:space:]]*ListenAddress[[:space:]]/d' "$SSH_CONFIG"
if ! grep -q "^ListenAddress 0.0.0.0" "$SSH_CONFIG"; then
  echo "ListenAddress 0.0.0.0" >> "$SSH_CONFIG"
fi

# 3. Ensure password authentication is enabled
if grep -qE "^\s*#?\s*PasswordAuthentication" "$SSH_CONFIG"; then
  sed -i 's/^\s*#\?\s*PasswordAuthentication.*/PasswordAuthentication yes/' "$SSH_CONFIG"
else
  echo "PasswordAuthentication yes" >> "$SSH_CONFIG"
fi

# Restart SSH to apply settings
systemctl restart ssh

# --- Ask user whether to enable root login ---
dialog --title "Enable Root SSH Login" \
       --yesno "WARNING: Enabling root login via SSH with password authentication can be a security risk.\n\nDo you want to enable root login?" 10 60

if [ $? -eq 0 ]; then
  # Enable root login with password
  if grep -qE "^\s*#?\s*PermitRootLogin" "$SSH_CONFIG"; then
    sed -i 's/^\s*#\?\s*PermitRootLogin.*/PermitRootLogin yes/' "$SSH_CONFIG"
  else
    echo "PermitRootLogin yes" >> "$SSH_CONFIG"
  fi

  # Restart SSH to apply changes
  systemctl restart ssh
  dialog --title "Root Login Enabled" --msgbox "Root login via SSH has been enabled with password authentication." 7 50
else
  dialog --title "Root Login Not Enabled" --msgbox "Root login via SSH remains disabled." 7 50
fi

# --- Display the system's local IP for SSH access ---
LOCAL_IP=$(hostname -I | awk '{print $1}')
dialog --title "SSH Access Information" \
       --msgbox "OpenSSH is now configured and running.\n\nTo connect from another machine, use:\n\n  ssh <your-user>@$LOCAL_IP\n\nNote: Replace <your-user> with your actual username." 10 60

# --- Configure UFW (if installed and enabled) ---
if command -v ufw &>/dev/null && systemctl is-active --quiet ufw; then
    dialog --title "Firewall (UFW) Detected" --yesno "UFW (Uncomplicated Firewall) is enabled on this system.\n\nWould you like to allow SSH (port 22) through the firewall?" 10 60

    if [ $? -eq 0 ]; then
        ufw allow 22/tcp
        dialog --title "Firewall Updated" --msgbox "UFW has been updated to allow SSH (port 22)." 7 50
    else
        dialog --title "Warning" --msgbox "SSH access may be blocked by UFW. Ensure port 22 is open before exiting." 8 50
    fi
fi

# Cleanup
clear
exit 0
