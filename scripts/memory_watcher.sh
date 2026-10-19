#!/bin/bash
# memory_watcher.sh — macOS RAM pressure monitor
# Scheduled via launchd to run every hour.
# Only acts when pressure is YELLOW or RED — does nothing in normal state.

INSTALL_DIR="$HOME/Library/macos-memory-manager"
LOG_FILE="$INSTALL_DIR/logs/memory_watcher.log"
SCRIPT_NAME="memory_watcher"

mkdir -p "$INSTALL_DIR/logs"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$SCRIPT_NAME] $1" | tee -a "$LOG_FILE"
}

notify() {
    local title="$1"
    local message="$2"
    osascript -e "display notification \"$message\" with title \"$title\" sound name \"Basso\"" 2>/dev/null
}

# ─────────────────────────────────────────────────────────────
# Diagnostics
# ─────────────────────────────────────────────────────────────

get_memory_stats() {
    vm_stat | awk '
        /page size of/        { match($0, /[0-9]+/); page=substr($0,RSTART,RLENGTH)+0 }
        /Pages free/          { gsub(/\./,""); free=$NF }
        /Pages inactive/      { gsub(/\./,""); inactive=$NF }
        /Pages speculative/   { gsub(/\./,""); spec=$NF }
        /Pages wired down/    { gsub(/\./,""); wired=$NF }
        /Pages occupied by compressor/ { gsub(/\./,""); compressed=$NF }
        END {
            if (page == 0) page=16384
            mb=1048576
            printf "free=%d inactive=%d compressed=%d wired=%d\n",
                int((free+spec+0)*page/mb),
                int((inactive+0)*page/mb),
                int((compressed+0)*page/mb),
                int((wired+0)*page/mb)
        }
    '
}

get_pressure_level() {
    local pct
    pct=$(memory_pressure 2>/dev/null | grep -i "System-wide memory free percentage" | grep -oE '[0-9]+' | head -1)

    if [ -z "$pct" ]; then
        echo "UNKNOWN"
        return
    fi

    if   [ "$pct" -ge 50 ]; then echo "GREEN:$pct"
    elif [ "$pct" -ge 25 ]; then echo "YELLOW:$pct"
    else                          echo "RED:$pct"
    fi
}

show_top_consumers() {
    log "--- Top 5 processes by memory ---"
    top -l 1 -o mem -n 5 -stats pid,command,mem 2>/dev/null | tail -6 | while read -r line; do
        log "  $line"
    done
}

# ─────────────────────────────────────────────────────────────
# Cleanup actions
# ─────────────────────────────────────────────────────────────

purge_ram() {
    log "Running RAM purge..."
    if sudo -n purge 2>/dev/null; then
        log "purge completed successfully"
    else
        log "WARNING: purge requires passwordless sudo — see README for sudoers setup"
    fi
}

clear_user_caches() {
    log "Clearing selected user caches..."
    local cleared=0

    local safe_caches=(
        "com.apple.Safari"
        "com.google.Chrome"
        "com.google.Chrome.helper"
        "Slack"
        "notion.id"
        "com.spotify.client"
        "com.microsoft.VSCode"
    )

    for cache in "${safe_caches[@]}"; do
        local target="$HOME/Library/Caches/$cache"
        if [ -d "$target" ]; then
            local size
            size=$(du -sh "$target" 2>/dev/null | awk '{print $1}')
            rm -rf "$target" 2>/dev/null
            log "  Removed: $cache ($size)"
            ((cleared++))
        fi
    done

    log "Caches cleared: $cleared dir(s)"
}

flush_dns() {
    log "Flushing DNS cache..."
    sudo -n dscacheutil -flushcache 2>/dev/null
    sudo -n killall -HUP mDNSResponder 2>/dev/null
    log "DNS cache flushed"
}

# ─────────────────────────────────────────────────────────────
# Main flows
# ─────────────────────────────────────────────────────────────

run_status() {
    echo ""
    echo "╔══════════════════════════════════════════╗"
    echo "║      macOS Memory Pressure Status        ║"
    echo "╚══════════════════════════════════════════╝"

    local pressure_info
    pressure_info=$(get_pressure_level)
    local level="${pressure_info%%:*}"
    local pct="${pressure_info##*:}"

    echo "Memory pressure: $level ($pct% free)"
    echo ""

    local stats
    stats=$(get_memory_stats)
    local free inactive compressed wired
    free=$(echo "$stats"       | awk -F'free='       '{print $2}' | awk '{print $1}')
    inactive=$(echo "$stats"   | awk -F'inactive='   '{print $2}' | awk '{print $1}')
    compressed=$(echo "$stats" | awk -F'compressed=' '{print $2}' | awk '{print $1}')
    wired=$(echo "$stats"      | awk -F'wired='      '{print $2}' | awk '{print $1}')

    echo "Free:           ${free} MB"
    echo "Inactive:       ${inactive} MB"
    echo "Compressed:     ${compressed} MB"
    echo "Wired (system): ${wired} MB"
    echo ""

    echo "Top 5 processes by memory:"
    top -l 1 -o mem -n 5 -stats pid,command,mem 2>/dev/null | tail -6
    echo ""

    local swap
    swap=$(sysctl -n vm.swapusage 2>/dev/null | awk '{print "used=" $6 " / total=" $3}')
    echo "Swap: $swap"
    echo ""
}

run_check() {
    local pressure_info
    pressure_info=$(get_pressure_level)
    local level="${pressure_info%%:*}"
    local pct="${pressure_info##*:}"

    local stats
    stats=$(get_memory_stats)

    log "====== MEMORY CHECK ======"
    log "Pressure: $level ($pct% free) | $stats"

    case "$level" in
        GREEN)
            log "STATUS: OK — no action needed"
            ;;
        YELLOW)
            log "STATUS: WARNING — running light cleanup"
            show_top_consumers
            purge_ram
            clear_user_caches
            log "STATUS: Light cleanup done"
            ;;
        RED)
            log "STATUS: CRITICAL — running aggressive cleanup"
            show_top_consumers
            purge_ram
            clear_user_caches
            flush_dns
            notify "Memory Critical" "RED pressure detected ($pct% free). Cleanup executed."
            log "STATUS: Aggressive cleanup done"
            ;;
        UNKNOWN)
            log "STATUS: Could not determine memory pressure"
            ;;
    esac

    log "====== END OF CHECK ======"
    log ""
}

run_force() {
    log "====== FORCED CLEANUP ======"
    local stats
    stats=$(get_memory_stats)
    log "State before: $stats"
    show_top_consumers
    purge_ram
    clear_user_caches
    flush_dns
    log "====== FORCED CLEANUP DONE ======"
    log ""
}

# ─────────────────────────────────────────────────────────────
# Entry point
# ─────────────────────────────────────────────────────────────

case "${1:-}" in
    --status|-s)
        run_status
        ;;
    --force|-f)
        run_force
        ;;
    --help|-h)
        echo "Usage: $0 [option]"
        echo ""
        echo "  (no argument)    Check pressure and act if needed"
        echo "  --status, -s     Show detailed memory status"
        echo "  --force,  -f     Force cleanup regardless of pressure"
        echo "  --help,   -h     Show this help"
        echo ""
        echo "Logs: $LOG_FILE"
        ;;
    *)
        run_check
        ;;
esac
