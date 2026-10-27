#!/bin/bash

# Colors only when attached to a terminal, so journald logs stay clean
if [[ -t 1 ]]; then
    RED='\033[0;31m'      # For errors or important actions
    GREEN='\033[0;32m'    # For successful actions
    YELLOW='\033[0;33m'   # For information
    NC='\033[0m'          # No Color
else
    RED='' GREEN='' YELLOW='' NC=''
fi

# mpstat prints localized labels and decimal commas otherwise
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GENERATOR="$SCRIPT_DIR/load_generator.py"
MEM_HOLDER="$SCRIPT_DIR/mem_holder.py"

# OCI treats an Always Free VM as idle when, over 7 days, its 95th percentile
# CPU, its network and (on A1 shapes) its memory are all below 20%, so keep
# CPU and memory a little above that. Both use the same thresholds.
TARGET=25         # % of total CPU / memory to aim for
LOW=22            # start processes below this
HIGH=30           # stop processes above this
KILL_ALL=80       # real workload is busy, stop every process
CPU_STEP=0.1      # fraction of one core each load generator uses
MEM_STEP=5        # % of total memory each memory holder keeps
INTERVAL=10       # seconds per CPU measurement

# Check if sysstat package is installed
if ! command -v mpstat &> /dev/null
then
    echo -e "${RED}sysstat could not be found. Install it with 'sudo apt-get install sysstat'${NC}"
    exit 1
fi

# Round $1 up to a whole number
function ceil {
    awk -v n="$1" 'BEGIN {c = int(n); if (c < n) c++; print c}'
}

NCPU=$(nproc)
# % of total CPU that one load generator adds
CPU_PER_PROC=$(awk -v s="$CPU_STEP" -v n="$NCPU" 'BEGIN {print s * 100 / n}')
CPU_MAX=$(ceil "$(awk -v h="$HIGH" -v p="$CPU_PER_PROC" 'BEGIN {print h / p}')")

MEM_TOTAL_KB=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
MEM_CHUNK_MB=$(( MEM_TOTAL_KB * MEM_STEP / 100 / 1024 ))
MEM_MAX=$(ceil "$(awk -v h="$HIGH" -v p="$MEM_STEP" 'BEGIN {print h / p}')")

cpu_pids=()
mem_pids=()

# a > b, with floats
function gt {
    awk -v a="$1" -v b="$2" 'BEGIN {exit !(a > b)}'
}

# Used memory in %, counting only what the kernel cannot reclaim (not cache)
function mem_usage {
    awk '/^MemTotal:/ {t = $2} /^MemAvailable:/ {a = $2} END {printf "%.1f", (t - a) * 100 / t}' /proc/meminfo
}

# Drop processes that have exited on their own, e.g. a memory holder
# picked by the OOM killer. $1 = name of the pid array
function prune_dead {
    local -n pids=$1
    local alive=()
    for pid in "${pids[@]}"; do
        kill -0 "$pid" 2> /dev/null && alive+=("$pid")
    done
    pids=("${alive[@]}")
}

# $1 = name of the pid array, $2 = how many, rest = command to run
function start_procs {
    local -n pids=$1
    local count=$2
    shift 2
    for ((i = 0; i < count; i++)); do
        "$@" & pids+=($!)
    done
}

# $1 = name of the pid array, $2 = how many
function stop_procs {
    local -n pids=$1
    for ((i = 0; i < $2 && ${#pids[@]} > 0; i++)); do
        kill "${pids[-1]}" 2> /dev/null # kill the last process
        unset 'pids[-1]' # remove it from the array
    done
}

# Keep one resource near TARGET by starting or stopping processes.
# $1 = name of the pid array, $2 = label for logs, $3 = usage in %,
# $4 = % one process adds, $5 = max processes, rest = command to run
function regulate {
    local -n procs=$1
    local label=$2 usage=$3 per_proc=$4 max=$5
    shift 5
    local count room

    prune_dead "${!procs}"
    echo -e "${YELLOW}Average $label Usage: $usage%. Current number of $label processes: ${#procs[@]}${NC}"

    if gt "$usage" "$KILL_ALL"; then
        if (( ${#procs[@]} > 0 )); then
            echo -e "${RED}$label usage is above ${KILL_ALL}%, stopping all $label processes...${NC}"
            stop_procs "${!procs}" ${#procs[@]}
        fi
    elif gt "$usage" "$HIGH"; then
        if (( ${#procs[@]} > 0 )); then
            count=$(ceil "$(awk -v u="$usage" -v t="$TARGET" -v p="$per_proc" 'BEGIN {print (u - t) / p}')")
            echo -e "${RED}$label usage is above ${HIGH}%, stopping up to $count $label processes...${NC}"
            stop_procs "${!procs}" "$count"
        fi
    elif gt "$LOW" "$usage"; then
        count=$(ceil "$(awk -v u="$usage" -v t="$TARGET" -v p="$per_proc" 'BEGIN {print (t - u) / p}')")
        room=$(( max - ${#procs[@]} ))
        (( count > room )) && count=$room
        if (( count > 0 )); then
            echo -e "${GREEN}$label usage is below ${LOW}%, starting $count $label processes...${NC}"
            start_procs "${!procs}" "$count" "$@"
        fi
    fi
}

# Function to stop child processes and exit
function cleanup {
    echo -e "${RED}Stopping load generators and memory holders and exiting...${NC}"
    stop_procs cpu_pids ${#cpu_pids[@]}
    stop_procs mem_pids ${#mem_pids[@]}
    wait
    exit
}

# Catch interrupt signal (Ctrl+C) and terminate signal
trap cleanup SIGINT SIGTERM

echo -e "${YELLOW}Target ${TARGET}% CPU on ${NCPU} cores: ${CPU_PER_PROC}% per load generator, max ${CPU_MAX}${NC}"
echo -e "${YELLOW}Target ${TARGET}% memory of $(( MEM_TOTAL_KB / 1024 )) MB: ${MEM_CHUNK_MB} MB per memory holder, max ${MEM_MAX}${NC}"

while true; do
    cpu_usage=$(mpstat "$INTERVAL" 1 | awk '/^Average:/ && $2 == "all" {printf "%.1f", 100 - $NF}')

    if [[ -z $cpu_usage ]]; then
        echo -e "${RED}Could not read CPU usage from mpstat, retrying...${NC}"
        sleep "$INTERVAL"
    else
        regulate cpu_pids CPU "$cpu_usage" "$CPU_PER_PROC" "$CPU_MAX" \
            python3 "$GENERATOR" "$CPU_STEP"
    fi

    regulate mem_pids Memory "$(mem_usage)" "$MEM_STEP" "$MEM_MAX" \
        python3 "$MEM_HOLDER" "$MEM_CHUNK_MB"
done
