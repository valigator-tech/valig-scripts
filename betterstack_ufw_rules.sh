#!/bin/bash

# Script to dynamically add firewall rules for IPs from Validator API


# Load environment variables from .env file
if [ -f "$(dirname "$0")/.env" ]; then
    source "$(dirname "$0")/.env"
else
    echo "ERROR: Missing .env file"
fi

# Fetch and parse IP addresses from the URL
echo "Fetching IP addresses from $BETTERSTACK_WHITELIST..."
IP_LIST=($(curl -s "$BETTERSTACK_WHITELIST" | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}'))

# Make sure UFW is enabled
echo "Checking UFW status..."
if ! sudo ufw status | grep -q "Status: active"; then
  echo "UFW is not active. Enabling UFW..."
  sudo ufw enable
fi

# Add rules for each IP
echo "Adding firewall rules for each IP address..."

if [ ${#IP_LIST[@]} -eq 0 ]; then
  echo "Error: No IP addresses found. Please check the URL and try again."
  exit 1
fi

echo "Found ${#IP_LIST[@]} IP addresses to add to firewall rules."

for ip in "${IP_LIST[@]}"; do
  echo "Adding rules for IP: $ip"

  # TCP rule
  sudo ufw insert 1 allow from $ip to any port 8899 proto tcp

  # UDP rule
  sudo ufw insert 1 allow from $ip to any port 8899 proto udp
done

echo "All UFW rules have been added!"
echo "Current UFW status:"
sudo ufw status