#!/bin/bash
# benchmark.sh — Fair performance and correctness benchmark
# Tests every component of macos-memory-manager and produces a scored report.
#
# Usage:
#   ./benchmark.sh            Run all benchmarks
#   ./benchmark.sh --quick    Skip slow tests (fewer top -l 2 repeat runs)
#   ./benchmark.sh --json     Also write results to benchmark_results.json

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN="$REPO_DIR/swiftbar/memory_status.60s.sh"
WATCHER="$REPO_DIR/scripts/memory_watcher.sh"

QUICK_MODE=false
JSON_MODE=false
for arg in "$@"; do
    case "$arg" in
        --quick) QUICK_MODE=true ;;
        --json)  JSON_MODE=true ;;
    esac
done

# ─── colours ───────────────────────────────────────────────────────────────
BOLD=$'\033[1m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
RED=$'\033[0;31m'
CYAN=$'\033[0;36m'
GRAY=$'\033[0;37m'
NC=$'\033[0m'

pass()   { echo -e "  ${GREEN}PASS${NC}  $1"; }
warn()   { echo -e "  ${YELLOW}WARN${NC}  $1"; }
fail_()  { echo -e "  ${RED}FAIL${NC}  $1"; }    # named fail_ to avoid collision
info()   { echo -e "  ${GRAY}    ${NC}  $1"; }
header() { echo -e "\n${BOLD}${CYAN}$1${NC}"; echo -e "${CYAN}$(printf '─%.0s' {1..60})${NC}"; }

# ─── timing helper ─────────────────────────────────────────────────────────

# wall_time CMD — returns elapsed seconds
wall_time() {
    { TIMEFORMAT='%R'; time eval "$1" > /dev/null 2>&1; } 2>&1
}

# rss_bytes CMD — returns peak RSS in bytes
rss_bytes() {
    /usr/bin/time -l bash -c "$1" 2>&1 | awk '/maximum resident/{print $1; exit}'
}

# bench LABEL RUNS CMD [THRESH_PASS] [THRESH_WARN]
# Runs CMD RUNS times, prints avg/min/max/stddev table row, echoes avg
bench() {
    local label="$1" runs="$2" cmd="$3"
    local thresh_pass="${4:-}" thresh_warn="${5:-}"
    local -a times=()
    local i

    for ((i=0; i<runs; i++)); do
        times+=( "$(wall_time "$cmd")" )
    done

    local stats
    stats=$(printf '%s\n' "${times[@]}" | awk '
        BEGIN { min=9999; max=0; sum=0; n=0 }
        {
            v = $1+0; sum+=v; n++
            if(v<min) min=v; if(v>max) max=v
            a[n]=v
        }
        END {
            avg=sum/n; var=0
            for(i=1;i<=n;i++) var+=(a[i]-avg)^2
            printf "%.3f %.3f %.3f %.3f %d", avg, min, max, sqrt(var/n), n
        }
    ')

    local avg min_t max_t stddev n_t
    read -r avg min_t max_t stddev n_t <<< "$stats"

    # colour verdict
    local color="$NC" verdict_sym=""
    if [ -n "$thresh_pass" ]; then
        if awk "BEGIN{exit !($avg <= $thresh_pass)}"; then
            color="$GREEN"; verdict_sym="${GREEN}✓${NC}"
        elif [ -n "$thresh_warn" ] && awk "BEGIN{exit !($avg <= $thresh_warn)}"; then
            color="$YELLOW"; verdict_sym="${YELLOW}~${NC}"
        else
            color="$RED"; verdict_sym="${RED}✗${NC}"
        fi
    fi

    # Print display row to /dev/tty so it isn't captured by $() callers
    {
        printf "  %-36s %s%6.3fs%s  (min %.3f  max %.3f  σ %.3f  n=%s)" \
            "$label" "$color" "$avg" "$NC" "$min_t" "$max_t" "$stddev" "$n_t"
        if [ -n "$verdict_sym" ]; then
            echo -e "  $verdict_sym"
        else
            echo ""
        fi
    } >&2

    BENCH_RESULTS+=("{\"test\":\"$label\",\"avg\":$avg,\"min\":$min_t,\"max\":$max_t,\"stddev\":$stddev,\"runs\":$n_t}")
    echo "$avg"   # only the number goes to stdout → captured by T_xxx=$( bench ... )
}

# ─── correctness helpers ────────────────────────────────────────────────────

CHECKS_PASSED=0
CHECKS_FAILED=0

check() {
    local desc="$1" result="$2" detail="${3:-}"
    if [ "$result" = "pass" ]; then
        pass "$desc${detail:+  ($detail)}"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
        fail_ "$desc${detail:+  ($detail)}"
        CHECKS_FAILED=$((CHECKS_FAILED + 1))
    fi
}

# ─── score helpers ──────────────────────────────────────────────────────────

TOTAL_SCORE=0
MAX_SCORE=0

add_score() {
    local max="$1" earned="$2"
    TOTAL_SCORE=$((TOTAL_SCORE + earned))
    MAX_SCORE=$((MAX_SCORE + max))
}

gte() { awk "BEGIN{exit !($1 >= $2)}"; }   # returns 0 (true) if $1 >= $2
lte() { awk "BEGIN{exit !($1 <= $2)}"; }

BENCH_RESULTS=()

# ═══════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}  macOS Memory Manager — Benchmark${NC}"
echo -e "  $(date '+%Y-%m-%d %H:%M:%S')  |  $(sw_vers -productName) $(sw_vers -productVersion)  |  $(sysctl -n hw.logicalcpu) cores"
echo -e "  Plugin:  $PLUGIN"
echo -e "  Watcher: $WATCHER"
$QUICK_MODE && echo -e "  ${YELLOW}Quick mode: fewer repeat runs for slow tests${NC}"
# ═══════════════════════════════════════════════════════════════════════════

# ───────────────────────────────────────────────────────────────────────────
header "1  CORRECTNESS — Output validation"
# ───────────────────────────────────────────────────────────────────────────

PLUGIN_OUT=$("$PLUGIN" 2>/dev/null)
FIRST_LINE=$(echo "$PLUGIN_OUT" | head -1)

# 1.1 SwiftBar pipe separator on first line
[[ "$FIRST_LINE" == *"|"* ]] && R="pass" || R="fail"
check "First line has SwiftBar pipe separator" "$R" "$FIRST_LINE"
add_score 5 $([ "$R" = "pass" ] && echo 5 || echo 0)

# 1.2 Pressure % is 0–100
PCT=$(echo "$FIRST_LINE" | grep -oE '^[0-9]+' || echo "")
if [[ "$PCT" =~ ^[0-9]+$ ]] && [ "$PCT" -ge 0 ] && [ "$PCT" -le 100 ]; then R="pass"; else R="fail"; fi
check "Pressure % is numeric (0–100)" "$R" "${PCT:-none}%"
add_score 5 $([ "$R" = "pass" ] && echo 5 || echo 0)

# 1.3 Color is a valid hex
COLOR_VAL=$(echo "$PLUGIN_OUT" | grep -oE 'color=#[0-9A-Fa-f]{6}' | head -1 | cut -d= -f2 || echo "")
[[ "$COLOR_VAL" =~ ^#[0-9A-Fa-f]{6}$ ]] && R="pass" || R="fail"
check "Pressure color is a valid hex code" "$R" "$COLOR_VAL"
add_score 5 $([ "$R" = "pass" ] && echo 5 || echo 0)

# 1.4 Memory section present
echo "$PLUGIN_OUT" | grep -q "^Memory" && R="pass" || R="fail"
check "Memory section present in dropdown" "$R"
add_score 5 $([ "$R" = "pass" ] && echo 5 || echo 0)

# 1.5 CPU usage 0–100
CPU_VAL=$(echo "$PLUGIN_OUT" | grep "^--Usage" | grep -oE '[0-9]+' | head -1 || echo "")
if [[ "$CPU_VAL" =~ ^[0-9]+$ ]] && [ "$CPU_VAL" -ge 0 ] && [ "$CPU_VAL" -le 100 ]; then R="pass"; else R="fail"; fi
check "CPU % is numeric (0–100)" "$R" "${CPU_VAL:-none}%"
add_score 5 $([ "$R" = "pass" ] && echo 5 || echo 0)

# 1.6 At least 3 processes listed
PROC_COUNT=$(echo "$PLUGIN_OUT" | grep -cE '^--[A-Za-z].*[0-9]+[MG]' || true)
[ "$PROC_COUNT" -ge 3 ] && R="pass" || R="fail"
check "At least 3 top processes listed" "$R" "${PROC_COUNT} found"
add_score 5 $([ "$R" = "pass" ] && echo 5 || echo 0)

# 1.7 All 4 action buttons
for btn in "Clear Cache" "Purge RAM" "Refresh" "View Logs"; do
    echo "$PLUGIN_OUT" | grep -q "^${btn}" && R="pass" || R="fail"
    check "Action button present: $btn" "$R"
    add_score 5 $([ "$R" = "pass" ] && echo 5 || echo 0)
done

# 1.8 Free memory is sane
TOTAL_RAM_MB=$(( $(sysctl -n hw.memsize) / 1048576 ))
FREE_VAL=$(echo "$PLUGIN_OUT" | grep "^--Free" | grep -oE '[0-9]+' | head -1 || echo "")
if [[ "$FREE_VAL" =~ ^[0-9]+$ ]] && [ "$FREE_VAL" -gt 0 ] && [ "$FREE_VAL" -lt "$TOTAL_RAM_MB" ]; then R="pass"; else R="fail"; fi
check "Free memory is sane (0 < free < ${TOTAL_RAM_MB} MB total)" "$R" "${FREE_VAL:-none} MB"
add_score 10 $([ "$R" = "pass" ] && echo 10 || echo 0)

# 1.9 Watcher --status produces output
WATCHER_OUT=$("$WATCHER" --status 2>/dev/null | head -5)
[ -n "$WATCHER_OUT" ] && R="pass" || R="fail"
check "memory_watcher.sh --status produces output" "$R"
add_score 5 $([ "$R" = "pass" ] && echo 5 || echo 0)

# 1.10 Watcher --help exits 0
"$WATCHER" --help > /dev/null 2>&1 && R="pass" || R="fail"
check "memory_watcher.sh --help exits cleanly" "$R"
add_score 5 $([ "$R" = "pass" ] && echo 5 || echo 0)

# ───────────────────────────────────────────────────────────────────────────
header "2  PERFORMANCE — Function-level timings"
# ───────────────────────────────────────────────────────────────────────────
echo ""
echo -e "  ${GRAY}Thresholds: ✓ good (green)   ~ acceptable (yellow)   ✗ slow (red)${NC}"
echo ""

RUNS=5
TOP_RUNS=$(if $QUICK_MODE; then echo 2; else echo 3; fi)

T_PRESSURE=$(bench "get_pressure  (memory_pressure)" $RUNS \
    "memory_pressure 2>/dev/null | grep -i 'System-wide' | grep -oE '[0-9]+' | head -1" \
    0.050 0.150)

T_VM_STAT=$(bench "get_vm_stats  (vm_stat + awk)" $RUNS \
    "vm_stat | awk 'END{print NR}'" \
    0.020 0.100)

T_SWAP=$(bench "get_swap      (sysctl vm.swapusage)" $RUNS \
    "sysctl -n vm.swapusage" \
    0.010 0.050)

T_CORES=$(bench "get_core_count (sysctl hw.logicalcpu)" $RUNS \
    "sysctl -n hw.logicalcpu" \
    0.010 0.050)

T_FMT=$(bench "fmt_mb ×8     (pure bash arithmetic)" $RUNS \
    'for v in 100 512 768 1024 1500 2048 3300 500; do [ $v -ge 1024 ] && echo "$((v/1024)).$((v%1024*10/1024)) GB" || echo "${v} MB"; done' \
    0.005 0.020)

echo ""
echo -e "  ${GRAY}get_top_data uses top -l 2 which must wait for two samples (~1.6s).${NC}"
echo -e "  ${GRAY}This is an unavoidable macOS API constraint — no faster bash alternative${NC}"
echo -e "  ${GRAY}gives accurate system-wide CPU%. Reported as-is, not penalised in score.${NC}"
echo ""

T_TOP=$(bench "get_top_data  (top -l 2) ← API constraint" $TOP_RUNS \
    "top -l 2 -o mem -n 5 -stats pid,command,mem")

# ───────────────────────────────────────────────────────────────────────────
header "3  PERFORMANCE — Full plugin (end-to-end)"
# ───────────────────────────────────────────────────────────────────────────
echo ""
echo -e "  ${GRAY}Threshold: ✓ ≤ 2.0s   ~ ≤ 3.0s   ✗ > 3.0s${NC}"
echo ""

FULL_RUNS=$(if $QUICK_MODE; then echo 2; else echo 5; fi)
T_FULL=$(bench "Full plugin (memory_status.60s.sh)" $FULL_RUNS \
    "\"$PLUGIN\"" \
    2.000 3.000)

if lte "$T_FULL" 2.0; then
    add_score 20 20
elif lte "$T_FULL" 3.0; then
    add_score 20 10
else
    add_score 20 0
fi

echo ""
DUTY_PCT=$(awk "BEGIN{printf \"%.2f\", $T_FULL/60*100}")
info "Refresh interval:  60 seconds"
info "CPU duty cycle:    ~${DUTY_PCT}% of one core per minute  (${T_FULL}s / 60s)"

if lte "$T_FULL" 3.0; then
    info "Impact:            negligible — well within acceptable range"
else
    info "Impact:            noticeable — consider reducing refresh to 120s"
fi

# ───────────────────────────────────────────────────────────────────────────
header "4  RESOURCE USAGE — Memory footprint"
# ───────────────────────────────────────────────────────────────────────────
echo ""

RSS_PLUGIN=$(rss_bytes "\"$PLUGIN\" > /dev/null 2>&1")
RSS_PLUGIN_MB=$(awk "BEGIN{printf \"%.1f\", $RSS_PLUGIN/1048576}")

RSS_WATCHER=$(rss_bytes "\"$WATCHER\" --status > /dev/null 2>&1")
RSS_WATCHER_MB=$(awk "BEGIN{printf \"%.1f\", $RSS_WATCHER/1048576}")

printf "  %-38s %6s MB\n" "Plugin peak RSS" "$RSS_PLUGIN_MB"
if lte "$RSS_PLUGIN" 20971520; then
    pass "Plugin RSS ≤ 20 MB"
    add_score 10 10
else
    warn "Plugin RSS > 20 MB (${RSS_PLUGIN_MB} MB)"
    add_score 10 5
fi

printf "  %-38s %6s MB\n" "Watcher --status peak RSS" "$RSS_WATCHER_MB"
if lte "$RSS_WATCHER" 20971520; then
    pass "Watcher RSS ≤ 20 MB"
    add_score 10 10
else
    warn "Watcher RSS > 20 MB (${RSS_WATCHER_MB} MB)"
    add_score 10 5
fi

# ───────────────────────────────────────────────────────────────────────────
header "5  LEAK CHECK — Process cleanup"
# ───────────────────────────────────────────────────────────────────────────
echo ""

"$PLUGIN" > /dev/null 2>&1 &
BG_PID=$!
sleep 2.5
STILL_ALIVE=$(ps -p "$BG_PID" > /dev/null 2>&1 && echo 1 || echo 0)
wait "$BG_PID" 2>/dev/null || true

[ "$STILL_ALIVE" = "0" ] && R="pass" || R="fail"
check "Plugin process exits cleanly (no hang)" "$R"
add_score 10 $([ "$R" = "pass" ] && echo 10 || echo 0)

ORPHAN_TOP=$(pgrep -x top 2>/dev/null | wc -l | tr -d ' ')
[ "$ORPHAN_TOP" -eq 0 ] && R="pass" || R="fail"
check "No orphan 'top' processes after plugin exits" "$R" "${ORPHAN_TOP} found"
add_score 10 $([ "$R" = "pass" ] && echo 10 || echo 0)

# ───────────────────────────────────────────────────────────────────────────
header "6  DATA ACCURACY — Values vs system ground truth"
# ───────────────────────────────────────────────────────────────────────────
echo ""

SYS_PCT=$(memory_pressure 2>/dev/null | grep -i "System-wide memory free percentage" | grep -oE '[0-9]+' | head -1 || echo "0")
PLUGIN_PCT=$(echo "$PLUGIN_OUT" | head -1 | grep -oE '^[0-9]+' || echo "0")
DIFF=$(awk "BEGIN{d=$PLUGIN_PCT-$SYS_PCT; print (d<0?-d:d)}")

info "Plugin:  ${PLUGIN_PCT}%   System (re-read): ${SYS_PCT}%   Δ ${DIFF}%"
# Allow ≤5% drift — these are two separate reads at different points in time
if lte "$DIFF" 5; then R="pass"; else R="fail"; fi
check "Pressure % within ±5% of system (time-of-read drift allowed)" "$R" "Δ=${DIFF}%"
add_score 10 $([ "$R" = "pass" ] && echo 10 || echo 0)

SYS_CORES=$(sysctl -n hw.logicalcpu)
PLUGIN_CORES=$(echo "$PLUGIN_OUT" | grep "^--Cores" | grep -oE '[0-9]+' | head -1 || echo "0")
[ "$PLUGIN_CORES" = "$SYS_CORES" ] && R="pass" || R="fail"
check "Core count matches system" "$R" "system=$SYS_CORES  plugin=$PLUGIN_CORES"
add_score 5 $([ "$R" = "pass" ] && echo 5 || echo 0)

SYS_TOTAL_MB=$(( $(sysctl -n hw.memsize) / 1048576 ))
PLUGIN_FREE=$(echo "$PLUGIN_OUT" | grep "^--Free" | grep -oE '[0-9]+' | head -1 || echo "0")
SYS_FREE=$(vm_stat | awk '
    /page size of/      { match($0,/[0-9]+/); page=substr($0,RSTART,RLENGTH)+0 }
    /Pages free/        { gsub(/\./,""); free=$NF }
    /Pages speculative/ { gsub(/\./,""); spec=$NF }
    END { if(page==0)page=16384; printf "%d", int((free+spec)*page/1048576) }
')
FREE_DIFF=$(awk "BEGIN{d=$PLUGIN_FREE-$SYS_FREE; print (d<0?-d:d)}")
info "Free memory — Plugin: ${PLUGIN_FREE} MB   System: ${SYS_FREE} MB   Δ ${FREE_DIFF} MB"
# Allow ≤256MB drift (memory changes rapidly between the two reads)
if lte "$FREE_DIFF" 256; then R="pass"; else R="fail"; fi
check "Free memory within ±256 MB of system (live drift allowed)" "$R" "Δ=${FREE_DIFF} MB"
add_score 10 $([ "$R" = "pass" ] && echo 10 || echo 0)

# ───────────────────────────────────────────────────────────────────────────
header "7  RESULTS SUMMARY"
# ───────────────────────────────────────────────────────────────────────────
echo ""

TOTAL_CHECKS=$((CHECKS_PASSED + CHECKS_FAILED))
PCT_CHECKS=$(awk "BEGIN{printf \"%d\", ($TOTAL_CHECKS>0) ? $CHECKS_PASSED/$TOTAL_CHECKS*100 : 0}")
PCT_SCORE=$(awk  "BEGIN{printf \"%d\", ($MAX_SCORE>0) ? $TOTAL_SCORE/$MAX_SCORE*100 : 0}")

echo -e "  Correctness  ${CHECKS_PASSED}/${TOTAL_CHECKS} checks passed  (${PCT_CHECKS}%)"
echo -e "  Score        ${TOTAL_SCORE}/${MAX_SCORE} pts  (${PCT_SCORE}%)"
echo ""
echo -e "  Timing breakdown:"
printf  "    %-38s %.3fs\n" "get_pressure()"           "$T_PRESSURE"
printf  "    %-38s %.3fs\n" "get_vm_stats()"           "$T_VM_STAT"
printf  "    %-38s %.3fs\n" "get_swap()"               "$T_SWAP"
printf  "    %-38s %.3fs\n" "get_core_count()"         "$T_CORES"
printf  "    %-38s %.3fs\n" "fmt_mb() ×8"              "$T_FMT"
printf  "    %-38s %.3fs  ← macOS API constraint\n"   "get_top_data() [top -l 2]" "$T_TOP"
printf  "    %-38s %.3fs\n" "Full plugin (end-to-end)" "$T_FULL"
echo ""
printf  "    %-38s %s MB\n" "Plugin peak RSS"          "$RSS_PLUGIN_MB"
printf  "    %-38s %s MB\n" "Watcher peak RSS"         "$RSS_WATCHER_MB"
printf  "    %-38s %s%% of one core / min\n" "CPU duty cycle" "$DUTY_PCT"
echo ""

if   gte "$PCT_SCORE" 90; then
    echo -e "  ${GREEN}${BOLD}Verdict  EXCELLENT — well-optimised, no issues found${NC}"
elif gte "$PCT_SCORE" 75; then
    echo -e "  ${YELLOW}${BOLD}Verdict  GOOD — minor issues, check warnings above${NC}"
elif gte "$PCT_SCORE" 60; then
    echo -e "  ${YELLOW}Verdict  ACCEPTABLE — some improvements recommended${NC}"
else
    echo -e "  ${RED}Verdict  NEEDS WORK — review failing checks above${NC}"
fi

echo ""

# ─── Optional JSON output ─────────────────────────────────────────────────
if $JSON_MODE; then
    JSON_FILE="$REPO_DIR/benchmark_results.json"
    {
        printf '{\n'
        printf '  "date": "%s",\n'        "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf '  "system": "%s %s",\n'   "$(sw_vers -productName)" "$(sw_vers -productVersion)"
        printf '  "cores": %s,\n'         "$SYS_CORES"
        printf '  "score": { "earned": %s, "max": %s, "pct": %s },\n' \
            "$TOTAL_SCORE" "$MAX_SCORE" "$PCT_SCORE"
        printf '  "checks": { "passed": %s, "failed": %s },\n' \
            "$CHECKS_PASSED" "$CHECKS_FAILED"
        printf '  "resource": { "plugin_rss_mb": %s, "watcher_rss_mb": %s, "duty_pct_per_min": %s },\n' \
            "$RSS_PLUGIN_MB" "$RSS_WATCHER_MB" "$DUTY_PCT"
        printf '  "timings": [\n'
        local sep=""
        for entry in "${BENCH_RESULTS[@]}"; do
            printf '%s    %s\n' "$sep" "$entry"
            sep=","
        done
        printf '  ]\n'
        printf '}\n'
    } > "$JSON_FILE"
    echo -e "  ${GRAY}JSON results → $JSON_FILE${NC}\n"
fi
