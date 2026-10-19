#!/bin/bash
# install.sh — macOS Memory Manager installer
set -e

INSTALL_DIR="$HOME/Library/macos-memory-manager"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
SWIFTBAR_PLUGINS="$HOME/Library/Application Support/SwiftBar/Plugins"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}  ✓${NC} $1"; }
warn() { echo -e "${YELLOW}  !${NC} $1"; }
fail() { echo -e "${RED}  ✗${NC} $1"; exit 1; }
step() { echo -e "\n${YELLOW}▶ $1${NC}"; }

echo ""
echo "  macOS Memory Manager — Installer"
echo "  ─────────────────────────────────"
echo "  Install dir: $INSTALL_DIR"
echo ""

# ─────────────────────────────────────────────────────────────
step "1/5  Checking requirements"
# ─────────────────────────────────────────────────────────────

[[ "$(uname)" == "Darwin" ]] || fail "macOS only"
sw_vers -productVersion | awk -F. '$1 < 12 {exit 1}' || fail "Requires macOS 12 (Monterey) or later"
ok "macOS $(sw_vers -productVersion)"

if ! command -v swiftbar &>/dev/null && [ ! -d "/Applications/SwiftBar.app" ]; then
    warn "SwiftBar not found — installing via Homebrew..."
    command -v brew &>/dev/null || fail "Homebrew is required. Install from https://brew.sh"
    brew install swiftbar
    ok "SwiftBar installed"
else
    ok "SwiftBar found"
fi

# ─────────────────────────────────────────────────────────────
step "2/5  Installing scripts"
# ─────────────────────────────────────────────────────────────

mkdir -p "$INSTALL_DIR/scripts" "$INSTALL_DIR/logs"

cp "$REPO_DIR/scripts/cache_cleanup.sh"  "$INSTALL_DIR/scripts/"
cp "$REPO_DIR/scripts/memory_watcher.sh" "$INSTALL_DIR/scripts/"
chmod +x "$INSTALL_DIR/scripts/"*.sh
ok "Scripts copied to $INSTALL_DIR/scripts/"

# ─────────────────────────────────────────────────────────────
step "3/5  Installing LaunchAgents"
# ─────────────────────────────────────────────────────────────

mkdir -p "$LAUNCH_AGENTS"

for plist in "$REPO_DIR/launchagents/"*.plist; do
    basename=$(basename "$plist")
    dest="$LAUNCH_AGENTS/$basename"

    # Replace __INSTALL_DIR__ placeholder with actual path
    sed "s|__INSTALL_DIR__|$INSTALL_DIR|g" "$plist" > "$dest"

    # Unload if already running, then load
    launchctl unload "$dest" 2>/dev/null || true
    launchctl load "$dest"
    ok "Loaded: $basename"
done

# ─────────────────────────────────────────────────────────────
step "4/5  Installing SwiftBar plugin"
# ─────────────────────────────────────────────────────────────

mkdir -p "$SWIFTBAR_PLUGINS"
cp "$REPO_DIR/swiftbar/memory_status.60s.sh" "$SWIFTBAR_PLUGINS/"
chmod +x "$SWIFTBAR_PLUGINS/memory_status.60s.sh"
ok "Plugin installed to SwiftBar/Plugins"

# Point SwiftBar at its plugin directory
defaults write com.ameba.SwiftBar PluginDirectory "$SWIFTBAR_PLUGINS" 2>/dev/null || true

# Restart SwiftBar if it's running
if pgrep -x SwiftBar &>/dev/null; then
    killall SwiftBar 2>/dev/null || true
    sleep 1
    open -a SwiftBar
    ok "SwiftBar restarted"
else
    open -a SwiftBar 2>/dev/null || warn "Open SwiftBar manually from /Applications"
fi

# ─────────────────────────────────────────────────────────────
step "5/5  Optional: passwordless sudo for purge"
# ─────────────────────────────────────────────────────────────

USER=$(whoami)
SUDOERS_FILE="/etc/sudoers.d/macos-memory-manager"

if [ -f "$SUDOERS_FILE" ]; then
    ok "sudoers entry already exists — skipping"
else
    echo ""
    echo "  The 'Purge RAM' button requires passwordless sudo for /usr/sbin/purge."
    echo "  This is optional — everything else works without it."
    echo ""
    read -r -p "  Configure passwordless sudo for purge? [y/N] " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        echo "$USER ALL=(ALL) NOPASSWD: /usr/sbin/purge, /usr/bin/dscacheutil, /bin/kill" | \
            sudo tee "$SUDOERS_FILE" > /dev/null
        sudo chmod 440 "$SUDOERS_FILE"
        ok "sudoers configured"
    else
        warn "Skipped — Purge RAM button will silently fail without sudo access"
    fi
fi

# ─────────────────────────────────────────────────────────────
echo ""
echo "  ─────────────────────────────────────────"
echo "  Installation complete!"
echo ""
echo "  Widget:  Look for the chip icon in your menu bar"
echo "  Status:  $INSTALL_DIR/scripts/memory_watcher.sh --status"
echo "  Logs:    $INSTALL_DIR/logs/"
echo "  ─────────────────────────────────────────"
echo ""
