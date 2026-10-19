# macOS Memory Manager

A lightweight macOS menu bar widget + background automation to monitor memory pressure and clean caches — no third-party apps, no bloat, pure shell scripts.

![Menu bar showing memory chip icon with percentage](docs/preview.png)

---

## What it does

| Component | What it does | Schedule |
|-----------|-------------|----------|
| **Menu bar widget** | Shows RAM free % + chip icon in top bar. Click to see memory, CPU, top processes, and action buttons. | Refreshes every 60s |
| **Memory watcher** | Checks RAM pressure hourly. Purges RAM + clears app caches when pressure is yellow or red. Sends macOS notification if critical. | Every 1 hour |
| **Cache cleanup** | Cleans Homebrew, Yarn, pip, TypeScript, node-gyp, Chrome, and old temp/log files. | Every 3 days |

### Memory pressure levels

| Level | Free RAM | Action |
|-------|----------|--------|
| 🟢 Normal | ≥ 50% | Log only — no action |
| 🟡 Warning | 25–50% | Purge RAM + clear app caches |
| 🔴 Critical | < 25% | Purge + caches + DNS flush + notification |

---

## Requirements

- macOS 12 (Monterey) or later
- [Homebrew](https://brew.sh) — used to install SwiftBar
- [SwiftBar](https://swiftbar.app) — renders the menu bar plugin (installed automatically)

---

## Installation

```bash
git clone https://github.com/youruser/macos-memory-manager.git
cd macos-memory-manager
chmod +x install.sh
./install.sh
```

The installer will:
1. Install SwiftBar via Homebrew (if not already installed)
2. Copy scripts to `~/Library/macos-memory-manager/scripts/`
3. Install and load both LaunchAgents
4. Install the SwiftBar plugin and restart SwiftBar
5. Optionally configure passwordless `sudo purge` (needed for the Purge RAM button)

After install, the chip icon appears in your menu bar automatically.

---

## Menu bar widget

Click the icon in the top bar to open the dropdown:

```
Memory
  Pressure    Warning
  Free        220 MB
  Inactive    1.2 GB
  Compressed  3.3 GB
  Wired       1.7 GB
  Swap        2.1 / 3.0 GB

CPU
  Usage       14%
  Cores       8

Top Processes
  Google Chrome He   619M
  WindowServer       558M
  Code Helper        512M

──────────────────────────
  Clear Cache          ←  clears dev + app caches, refreshes widget
  Purge RAM            ←  flushes RAM file cache (requires sudo setup)
  Refresh              ←  forces widget refresh
  View Logs            ←  opens log in Console.app
```

### Icon color

The chip icon in the menu bar changes color with pressure:
- **Green** — memory is fine
- **Orange** — pressure is elevated, cleanup triggered
- **Red** — critical, aggressive cleanup + notification

---

## Optional: enable Purge RAM

The **Purge RAM** button needs passwordless `sudo` access to `/usr/sbin/purge`. The installer will ask to set this up. To do it manually:

```bash
sudo visudo -f /etc/sudoers.d/macos-memory-manager
```

Add this line (replace `youruser` with your macOS username):

```
youruser ALL=(ALL) NOPASSWD: /usr/sbin/purge, /usr/bin/dscacheutil, /bin/kill
```

---

## Manual usage

```bash
# Check memory status in the terminal
~/Library/macos-memory-manager/scripts/memory_watcher.sh --status

# Force a full cache cleanup now
~/Library/macos-memory-manager/scripts/memory_watcher.sh --force

# Trigger background jobs manually
launchctl start com.user.memory-watcher
launchctl start com.user.cache-cleanup
```

---

## Logs

All logs are written to `~/Library/macos-memory-manager/logs/`:

| File | Content |
|------|---------|
| `memory_watcher.log` | Hourly pressure checks and cleanup actions |
| `cache_cleanup.log` | 3-day disk cache cleanup results |
| `*_stdout.log` | LaunchAgent stdout (usually empty) |
| `*_stderr.log` | LaunchAgent errors (check here if something breaks) |

```bash
# Follow live log
tail -f ~/Library/macos-memory-manager/logs/memory_watcher.log
```

---

## Uninstall

```bash
./uninstall.sh
```

Removes scripts, LaunchAgents, SwiftBar plugin, and the sudoers entry. Nothing else on your system is touched.

---

## Project structure

```
macos-memory-manager/
├── install.sh                          # One-command installer
├── uninstall.sh                        # Clean removal
├── scripts/
│   ├── memory_watcher.sh               # RAM pressure monitor + cleanup
│   └── cache_cleanup.sh                # Disk cache cleanup
├── swiftbar/
│   └── memory_status.60s.sh            # Menu bar widget plugin
└── launchagents/
    ├── com.user.memory-watcher.plist   # Runs memory_watcher.sh every 1h
    └── com.user.cache-cleanup.plist    # Runs cache_cleanup.sh every 3 days
```

---

## Performance

The widget script runs for ~1.65s every 60 seconds (dominated by `top -l 2` which needs two samples for accurate CPU reading). Tested impact:

- **CPU**: ~2.7% of one core during the 1.65s run, then idle
- **Memory**: 6.4 MB RSS peak (normal for bash)
- **No leaks**: all child processes exit cleanly, no zombies

---

## How macOS memory works

macOS caches aggressively — **high cached memory is not a problem**. The real signal is **memory pressure**:

- `memory_pressure` reports what percentage of RAM is available for new allocations
- When it drops below 50%, macOS starts compressing inactive pages
- When it drops below 25%, swap usage grows and the system may become sluggish

This tool only intervenes when pressure is actually elevated, not just because cached memory looks high.
