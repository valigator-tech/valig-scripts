#!/bin/bash
check_name="Check-Solana-Health"
SERVICE="sol"
LOG_FILE="/var/log/solana/solana-validator.log"
CRIT_PATTERN="panicked"

# Load environment variables from .env file
if [ -f ".env" ]; then
    source ".env"
else
    echo "ERROR: Missing .env file"
fi

# Function to send message to Slack
send_slack_alert() {
    local message="$1"
    if [ -n "$SLACK_WEBHOOK_URL" ]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"$message\"}" \
            "$SLACK_WEBHOOK_URL" 2>/dev/null
    fi
}

# Check if the service is active
if ! systemctl is-active --quiet "$SERVICE"; then
    message="$check_name - Service $SERVICE is not running"
    echo "$message"
    send_slack_alert "$message @ $(hostname -s)"
    exit 1
fi

# Check if log file exists
if [ ! -f "$LOG_FILE" ]; then
    echo "$check_name - Log file $LOG_FILE not found"
    exit 0
fi

# Get timestamp for 5 minutes ago in ISO format with timezone
FIVE_MIN_AGO=$(date -u -d '5 minutes ago' '+%Y-%m-%dT%H:%M:%S')

# Check for panic in recent logs (looking at timestamps in the log format)
if tail -n 1000000 "$LOG_FILE" | awk -v cutoff="$FIVE_MIN_AGO" -F'[' '{if ($2 > cutoff"Z") print}' | grep -qi "$CRIT_PATTERN"; then
    message="$check_name - PANIC detected in Agave validator logs!"
    echo "$message"
    send_slack_alert "$message @ $(hostname -s)"
# Check for validator restart in recent logs (without panic)
elif tail -n 1000000 "$LOG_FILE" | awk -v cutoff="$FIVE_MIN_AGO" -F'[' '{if ($2 > cutoff"Z") print}' | grep -qi "Starting validator with"; then
    message="$check_name - Validator restarted (without panic)"
    echo "$message"
    send_slack_alert "$message @ $(hostname -s)"
else
    echo "$check_name - Service $SERVICE is running normally"
fi