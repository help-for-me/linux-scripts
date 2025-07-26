#!/bin/bash
# auto_system_update.sh - Schedule automatic system updates with optional Discord notifications.

CRON_JOB_ID="auto_system_update"
UPDATE_SCRIPT="/usr/local/bin/auto_update.sh"
LOG_FILE="/var/log/auto_system_update.log"
WEBHOOK_CONF="/etc/auto_update_webhook.conf"

if [ "$(id -u)" -ne 0 ]; then
  dialog --title "Permission Denied" --msgbox "This script must be run as root." 6 50
  exit 1
fi

# Ensure dialog is installed
if ! command -v dialog &> /dev/null; then
  apt-get update && apt-get install -y dialog
fi

# Detect existing cron
EXISTING_CRON=$(crontab -l 2>/dev/null | grep "$CRON_JOB_ID")
if [[ -n "$EXISTING_CRON" ]]; then
  EXISTING_TIME=$(echo "$EXISTING_CRON" | awk '{print $2":"$1}')
  EXISTING_DAYS=$(echo "$EXISTING_CRON" | awk '{print $5}' | tr ',' ' ')
  dialog --title "Existing Schedule" --yesno "An update schedule is already set:\n\nTime: $EXISTING_TIME\nDays: $EXISTING_DAYS\n\nWould you like to change it?" 12 60
  [[ $? -ne 0 ]] && dialog --msgbox "No changes made." 6 40 && exit 0
fi

# Select update days
DAYS_SELECTED=$(dialog --title "Select Update Days" --checklist \
"Select the days for automatic updates:" 15 50 7 \
1 "Monday" off 2 "Tuesday" off 3 "Wednesday" off \
4 "Thursday" off 5 "Friday" off 6 "Saturday" off 7 "Sunday" off 2>&1 >/dev/tty)

[[ -z "$DAYS_SELECTED" ]] && dialog --msgbox "No days selected. Exiting." 6 40 && exit 0
CRON_DAYS=$(echo "$DAYS_SELECTED" | sed 's/ /,/g')

# Ask for update time
dialog --title "Set Update Time" --inputbox "Enter time (24h format, e.g., 02:30):" 8 50 2> /tmp/update_time
UPDATE_TIME=$(cat /tmp/update_time)
rm -f /tmp/update_time

[[ ! "$UPDATE_TIME" =~ ^([01]?[0-9]|2[0-3]):([0-5][0-9])$ ]] && dialog --msgbox "Invalid time format." 6 40 && exit 1
UPDATE_HOUR=${UPDATE_TIME%:*}
UPDATE_MINUTE=${UPDATE_TIME#*:}

# Ask whether to enable Discord notifications
dialog --title "Enable Notifications" --yesno "Would you like to receive Discord notifications when updates run?" 7 60
USE_DISCORD=$?

WEBHOOK_URL=""
if [ "$USE_DISCORD" -eq 0 ]; then
  dialog --title "Webhook URL" --inputbox "Enter your Discord webhook URL:" 8 60 2> /tmp/webhook_input
  WEBHOOK_URL=$(cat /tmp/webhook_input)
  rm -f /tmp/webhook_input
  if [[ ! "$WEBHOOK_URL" =~ ^https://discord.com/api/webhooks/ ]]; then
    dialog --msgbox "Invalid Discord webhook URL. Notifications will be disabled." 6 60
    WEBHOOK_URL=""
  fi
fi

# Save webhook to config (or remove it if not used)
[[ -n "$WEBHOOK_URL" ]] && echo "$WEBHOOK_URL" > "$WEBHOOK_CONF" || rm -f "$WEBHOOK_CONF"

# Generate update script
cat << 'EOF' > "$UPDATE_SCRIPT"
#!/bin/bash
LOG_FILE="/var/log/auto_system_update.log"
WEBHOOK_CONF="/etc/auto_update_webhook.conf"
HOSTNAME=$(hostname)
IP=$(hostname -I | awk '{print $1}')

echo "[$(date)] Running system update..." | tee -a "$LOG_FILE"
UPDATE_OUTPUT=$(apt update && apt upgrade -y 2>&1)
echo "$UPDATE_OUTPUT" | tee -a "$LOG_FILE"
SUMMARY=$(echo "$UPDATE_OUTPUT" | grep -Eo '[0-9]+\s+upgraded' | tail -n1)
[ -z "$SUMMARY" ] && SUMMARY="No packages upgraded."

if [ -f "$WEBHOOK_CONF" ]; then
  WEBHOOK_URL=$(cat "$WEBHOOK_CONF")
  MESSAGE="System Update Completed on Host: $HOSTNAME\nIP: $IP\nSummary: $SUMMARY"
  curl -s -H "Content-Type: application/json" -X POST -d "{\"content\": \"${MESSAGE//\"/\\\"}\"}" "$WEBHOOK_URL" &>/dev/null
fi

# Check if kernel update occurred
if ! dpkg --list | grep -q "linux-image-$(uname -r)"; then
  echo "[$(date)] Kernel update detected. Waiting for critical processes..." | tee -a "$LOG_FILE"
  check_critical_processes() {
    for proc in apt dpkg snapd; do
      pgrep -x "$proc" >/dev/null && return 1
    done
    return 0
  }
  while ! check_critical_processes; do
    sleep 60
  done
  if [ -f "$WEBHOOK_CONF" ]; then
    REBOOT_MSG="Kernel update detected on $HOSTNAME ($IP). Rebooting now."
    curl -s -H "Content-Type: application/json" -X POST -d "{\"content\": \"${REBOOT_MSG//\"/\\\"}\"}" "$WEBHOOK_URL" &>/dev/null
  fi
  echo "[$(date)] Rebooting..." | tee -a "$LOG_FILE"
  reboot
fi
EOF

chmod +x "$UPDATE_SCRIPT"

# Update cron
(crontab -l 2>/dev/null | grep -v "$CRON_JOB_ID") | crontab -
(crontab -l 2>/dev/null; echo "$UPDATE_MINUTE $UPDATE_HOUR * * $CRON_DAYS $UPDATE_SCRIPT # $CRON_JOB_ID") | crontab -

# Final confirmation
dialog --title "Automatic Updates Scheduled" --msgbox "Updates scheduled:\nDays: $DAYS_SELECTED\nTime: $UPDATE_TIME\n\nKernel updates will trigger safe reboots.\nDiscord notifications: $( [[ -n "$WEBHOOK_URL" ]] && echo Enabled || echo Disabled )" 10 60
clear
exit 0
