#!/bin/bash
set -Eeuo pipefail
IFS=$'\n\t'
LC_ALL=C

check_name="Check-BAM-Connection"
LOG_FILE="/var/log/solana/solana.log"

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load environment variables from .env file
if [ -f "$SCRIPT_DIR/.env" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/.env"
else
    echo "ERROR: Missing .env file at $SCRIPT_DIR/.env"
    exit 1
fi

send_slack_alert() {
    local message="$1"
    if [ -n "${SLACK_WEBHOOK_URL:-}" ]; then
        curl -s -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"$message\"}" \
            "$SLACK_WEBHOOK_URL" >/dev/null 2>&1 || true
    fi
}

# Log present?
if [ ! -f "$LOG_FILE" ]; then
    echo "$check_name - Log file $LOG_FILE not found"
    exit 0
fi

# Five minutes ago in UTC (to the second)
FIVE_MIN_AGO="$(date -u -d '5 minutes ago' '+%Y-%m-%dT%H:%M:%S')"

# Scan recent lines once; normalize log timestamps to seconds before comparing.
# The log lines look like:
# [2025-10-09T18:44:55.676610815Z INFO ...] Failed to connect to BAM
read -r HAS_FAILED HAS_LOST < <(
  tail -n 1000000 -- "$LOG_FILE" \
  | awk -F'[][]' -v c="$FIVE_MIN_AGO" '
      BEGIN { IGNORECASE=1; failed=0; lost=0 }
      {
        # $2 begins with the ISO8601 timestamp; drop everything after it (space -> severity)
        ts = $2
        sub(/ .*/, "", ts)                # keep like 2025-10-09T18:44:55.676610815Z
        # Normalize to seconds so lexicographic compare works
        ts = substr(ts, 1, 19) "Z"        # 2025-10-09T18:44:55Z

        if (ts > c "Z") {
          if (index($0, "Failed to connect to BAM") > 0)  failed=1
          if (index($0, "BAM connection lost") > 0)        lost=1
        }
      }
      END { print failed, lost }
    '
)

if [[ "$HAS_FAILED" == "1" ]]; then
    message="$check_name - Failed to connect to BAM detected in logs!"
    echo "$message"
    send_slack_alert "$message @ $(hostname -s)"
elif [[ "$HAS_LOST" == "1" ]]; then
    message="$check_name - BAM connection lost detected in logs!"
    echo "$message"
    send_slack_alert "$message @ $(hostname -s)"
else
    echo "$check_name - No BAM connection issues detected"
fi
