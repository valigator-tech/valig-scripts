#!/bin/bash
check_name="Check-Yellowstone-Jet-Health"
SERVICE="yellowstone-jet"

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment variables from .env file
if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
else
    echo "ERROR: Missing .env file at $SCRIPT_DIR/.env"
    exit 1
fi


# Function to send message to Slack
send_slack_alert() {
    local message="$1"
    if [ -n "$SLACK_WEBHOOK_URL" ]; then
        curl -s -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"$message\"}" \
            "$SLACK_WEBHOOK_URL" >/dev/null 2>&1
    fi
}

# Check if the service is active
if ! systemctl is-active --quiet "$SERVICE"; then
    message="$check_name - Service $SERVICE is not running"
    echo "$message"
    send_slack_alert "$message @ $(hostname -s)"
    exit 1
else
    echo "$check_name - Service $SERVICE is running"
fi