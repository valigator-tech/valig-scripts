#!/usr/bin/env bash
# nvme_link_report.sh — Show NVMe details + PCIe link width/gen in one shot.

set -euo pipefail

# Verify deps
for bin in nvme lspci awk sed grep; do
  command -v "$bin" >/dev/null 2>&1 || { echo "Missing $bin. Install nvme-cli/pciutils."; exit 1; }
done


printf "%-8s %-28s %-20s %-10s %-22s %-8s %-8s %-10s\n" \
  "NVMe" "Model" "Serial" "FW" "Namespace" "PCIeGen" "Width" "EstMaxGB/s"

# Per-lane rough maxima after overhead (rule of thumb)
# Gen3≈0.985 GB/s, Gen4≈1.969 GB/s, Gen5≈3.938 GB/s
gen_to_gbps_per_lane() {
  case "$1" in
    1) echo "0.25" ;;   # very rough, rarely relevant for NVMe
    2) echo "0.5"  ;;   # "
    3) echo "0.985" ;;
    4) echo "1.969" ;;
    5) echo "3.938" ;;
    6) echo "7.876" ;;  # Gen6 theoretical (future-proof)
    *) echo "0" ;;
  esac
}

# Map GT/s to Gen
gts_to_gen() {
  case "$1" in
    2.5*) echo 1 ;;
    5*)   echo 2 ;;
    8*)   echo 3 ;;
    16*)  echo 4 ;;
    32*)  echo 5 ;;
    64*)  echo 6 ;;
    *)    echo 0 ;;
  esac
}

# Iterate controllers (nvme0, nvme1, ...)
for ctrl in /sys/class/nvme/nvme*; do
  [ -e "$ctrl" ] || continue
  name=$(basename "$ctrl")               # e.g. nvme0
  model=$(<"$ctrl/model")
  serial=$(<"$ctrl/serial")
  fw=$(<"$ctrl/firmware_rev")

  # Pick the first namespace (if multiple exist, you can extend to loop them)
  ns_path=$(ls -1d "$ctrl/${name}n"* 2>/dev/null | head -n1 || true)
  ns_name=$(basename "$ns_path" 2>/dev/null || echo "-")
  # Human size from /sys (blocks * 512)
  if [[ -n "${ns_path:-}" && -e "$ns_path/size" ]]; then
    blocks=$(<"$ns_path/size")
    bytes=$(( blocks * 512 ))
    # Pretty size in GiB/TiB
    if (( bytes >= 1099511627776 )); then
      size=$(awk -v b="$bytes" 'BEGIN{printf "%.2fTiB", b/1099511627776}')
    else
      size=$(awk -v b="$bytes" 'BEGIN{printf "%.2fGiB", b/1073741824}')
    fi
    ns_disp="$ns_name($size)"
  else
    ns_disp="-"
  fi

  # Resolve PCI address
  devlink=$(readlink -f "$ctrl/device")                         # .../0000:5e:00.0
  pci_addr="${devlink##*/}"

  # Pull link caps/status
  linfo=$(lspci -s "$pci_addr" -vv 2>/dev/null | grep -E "LnkCap:|LnkSta:" | sed 's/^[[:space:]]*//')
  lnkcap_speed=$(echo "$linfo" | awk '/LnkCap:/{for(i=1;i<=NF;i++) if($i ~ /GT\/s/) {print $i; exit}}')
  lnkcap_width=$(echo "$linfo" | awk '/LnkCap:/{for(i=1;i<=NF;i++) if($i ~ /^x[0-9]+$/) {print $i; exit}}')
  lnksta_speed=$(echo "$linfo" | awk '/LnkSta:/{for(i=1;i<=NF;i++) if($i ~ /GT\/s/) {print $i; exit}}')
  lnksta_width=$(echo "$linfo" | awk '/LnkSta:/{for(i=1;i<=NF;i++) if($i ~ /^x[0-9]+$/) {print $i; exit}}')

  # Prefer actual status (what it's running at now)
  speed_val="${lnksta_speed:-$lnkcap_speed}"       # e.g. 16GT/s
  width_val="${lnksta_width:-$lnkcap_width}"       # e.g. x4

  # Parse gen from GT/s
  speed_num=$(echo "$speed_val" | sed 's/GT\/s//')
  gen=$(gts_to_gen "$speed_num")
  lanes=$(echo "$width_val" | sed 's/x//')

  # Compute estimated max GB/s
  per_lane=$(gen_to_gbps_per_lane "$gen")
  if [[ -n "$per_lane" && -n "$lanes" && "$lanes" =~ ^[0-9]+$ ]]; then
    est=$(awk -v p="$per_lane" -v n="$lanes" 'BEGIN{printf "%.2f", p*n}')
  else
    est="0.00"
  fi

  # Display
  printf "%-8s %-28s %-20s %-10s %-22s %-8s %-8s %-10s\n" \
  "$name" "${model:0:28}" "$serial" "$fw" "$ns_disp" "Gen$gen" "$width_val" "$est"
done

