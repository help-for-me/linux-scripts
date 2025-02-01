#!/bin/bash
# auto_system_update.sh - Schedule automatic system updates with safe reboot handling and Discord notifications.
# This script configures a cron job that runs a separate update script and sends notifications to Discord.

# Unique tag for our cron job.
CRON_JOB_ID="auto_system_update"
# Path to the update script that will be created.
UPDATE_SCRIPT="/usr/local/bin/auto_update.sh"
# Discord webhook URL to send notifications.
WEBHOOK_URL="https://discord.com/api/webhooks/1335108193159741500/-7Ov56uDZgUQS6QMQTujrVcWLccW-IL8U1JvFsfXuyDcOxmuzqaElqGOP7-YrRihbhl6"
# Log file for update operations.
LOG_FILE="/var/log/auto_system_update.log"

# Ensure the script is run as root.
if [ "$(id -u)" -ne 0 ]; then
  dialog --title "Permission Denied" --msgbox "This script must be run as root. Please use sudo or run as root." 7 50
  exit 1
fi

# Ensure dialog is installed.
if ! command -v dialog &> /dev/null; then
  echo "'dialog' is not installed. Installing dialog..."
  apt-get update && apt-get install -y dialog
fi

# --- Check if a scheduled update job already exists ---
EXISTING_CRON=$(crontab -l 2>/dev/null | grep "$CRON_JOB_ID")
if [[ -n "$EXISTING_CRON" ]]; then
  EXISTING_TIME=$(echo "$EXISTING_CRON" | awk '{print $2":"$1}')
  EXISTING_DAYS=$(echo "$EXISTING_CRON" | awk '{print $5}' | tr ',' ' ')
  dialog --title "Existing Update Schedule" --yesno "An automatic update schedule is already set:\n\n⏳ Time: $EXISTING_TIME\n📅 Days: $EXISTING_DAYS\n\nWould you like to update the schedule?" 12 60
  if [ $? -ne 0 ]; then
    dialog --title "No Changes" --msgbox "The existing update schedule remains unchanged." 7 50
    exit 0
  fi
fi

# --- Allow the user to select update days ---
DAYS_SELECTED=$(dialog --title "Select Update Days" --checklist \
"Select the days of the week to run automatic updates (SPACE to select, ENTER to confirm):" 15 50 7 \
1 "Monday" off \
2 "Tuesday" off \
3 "Wednesday" off \
4 "Thursday" off \
5 "Friday" off \
6 "Saturday" off \
7 "Sunday" off 2>&1 >/dev/tty)

if [[ -z "$DAYS_SELECTED" ]]; then
  dialog --title "No Selection" --msgbox "No days selected. Exiting." 7 50
  exit 0
fi

# Convert selected days to cron format (e.g., "1,3,5")
CRON_DAYS=$(echo "$DAYS_SELECTED" | sed 's/ /,/g')

# --- Ask user for update time ---
dialog --title "Set Update Time" --inputbox "Enter the time for updates (24-hour format, e.g., 02:30 for 2:30 AM):" 8 50 2> /tmp/update_time
UPDATE_TIME=$(cat /tmp/update_time)
rm -f /tmp/update_time

# Validate that the time is in proper HH:MM (24-hour) format.
if [[ ! "$UPDATE_TIME" =~ ^([01]?[0-9]|2[0-3]):([0-5][0-9])$ ]]; then
  dialog --title "Invalid Time" --msgbox "Invalid time format. Please use HH:MM (24-hour format)." 7 50
  exit 1
fi

# Extract hour and minute from the update time.
UPDATE_HOUR=$(echo "$UPDATE_TIME" | cut -d':' -f1)
UPDATE_MINUTE=$(echo "$UPDATE_TIME" | cut -d':' -f2)

# --- Create the update script ---
# This script will be executed by cron. It updates the system,
# sends a Discord notification about the update, and handles safe reboots if needed.
cat << 'EOF' > "$UPDATE_SCRIPT"
#!/bin/bash
# auto_update.sh - Runs system updates and sends a Discord notification.

# Log file and webhook URL used for notifications.
LOG_FILE="/var/log/auto_system_update.log"
WEBHOOK_URL="https://discord.com/api/webhooks/1335108193159741500/-7Ov56uDZgUQS6QMQTujrVcWLccW-IL8U1JvFsfXuyDcOxmuzqaElqGOP7-YrRihbhl6"
HOSTNAME=$(hostname)
IP=$(hostname -I | awk '{print $1}')

# --- Run system update and capture output. ---
echo "[$(date)] Running system update..." | tee -a $LOG_FILE
UPDATE_OUTPUT=$(apt update && apt upgrade -y 2>&1)
echo "$UPDATE_OUTPUT" | tee -a $LOG_FILE

# --- Extract a summary line from the output (e.g., "X upgraded") ---
SUMMARY=$(echo "$UPDATE_OUTPUT" | grep -Eo '[0-9]+\s+upgraded' | tail -n1)
[ -z "$SUMMARY" ] && SUMMARY="No packages upgraded."

# --- Prepare Discord notification message. ---
DISCORD_MESSAGE="System Update Completed on Host: $HOSTNAME
IP Address: $IP
Summary: $SUMMARY
Detailed log available on the system."

# --- Send notification to Discord. ---
curl -s -H "Content-Type: application/json" -X POST -d "{\"content\": \"${DISCORD_MESSAGE//\"/\\\"}\"}" "$WEBHOOK_URL" &>/dev/null

# --- Check if a kernel update occurred. ---
# This checks if the running kernel package is still installed.
if ! dpkg --list | grep -q "linux-image-$(uname -r)"; then
    echo "[$(date)] Kernel update detected. Checking for active processes before reboot..." | tee -a $LOG_FILE

    check_critical_processes() {
        # List of processes that should not be interrupted.
        local processes=("apt" "dpkg" "snapd")
        for proc in "${processes[@]}"; do
            if pgrep -x "$proc" > /dev/null; then
                return 1
            fi
        done
        return 0
    }

    # Wait until critical package processes finish.
    while ! check_critical_processes; do
        echo "[$(date)] Waiting for ongoing package operations to complete..." | tee -a $LOG_FILE
        sleep 60
    done

    # Notify about the kernel update and impending reboot.
    REBOOT_MESSAGE="Kernel update detected on Host: $HOSTNAME (IP: $IP). System will reboot now after completing package operations."
    curl -s -H "Content-Type: application/json" -X POST -d "{\"content\": \"${REBOOT_MESSAGE//\"/\\\"}\"}" "$WEBHOOK_URL" &>/dev/null

    echo "[$(date)] Rebooting system..." | tee -a $LOG_FILE
    reboot
fi
EOF

# Make the update script executable.
chmod +x "$UPDATE_SCRIPT"

# --- Remove existing cron job if it exists ---
(crontab -l 2>/dev/null | grep -v "$CRON_JOB_ID") | crontab -

# --- Add new cron job with our unique identifier ---
(crontab -l 2>/dev/null; echo "$UPDATE_MINUTE $UPDATE_HOUR * * $CRON_DAYS $UPDATE_SCRIPT # $CRON_JOB_ID") | crontab -

# --- Confirm setup to the user via a dialog box ---
dialog --title "Automatic Updates Scheduled" --msgbox "System updates will run on the following schedule:\n\n📅 Days: $DAYS_SELECTED\n⏰ Time: $UPDATE_TIME\n\nA kernel update will trigger a safe reboot (after waiting for critical processes).\nA Discord notification will be sent with update details." 12 70

# --- Prepare and send final Discord configuration notification ---
# This sends a summary of the update configuration to Discord.
CONFIG_SUMMARY="**Automatic System Update Configuration Applied**
**Host:** $(hostname)
**IP Address:** $(hostname -I | awk '{print $1}')
**Days Selected:** $DAYS_SELECTED
**Time:** $UPDATE_TIME
**Cron Schedule:** $UPDATE_MINUTE $UPDATE_HOUR * * $CRON_DAYS
**Update Script:** $UPDATE_SCRIPT
**Log File:** $LOG_FILE"

# Construct the JSON payload with proper escaping.
PAYLOAD="{\"content\": \"${CONFIG_SUMMARY//\"/\\\"}\"}"

# Send the payload to Discord.
curl -s -H "Content-Type: application/json" -X POST -d "$PAYLOAD" "$WEBHOOK_URL" &>/dev/null

# Clear the screen and exit.
clear
exit 0
