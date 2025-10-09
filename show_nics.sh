#!/usr/bin/env bash
printf "%-16s %-18s %-22s %-38s %-10s %-12s %-8s\n" "IFACE" "MAC" "IPv4" "IPv6" "PCI" "VENDOR" "STATE"

for i in /sys/class/net/*; do
  IF=${i##*/}
  [[ "$IF" == "lo" ]] && continue

  PCI=$(basename "$(readlink -f "$i/device" 2>/dev/null)" 2>/dev/null)
  MAC=$(cat "$i/address" 2>/dev/null)

  # Vendor name from PCI vendor ID (common NICs)
  VID=$(cat "/sys/bus/pci/devices/$PCI/vendor" 2>/dev/null)
  case "$VID" in
    0x14e4) VENDOR="Broadcom" ;;  # Broadcom Inc.
    0x15b3) VENDOR="Mellanox" ;;  # NVIDIA/Mellanox
    0x8086) VENDOR="Intel"    ;;  # Intel (e.g., X710)
    *)      VENDOR=${VID:-"-"} ;;
  esac

  # Collect IPs (comma-separated if multiple)
  IPV4=$(ip -o -4 addr show dev "$IF" 2>/dev/null | awk '{print $4}' | paste -sd "," -)
  IPV6=$(ip -o -6 addr show dev "$IF" 2>/dev/null | awk '{print $4}' | paste -sd "," -)

  STATE=$(cat "$i/operstate" 2>/dev/null)

  printf "%-16s %-18s %-22s %-38s %-10s %-12s %-8s\n" \
    "$IF" "${MAC:--}" "${IPV4:--}" "${IPV6:--}" "${PCI#0000:}" "${VENDOR:--}" "${STATE:--}"
done
