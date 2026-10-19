#!/bin/bash
# cache_cleanup.sh — Automatic macOS cache cleanup
# Scheduled to run every 3 days via launchd

INSTALL_DIR="$HOME/Library/macos-memory-manager"
LOG_FILE="$INSTALL_DIR/logs/cache_cleanup.log"
CACHE_DIR="$HOME/Library/Caches"

mkdir -p "$INSTALL_DIR/logs"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# ────────────────────────────────────────────
log "====== CACHE CLEANUP START ======"

BEFORE=$(df -h / | awk 'NR==2 {print $4}')
CACHE_BEFORE=$(du -sh "$CACHE_DIR" 2>/dev/null | awk '{print $1}')
log "Free space before: $BEFORE | Library/Caches: $CACHE_BEFORE"

# ────────────────────────────────────────────
log "--- [1/7] Homebrew ---"
if command -v brew &>/dev/null; then
    brew cleanup --prune=all 2>&1 | tail -5 | tee -a "$LOG_FILE"
    log "Homebrew: cleanup done"
else
    log "Homebrew: not installed, skipping"
fi

# ────────────────────────────────────────────
log "--- [2/7] Yarn ---"
if command -v yarn &>/dev/null; then
    yarn cache clean 2>&1 | tee -a "$LOG_FILE"
    log "Yarn: cache cleared"
else
    log "Yarn: not installed, skipping"
fi

# ────────────────────────────────────────────
log "--- [3/7] pip ---"
if command -v pip3 &>/dev/null; then
    pip3 cache purge 2>&1 | tee -a "$LOG_FILE"
    log "pip3: cache cleared"
else
    log "pip3: not installed, skipping"
fi

# ────────────────────────────────────────────
log "--- [4/7] Dev caches (TypeScript, node-gyp) ---"
for dir in typescript node-gyp; do
    TARGET="$CACHE_DIR/$dir"
    if [ -d "$TARGET" ]; then
        SIZE=$(du -sh "$TARGET" 2>/dev/null | awk '{print $1}')
        rm -rf "$TARGET"
        log "Removed: $dir ($SIZE)"
    fi
done

# ────────────────────────────────────────────
log "--- [5/7] App caches (Chrome, ShipIt updaters) ---"
for dir in Google "notion.id.ShipIt" "com.mongodb.compass.ShipIt"; do
    TARGET="$CACHE_DIR/$dir"
    if [ -d "$TARGET" ]; then
        SIZE=$(du -sh "$TARGET" 2>/dev/null | awk '{print $1}')
        rm -rf "$TARGET"
        log "Removed: $dir ($SIZE)"
    fi
done

# ────────────────────────────────────────────
log "--- [6/7] Old logs (+7 days) ---"
LOGS_REMOVED=$(find "$HOME/Library/Logs" -type f -mtime +7 -delete -print 2>/dev/null | wc -l | tr -d ' ')
log "Old logs removed: $LOGS_REMOVED file(s)"

# ────────────────────────────────────────────
log "--- [7/7] System temp files (+3 days) ---"
TEMP_REMOVED=$(find /private/var/folders -type f -mtime +3 -delete -print 2>/dev/null | wc -l | tr -d ' ')
log "Temp files removed: $TEMP_REMOVED file(s)"

# ────────────────────────────────────────────
AFTER=$(df -h / | awk 'NR==2 {print $4}')
CACHE_AFTER=$(du -sh "$CACHE_DIR" 2>/dev/null | awk '{print $1}')
log "Free space after: $AFTER | Library/Caches: $CACHE_AFTER"
log "====== CACHE CLEANUP DONE ======"
log ""
