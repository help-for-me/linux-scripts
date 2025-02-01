#!/bin/bash
# setup_ssh.sh
#
# This script checks if SSH is running, installs OpenSSH Server if needed,
# and then uses a dialog box to ask whether to enable root login via SSH.
# Enabling root login is a security risk, so the user is warned accordingly.

# --- Ensure the script is run as root ---
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. Please run it with sudo or as root."
  exit 1
fi

# --- Ensure 'dialog' is installed (it provides nice interactive dialog boxes) ---
if ! command -v dialog &> /dev/null; then
  echo "'dialog' is not installed. Installing dialog..."
  apt-get update && apt-get install -y dialog
fi

# --- Check if SSH is running (by looking for the sshd process) ---
if pgrep -x "sshd" > /dev/null; then
  echo "SSH (sshd) is running."
else
  echo "SSH (sshd) is not running. Installing openssh-server..."
  apt-get update
  apt-get install -y openssh-server
  # Start and enable the SSH service
  systemctl start sshd
  systemctl enable sshd
fi

# --- Ask the user whether to enable root login via SSH ---
dialog --title "Enable Root SSH Login" \
       --yesno "WARNING: Enabling root login via SSH can be a significant security risk.\n\nDo you want to enable root login via SSH?" 10 60

# Capture the exit status of the dialog command:
#   0 = Yes, 1 = No, 255 = Cancel/ESC.
response=$?

if [ $response -eq 0 ]; then
  # User chose Yes: enable root login.
  # Modify /etc/ssh/sshd_config: change any existing PermitRootLogin setting,
  # whether commented out or not, to "PermitRootLogin yes".
  if grep -q -E "^#?PermitRootLogin" /etc/ssh/sshd_config; then
    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
  else
    # If the line does not exist, append it to the file.
    echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
  fi

  # Restart the SSH service so that the changes take effect.
  systemctl restart sshd

  dialog --title "Configuration Updated" \
         --msgbox "Root login via SSH has been enabled.\n\nWARNING: This configuration poses a security risk!" 8 60
else
  # User chose No (or canceled): do nothing.
  dialog --title "Configuration Unchanged" \
         --msgbox "Root login via SSH remains disabled." 8 60
fi

# Clear the screen after using dialog.
clear
