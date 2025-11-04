#!/bin/bash
set -Eeuo pipefail
IFS=$'\n\t'
LC_ALL=C

check_name="Check-BAM-Connection"
LOG_FILE="/var/log/solana/solana-validator.log"

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
# Handle both GNU date (Linux) and BSD date (macOS)
if date --version >/dev/null 2>&1; then
    # GNU date
    FIVE_MIN_AGO="$(date -u -d '5 minutes ago' '+%Y-%m-%dT%H:%M:%S')"
else
    # BSD date (macOS)
    FIVE_MIN_AGO="$(date -u -v-5M '+%Y-%m-%dT%H:%M:%S')"
fi

# Debug output (set DEBUG=1 to enable)
if [[ "${DEBUG:-0}" == "1" ]]; then
    echo "DEBUG: FIVE_MIN_AGO=$FIVE_MIN_AGO"
    echo "DEBUG: Current time=$(date -u '+%Y-%m-%dT%H:%M:%S')"
    echo "DEBUG: Checking last 5 min for errors..."
fi

# Scan recent lines once; normalize log timestamps to seconds before comparing.
# The log lines look like:
# [2025-10-09T18:44:55.676610815Z INFO ...] Failed to connect to BAM
# Temporarily use default IFS for read to split on space
IFS=' ' read -r HAS_FAILED HAS_LOST NOT_ON_SCHEDULE < <(
  tail -n 1000000 -- "$LOG_FILE" \
  | awk -F'[][]' -v c="$FIVE_MIN_AGO" -v debug="${DEBUG:-0}" '
      BEGIN { IGNORECASE=1; failed=0; lost=0; not_on_schedule=0 }
      {
        # $2 begins with the ISO8601 timestamp; drop everything after it (space -> severity)
        ts = $2
        sub(/ .*/, "", ts)                # keep like 2025-10-09T18:44:55.676610815Z
        # Normalize to seconds so lexicographic compare works
        ts = substr(ts, 1, 19) "Z"        # 2025-10-09T18:44:55Z

        cutoff = c "Z"
        if (ts > cutoff) {
          if (index($0, "Failed to connect to BAM") > 0) {
            failed=1
            if (debug == "1") print "DEBUG: Found BAM failure at", ts > "/dev/stderr"
          }
          if (index($0, "BAM connection lost") > 0) {
            lost=1
            if (debug == "1") print "DEBUG: Found BAM lost at", ts > "/dev/stderr"
          }
          if (index($0, "Validator is not on the leader schedule") > 0) {
            not_on_schedule=1
            if (debug == "1") print "DEBUG: Found not on leader schedule at", ts > "/dev/stderr"
          }
        }
      }
      END {
        if (debug == "1") print "DEBUG: Cutoff was", c "Z", "| Result:", failed, lost, not_on_schedule > "/dev/stderr"
        print failed, lost, not_on_schedule
      }
    '
)

if [[ "${DEBUG:-0}" == "1" ]]; then
    echo "DEBUG: HAS_FAILED='$HAS_FAILED'"
    echo "DEBUG: HAS_LOST='$HAS_LOST'"
    echo "DEBUG: NOT_ON_SCHEDULE='$NOT_ON_SCHEDULE'"
fi

# Only alert if there are BAM issues AND the validator IS on the leader schedule
if [[ "$NOT_ON_SCHEDULE" == "1" ]]; then
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo "DEBUG: Suppressing alert - validator not on leader schedule"
    fi
    echo "$check_name - No BAM connection issues detected (not on leader schedule)"
elif [[ "$HAS_FAILED" == "1" ]]; then
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
