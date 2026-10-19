#!/bin/bash
# <swiftbar.title>Memory Status</swiftbar.title>
# <swiftbar.version>v1.0</swiftbar.version>
# <swiftbar.author>mateuslimadematos</swiftbar.author>
# <swiftbar.desc>Memory and CPU monitor with cache management actions</swiftbar.desc>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>false</swiftbar.hideDisablePlugin>
# <swiftbar.hideSwiftBar>false</swiftbar.hideSwiftBar>

INSTALL_DIR="$HOME/Library/macos-memory-manager"
WATCHER="$INSTALL_DIR/scripts/memory_watcher.sh"
LOG_FILE="$INSTALL_DIR/logs/memory_watcher.log"

# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────

get_pressure() {
    local pct
    pct=$(memory_pressure 2>/dev/null | grep -i "System-wide memory free percentage" | grep -oE '[0-9]+' | head -1)
    echo "${pct:-0}"
}

pressure_label() {
    local pct="$1"
    if   [ "$pct" -ge 50 ]; then echo "Normal"
    elif [ "$pct" -ge 25 ]; then echo "Warning"
    else                          echo "Critical"
    fi
}

pressure_color() {
    local pct="$1"
    if   [ "$pct" -ge 50 ]; then echo "#34C759"   # Apple green
    elif [ "$pct" -ge 25 ]; then echo "#FF9F0A"   # Apple yellow/orange
    else                          echo "#FF3B30"   # Apple red
    fi
}

get_vm_stats() {
    vm_stat | awk '
        /page size of/               { match($0,/[0-9]+/); page=substr($0,RSTART,RLENGTH)+0 }
        /Pages free/                 { gsub(/\./,""); free=$NF }
        /Pages inactive/             { gsub(/\./,""); inactive=$NF }
        /Pages speculative/          { gsub(/\./,""); spec=$NF }
        /Pages wired down/           { gsub(/\./,""); wired=$NF }
        /Pages occupied by compressor/ { gsub(/\./,""); compressed=$NF }
        END {
            if (page==0) page=16384
            mb=1048576
            printf "%d %d %d %d\n",
                int((free+spec)*page/mb),
                int(inactive*page/mb),
                int(compressed*page/mb),
                int(wired*page/mb)
        }
    '
}

fmt_mb() {
    # Pure bash — no subprocess
    local mb="$1"
    if [ "$mb" -ge 1024 ]; then
        echo "$((mb / 1024)).$((mb % 1024 * 10 / 1024)) GB"
    else
        echo "${mb} MB"
    fi
}

get_swap() {
    sysctl -n vm.swapusage 2>/dev/null | awk '{
        gsub(/M/,"",$3); gsub(/M/,"",$6)
        printf "%.1f / %.1f GB", $6/1024, $3/1024
    }'
}

get_core_count() {
    sysctl -n hw.logicalcpu 2>/dev/null
}

# Single top call: -l 2 gives accurate CPU sample and top 5 processes.
# Avoids two separate top invocations (saves ~0.5s per refresh).
get_top_data() {
    top -l 2 -o mem -n 5 -stats pid,command,mem 2>/dev/null
}

# ─────────────────────────────────────────────
# Gather data
# ─────────────────────────────────────────────

FREE_PCT=$(get_pressure)
COLOR=$(pressure_color "$FREE_PCT")
LABEL=$(pressure_label "$FREE_PCT")

read -r FREE_MB INACTIVE_MB COMPRESSED_MB WIRED_MB <<< "$(get_vm_stats)"

FREE_FMT=$(fmt_mb "$FREE_MB")
INACTIVE_FMT=$(fmt_mb "$INACTIVE_MB")
COMPRESSED_FMT=$(fmt_mb "$COMPRESSED_MB")
WIRED_FMT=$(fmt_mb "$WIRED_MB")
SWAP=$(get_swap)
CORES=$(get_core_count)

TOP_DATA=$(get_top_data)
CPU=$(echo "$TOP_DATA" | grep "CPU usage" | tail -1 | awk '{printf "%d", $3+$5}')
TOP_PROCS=$(echo "$TOP_DATA" | awk '
    /^[0-9]/ {
        mem=$NF; cmd=""
        for(i=2;i<NF;i++) cmd=cmd (i>2?" ":"") $i
        printf "%-22s %s\n", substr(cmd,1,22), mem
    }
' | tail -5)

# ─────────────────────────────────────────────
# Menu bar title
# ─────────────────────────────────────────────

echo "${FREE_PCT}% | sfimage=memorychip color=${COLOR} font=SF Pro Text size=12"

# ─────────────────────────────────────────────
# Dropdown
# ─────────────────────────────────────────────

echo "---"

# ── Memory ──
echo "Memory | font=SF Pro Text size=11 color=#8E8E93"
echo "--Pressure    $LABEL | font=SF Mono size=12 color=${COLOR}"
echo "--Free        $FREE_FMT | font=SF Mono size=12"
echo "--Inactive    $INACTIVE_FMT | font=SF Mono size=12"
echo "--Compressed  $COMPRESSED_FMT | font=SF Mono size=12"
echo "--Wired       $WIRED_FMT | font=SF Mono size=12"
echo "--Swap        $SWAP | font=SF Mono size=12"

echo "---"

# ── CPU ──
echo "CPU | font=SF Pro Text size=11 color=#8E8E93"
echo "--Usage       ${CPU}% | font=SF Mono size=12"
echo "--Cores       $CORES | font=SF Mono size=12"

echo "---"

# ── Top processes ──
echo "Top Processes | font=SF Pro Text size=11 color=#8E8E93"
while IFS= read -r line; do
    echo "--${line} | font=SF Mono size=12"
done <<< "$TOP_PROCS"

echo "---"

# ── Actions ──
echo "Clear Cache | sfimage=trash font=SF Pro Text size=12 bash=$WATCHER param1=--force terminal=false refresh=true"
echo "Purge RAM | sfimage=memorychip font=SF Pro Text size=12 bash=/usr/sbin/purge terminal=false refresh=true"
echo "Refresh | sfimage=arrow.clockwise font=SF Pro Text size=12 refresh=true"
echo "View Logs | sfimage=doc.text font=SF Pro Text size=12 bash=/usr/bin/open param1=-a param2=Console param3=$LOG_FILE terminal=false"
