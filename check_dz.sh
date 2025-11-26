#!/bin/bash
check_name="Check-DoubleZero-Health"
SERVICE="doublezerod"
CRIT_PATTERN="bgp: peer closed"

# Number of consecutive failures before alerting (5 min cron = 1 check per failure)
ALERT_THRESHOLD=2

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# State file to track consecutive failures
STATE_FILE="/tmp/check_dz_state"

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

# Function to get current failure count from state file
get_failure_count() {
    if [ -f "$STATE_FILE" ]; then
        cat "$STATE_FILE" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Function to check if alert was already sent
alert_was_sent() {
    [ -f "${STATE_FILE}.alerted" ]
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
    # Increment failure count
    FAIL_COUNT=$(get_failure_count)
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "$FAIL_COUNT" > "$STATE_FILE"

    echo "$check_name - BGP Peers Closed detected (count: $FAIL_COUNT/$ALERT_THRESHOLD)"

    # Only alert if threshold reached AND we haven't already alerted
    if [ "$FAIL_COUNT" -ge "$ALERT_THRESHOLD" ] && ! alert_was_sent; then
        message="$check_name - BGP Peers Closed - DZ is not active anymore! (persistent for $((FAIL_COUNT * 5)) min)"
        echo "ALERTING: $message"
        send_slack_alert "$message @ $(hostname -s)"
        touch "${STATE_FILE}.alerted"
    fi
else
    # Clear state on success
    if [ -f "$STATE_FILE" ]; then
        rm -f "$STATE_FILE" "${STATE_FILE}.alerted"
    fi
    echo "$check_name - BGP Peers established"
fi
