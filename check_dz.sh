#!/bin/bash
check_name="Check-DoubleZero-Health"
SERVICE="doublezerod"
CRIT_PATTERN="bgp: peer closed"

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
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"$message\"}" \
            "$SLACK_WEBHOOK_URL" 2>/dev/null
    fi
}

# Check if the service is active
if ! systemctl is-active --quiet "$SERVICE"; then
    message="$check_name - Service $SERVICE is not running"
    echo "$message"
    #send_slack_alert ":warning: $message"
    send_slack_alert "$message @ $(hostname -s)"
    exit 1
fi

# Get logs from the last 6 minutes
LOG=$(journalctl -u "$SERVICE" --since "6 minutes ago" --no-pager)

# Check for the pattern
if echo "$LOG" | grep -qF "$CRIT_PATTERN"; then
    message="$check_name - BGP Peers Closed - DZ is not active anymore!"
    echo "$message"
    #send_slack_alert ":rotating_light: $message"
    send_slack_alert "$message @ $(hostname -s)"
    
else
    echo "$check_name - BGP Peers established"
fi
