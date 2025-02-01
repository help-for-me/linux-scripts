#!/bin/bash
# install_ssh_fixed.sh
#
# This script ensures that OpenSSH Server is installed and properly configured so that:
#  - It listens on port 22
#  - It listens on all interfaces (i.e. not restricted to localhost)
#
# It then uses dialog to ask if you want to enable root login via SSH,
# warning you that this can be a security risk.
#
# Run this script as root.

# --- Check for root privileges ---
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. Please run it with sudo or as root."
  exit 1
fi

# --- Ensure 'dialog' is installed ---
if ! command -v dialog &> /dev/null; then
  echo "'dialog' is not installed. Installing dialog..."
  apt-get update && apt-get install -y dialog
fi

# --- Install OpenSSH Server if not installed ---
if ! dpkg -l | grep -qw openssh-server; then
  echo "Installing OpenSSH Server..."
  apt-get update && apt-get install -y openssh-server
fi

# --- Start and enable sshd ---
systemctl start sshd
systemctl enable sshd

# --- Fix SSH configuration to listen on port 22 and all interfaces ---

SSH_CONFIG="/etc/ssh/sshd_config"

# 1. Ensure the server listens on port 22.
if grep -qE "^\s*#?\s*Port" "$SSH_CONFIG"; then
  sed -i 's/^\s*#\?\s*Port.*/Port 22/' "$SSH_CONFIG"
else
  echo "Port 22" >> "$SSH_CONFIG"
fi

# 2. Remove any active ListenAddress directives (which might restrict SSH to certain interfaces)
#    and force SSH to listen on all interfaces.
sed -i '/^[[:space:]]*ListenAddress[[:space:]]/d' "$SSH_CONFIG"
if ! grep -q "^ListenAddress 0.0.0.0" "$SSH_CONFIG"; then
  echo "ListenAddress 0.0.0.0" >> "$SSH_CONFIG"
fi

# Restart sshd to apply the above changes.
systemctl restart sshd

# Inform the user that SSH is now listening on port 22 on all interfaces.
dialog --title "SSH Configuration Updated" \
       --msgbox "OpenSSH Server is now configured to listen on port 22 on all interfaces." 8 60

# --- Ask the user whether to enable root login via SSH ---
dialog --title "Enable Root SSH Login" \
       --yesno "WARNING: Enabling root login via SSH poses a significant security risk.\n\nDo you want to enable root login?" 10 60

response=$?

if [ $response -eq 0 ]; then
  # User chose Yes: enable root login.
  if grep -qE "^\s*#?\s*PermitRootLogin" "$SSH_CONFIG"; then
    sed -i 's/^\s*#\?\s*PermitRootLogin.*/PermitRootLogin yes/' "$SSH_CONFIG"
  else
    echo "PermitRootLogin yes" >> "$SSH_CONFIG"
  fi

  # Restart sshd to apply the change.
  systemctl restart sshd

  dialog --title "Root Login Enabled" \
         --msgbox "Root login via SSH has been enabled.\n\nBe aware that this may expose your system to security risks!" 8 60
else
  dialog --title "Root Login Not Enabled" \
         --msgbox "Root login via SSH remains disabled." 8 60
fi

# --- Cleanup ---
clear
exit 0
