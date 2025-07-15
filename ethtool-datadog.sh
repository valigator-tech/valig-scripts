#!/bin/bash
#INTERFACES="eno1np0 eno1np1"
INTERFACES="enp5s0f1 enp5s0f0"

for iface in $INTERFACES; do
    # Initialize counters
    declare -A metrics_sum
    
    # Get statistics and sum across queues
    while IFS= read -r line; do
        # Skip empty lines and headers
        [[ -z "$line" || "$line" =~ ^NIC[[:space:]]statistics ]] && continue
        
        # Parse the line - handle both formats
        if [[ "$line" =~ ^[[:space:]]*\[([0-9]+)\]:[[:space:]]*([^:]+):[[:space:]]*([0-9]+)[[:space:]]*$ ]]; then
            # Queue format: [0]: metric_name: value
            clean_metric="${BASH_REMATCH[2]}"
            value="${BASH_REMATCH[3]}"
        elif [[ "$line" =~ ^[[:space:]]*([^:]+):[[:space:]]*([0-9]+)[[:space:]]*$ ]]; then
            # Simple format: metric_name: value
            clean_metric="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
        else
            continue
        fi
        
        # Trim whitespace from metric name
        clean_metric=$(echo "$clean_metric" | xargs)
        
        # Only process specific metrics
        case "$clean_metric" in
            "rx_errors"|"rx_discards"|"rx_dropped"|"rx_missed_errors"|"tx_errors"|"tx_discards"|"tx_dropped")
                # Sum up the values across queues
                metrics_sum["$clean_metric"]=$((${metrics_sum["$clean_metric"]:-0} + value))
                ;;
        esac
    done < <(ethtool -S $iface 2>/dev/null)
    
    # Debug: show what we collected
    echo "Debug: Found ${#metrics_sum[@]} metrics for $iface" >&2
    
    # Send the aggregated metrics
    for metric in "${!metrics_sum[@]}"; do
        echo "ethtool.${metric}:${metrics_sum[$metric]}|g|#interface:${iface}"
        # echo "ethtool.${metric}:${metrics_sum[$metric]}|g|#interface:${iface}" | nc -w 1 -u 127.0.0.1 8125
    done
    
    # Get ring buffer sizes (these are typically not per-queue)
    ring_output=$(ethtool -g $iface 2>/dev/null)
    if [[ $? -eq 0 ]]; then
        rx_ring=$(echo "$ring_output" | sed -n '/Current hardware settings:/,/^$/p' | grep "^RX:" | awk '{print $2}')
        if [[ -n "$rx_ring" && "$rx_ring" =~ ^[0-9]+$ ]]; then
            echo "ethtool.rx_ring_size:${rx_ring}|g|#interface:${iface}"
            # echo "ethtool.rx_ring_size:${rx_ring}|g|#interface:${iface}" | nc -w 1 -u 127.0.0.1 8125
        fi
        
        tx_ring=$(echo "$ring_output" | sed -n '/Current hardware settings:/,/^$/p' | grep "^TX:" | awk '{print $2}')
        if [[ -n "$tx_ring" && "$tx_ring" =~ ^[0-9]+$ ]]; then
            echo "ethtool.tx_ring_size:${tx_ring}|g|#interface:${iface}"
            # echo "ethtool.tx_ring_size:${tx_ring}|g|#interface:${iface}" | nc -w 1 -u 127.0.0.1 8125
        fi
    fi
    
    unset metrics_sum
done
