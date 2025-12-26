#!/bin/bash

# wait to load the binary
# sleep 120

# timeout after 1 hour (3600 seconds)
MAX_WAIT=3600
elapsed=0

# main pid of solana-validator
while [ -z "$solana_pid" ]; do
    solana_pid=$(pgrep -f "agave-validator --tip")
    if [ -z "$solana_pid" ]; then
        echo "set_affinity: solana_validator_404"
        sleep 20
        elapsed=$((elapsed + 20))
        if [ $elapsed -ge $MAX_WAIT ]; then
            echo "set_affinity: timeout_after_${elapsed}s_waiting_for_validator"
            exit 2
        fi
    fi
done

# find thread id
while [ -z "$thread_pid" ]; do
    thread_pid=$(ps -T -p $solana_pid -o spid,comm | grep 'solPohTickProd' | awk '{print $1}')
    if [ -z "$thread_pid" ]; then
        echo "set_affinity: solPohTickProd_404"
        sleep 120
        elapsed=$((elapsed + 120))
        if [ $elapsed -ge $MAX_WAIT ]; then
            echo "set_affinity: timeout_after_${elapsed}s_waiting_for_thread"
            exit 2
        fi
    fi
done

current_affinity=$(taskset -cp $thread_pid 2>&1 | awk '{print $NF}')
if [ "$current_affinity" == "2" ]; then
    echo "set_affinity: solPohTickProd_already_set"
    exit 1
else
    # set poh to cpu2
    taskset -cp 2 $thread_pid
    echo "set_affinity: set_done"
     # $thread_pid
fi