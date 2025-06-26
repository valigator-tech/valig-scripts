# Valig Scripts

A collection of health monitoring scripts for various blockchain services with Slack alerting capabilities.

## Overview

This repository contains monitoring scripts that check the health status of different blockchain services and send alerts to Slack when issues are detected. Each script automatically includes the server's hostname in alerts for easy identification.

## Scripts

### 1. check_dz.sh
Monitors the DoubleZero service for BGP peer connectivity issues.

- **Service**: `doublezerod`
- **Alert Conditions**:
  - Service is not running
  - BGP peer closed events detected in logs (within last 6 minutes)

### 2. check_yellowstone.sh
Monitors the Yellowstone Jet service availability.

- **Service**: `yellowstone-jet`
- **Alert Conditions**:
  - Service is not running

### 3. check_sol.sh
Monitors the Solana validator for panics and restarts.

- **Service**: `sol`
- **Log File**: `/var/log/solana/solana-validator.log`
- **Alert Conditions**:
  - Service is not running
  - Panic detected in validator logs (within last 5 minutes)
  - Validator restart detected without panic (within last 5 minutes)

## Configuration

All scripts require a `.env` file in the same directory with the following variable:

```bash
SLACK_WEBHOOK_URL="your-slack-webhook-url-here"
```

## Usage

Make the scripts executable:
```bash
chmod +x check_*.sh
```

Run individually:
```bash
./check_dz.sh
./check_yellowstone.sh
./check_sol.sh
```

### Cron Setup

To run checks periodically, add to crontab:
```bash
# Run every 5 minutes
*/5 * * * * /path/to/valig-scripts/check_dz.sh
*/5 * * * * /path/to/valig-scripts/check_yellowstone.sh
*/5 * * * * /path/to/valig-scripts/check_sol.sh
```

## Alert Format

All alerts include:
- Check name
- Issue description
- Server hostname (automatically detected)

Example: `Check-Solana-Health - PANIC detected in Agave validator logs! @ server-name`

## Requirements

- Bash
- systemctl (for service status checks)
- journalctl (for DoubleZero log access)
- curl (for Slack notifications)
- Access to service logs

# valig-scripts
# valig-scripts
