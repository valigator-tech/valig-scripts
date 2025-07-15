#!/bin/bash
check_name="Check-Agave-Watchtower-Health"

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment variables from .env file
if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
else
    echo "ERROR: Missing .env file at $SCRIPT_DIR/.env"
    exit 1
fi

# Expected validator identities
VALIDATOR_IDENTITIES=(
    "vALigXFg9wnnhVHN16vNxHxXtAXiBv5QjAE6udoniBY"
    "2m1A2WM1vte7RWz5xTTw4i1SiXmngVtXhqFERaUjoAAb"
    "7tqeaFKsg2K9xKnQWe61w71AtCZVMQvG4hbFAiFAngYw"
)

# Function to send message to Slack
send_slack_alert() {
    local message="$1"
    if [ -n "$SLACK_WEBHOOK_URL" ]; then
        curl -s -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"$message\"}" \
            "$SLACK_WEBHOOK_URL" >/dev/null 2>&1
    fi
}

# Check for each validator identity
missing_processes=()
for identity in "${VALIDATOR_IDENTITIES[@]}"; do
    if ! pgrep -f "agave-watchtower.*--validator-identity $identity" >/dev/null 2>&1; then
        missing_processes+=("$identity")
    fi
done

# Report results
if [ ${#missing_processes[@]} -eq 0 ]; then
    echo "$check_name - All agave-watchtower processes are running"
    
    # Send heartbeat to BetterStack on success
    if [ -n "$BETTERSTACK_HEARTBEAT_WATCHTOWER" ]; then
        curl -s "$BETTERSTACK_HEARTBEAT_WATCHTOWER" >/dev/null 2>&1
        echo "$check_name - Heartbeat sent to BetterStack"
    fi
else
    message="$check_name - Missing agave-watchtower processes for validator identities: ${missing_processes[*]}"
    echo "$message"
    send_slack_alert "$message @ $(hostname -s)"
    exit 1
fi