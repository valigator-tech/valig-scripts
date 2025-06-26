#!/bin/bash
check_name="Check-Yellowstone-Jet-Health"
SERVICE="yellowstone-jet"

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
else
    echo "$check_name - Service $SERVICE is running"
fi