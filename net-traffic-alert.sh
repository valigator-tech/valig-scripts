#!/usr/bin/env bash
set -euo pipefail

# --- CONFIG (override via env if you like) -----------------------------
IFACE="${IFACE:-ens18}"          # main NIC
INTERVAL="${INTERVAL:-10}"       # seconds between samples
THRESHOLD_MIB="${THRESHOLD_MIB:-20}"  # alert threshold
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"  # Slack incoming webhook
#DD_API_KEY="${DD_API_KEY:-}"           # Datadog API key (for HTTP)
#DD_SITE="${DD_SITE:-datadoghq.com}"    # or datadoghq.eu etc.
# ----------------------------------------------------------------------

hostname=$(hostname -f 2>/dev/null || hostname)

# read rx/tx bytes from /proc/net/dev
read rx1 tx1 < <(awk -v ifc="$IFACE:" '$1==ifc {gsub(":", "", $1); print $2, $10}' /proc/net/dev)
sleep "$INTERVAL"
read rx2 tx2 < <(awk -v ifc="$IFACE:" '$1==ifc {gsub(":", "", $1); print $2, $10}' /proc/net/dev)

delta_bytes=$(( (rx2 + tx2) - (rx1 + tx1) ))
bps=$(( delta_bytes / INTERVAL ))          # bytes per second
rate_mib=$(( bps / 1024 / 1024 ))         # MiB per second

timestamp=$(date +%s)

# --- If above threshold, alert to Slack (and optionally Datadog event) --
if (( rate_mib >= THRESHOLD_MIB )); then
  msg="High network usage on ${hostname} (${IFACE}): ${rate_mib} MiB/s over last ${INTERVAL}s (threshold: ${THRESHOLD_MIB} MiB/s)"

  # Slack
  if [[ -n "$SLACK_WEBHOOK_URL" ]]; then
    payload=$(printf '{"text": "%s"}' "$(echo "$msg" | sed 's/"/\\"/g')")
    curl -sS -X POST -H 'Content-type: application/json' \
      --data "$payload" "$SLACK_WEBHOOK_URL" >/dev/null || true
  fi

 
fi
