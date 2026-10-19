#!/bin/bash
# uninstall.sh — macOS Memory Manager uninstaller

INSTALL_DIR="$HOME/Library/macos-memory-manager"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
SWIFTBAR_PLUGINS="$HOME/Library/Application Support/SwiftBar/Plugins"

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

ok()   { echo -e "${GREEN}  ✓${NC} $1"; }
step() { echo -e "\n${YELLOW}▶ $1${NC}"; }

echo ""
echo "  macOS Memory Manager — Uninstaller"
echo "  ────────────────────────────────────"
echo ""

step "Unloading LaunchAgents"
for label in com.user.cache-cleanup com.user.memory-watcher; do
    plist="$LAUNCH_AGENTS/$label.plist"
    if [ -f "$plist" ]; then
        launchctl unload "$plist" 2>/dev/null || true
        rm -f "$plist"
        ok "Removed: $label.plist"
    fi
done

step "Removing SwiftBar plugin"
rm -f "$SWIFTBAR_PLUGINS/memory_status.60s.sh"
ok "Plugin removed"

if pgrep -x SwiftBar &>/dev/null; then
    killall SwiftBar 2>/dev/null || true
    sleep 1
    open -a SwiftBar 2>/dev/null || true
    ok "SwiftBar restarted"
fi

step "Removing install directory"
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    ok "Removed: $INSTALL_DIR"
fi

step "Removing sudoers entry (if exists)"
if [ -f "/etc/sudoers.d/macos-memory-manager" ]; then
    sudo rm -f "/etc/sudoers.d/macos-memory-manager"
    ok "sudoers entry removed"
fi

echo ""
echo "  Uninstall complete."
echo ""
