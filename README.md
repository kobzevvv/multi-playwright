# Playwright MCP Multi-Session Guide

> How to run multiple AI coding sessions (Claude Code, Cursor, etc.) with browser automation — without them fighting over the same Chrome instance.

## The Problem

You're using [Playwright MCP](https://github.com/anthropics/anthropic-quickstarts/tree/main/mcp-playwright) to give your AI assistant browser access. It works great — until you open a second session:

```
Error: Failed to launch the browser process
browserType.launchPersistentContext: Profile already in use
```

**Why?** Chrome locks its `user-data-dir` at the process level. Two Playwright instances can't share the same Chrome profile simultaneously.

**And if you need authenticated sessions** (Google Sheets, Webflow, internal tools), a clean/disposable browser isn't an option — you need persistent profiles with saved logins.

## The Solution

An **auto-launcher script** that gives each session its own Chrome instance on a unique port:

```
Session A starts → Chrome on port 9223 (user-data-dir A)
Session B starts → port 9223 busy → Chrome on port 9224 (user-data-dir B)
Session C starts → both busy → connects to Chrome B via CDP (shares tabs)
```

Within each session, use **multi-tab** (`browser_tabs`) to work with multiple sites simultaneously.

```
┌─────────────────────────┐    ┌─────────────────────────┐
│  Chrome A (port 9223)   │    │  Chrome B (port 9224)   │
│  Authenticated profile  │    │  Authenticated profile  │
│  Tab 0: Google Sheets   │    │  Tab 0: Webflow         │
│  Tab 1: Google Ads      │    │  Tab 1: Analytics       │
└───────────┬─────────────┘    └───────────┬─────────────┘
            │ CDP                          │ CDP
┌───────────┴─────────────┐    ┌───────────┴─────────────┐
│  AI Session A           │    │  AI Session B           │
│  Playwright MCP         │    │  Playwright MCP         │
└─────────────────────────┘    └─────────────────────────┘
```

## Quick Setup

### 1. Create the auto-launcher script

```bash
mkdir -p ~/.claude/scripts
cp scripts/playwright-auto.sh ~/.claude/scripts/
chmod +x ~/.claude/scripts/playwright-auto.sh
```

Or create it manually — see [`scripts/playwright-auto.sh`](scripts/playwright-auto.sh).

### 2. Create Chrome configs

```bash
mkdir -p ~/.claude/configs
cp configs/playwright-chrome-A.json ~/.claude/configs/
cp configs/playwright-chrome-B.json ~/.claude/configs/
```

### 3. Update MCP settings

In your `~/.claude/settings.json` (or equivalent MCP config), replace the Playwright server entry:

```json
{
  "mcpServers": {
    "playwright": {
      "command": "/path/to/your/.claude/scripts/playwright-auto.sh",
      "args": []
    }
  }
}
```

**For Cursor / other editors** — adjust the MCP config path per your editor's documentation.

### 4. First-time setup for Chrome B

The second Chrome instance (`~/.chrome-playwright-2`) starts with a clean profile. You need to log in to your accounts **once**:

```bash
# Launch Chrome B manually to log in
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --remote-debugging-port=9224 \
  --profile-directory="Profile 30" \
  --user-data-dir=$HOME/.chrome-playwright-2
```

Log in to Google, Webflow, etc. Close it. Done — sessions persist.

## How It Works

### Auto-launcher logic

```
START
  ├─ Port 9223 free? → Launch Chrome A → Done
  ├─ Port 9223 busy, 9224 free? → Launch Chrome B → Done
  └─ Both busy? → Connect to Chrome B via CDP → Done
```

The script uses `curl` to check if a port responds to CDP (`/json/version`). Takes ~1 second.

Key detail: the script uses `exec` to replace itself with the MCP process, so stdin/stdout pass through cleanly for JSON-RPC communication.

### Multi-tab within a session

Each session can manage multiple browser tabs without conflicts:

```
browser_tabs → action: list              # see all tabs
browser_tabs → action: new               # open new tab
browser_tabs → action: select, index: 0  # switch to tab
browser_tabs → action: close, index: 1   # close tab
```

Switching tabs preserves the full page context (DOM, scroll position, form state).

### Your personal Chrome is not affected

Playwright Chrome and your regular Chrome are **completely independent**:

| | Your Chrome | Playwright Chrome |
|---|---|---|
| Data dir | `~/Library/Application Support/Google/Chrome/` | `~/.chrome-playwright/` |
| CDP port | None | 9223 / 9224 |
| Launched by | You (Dock icon) | Playwright MCP |
| Affects the other? | No | No |

## Use Cases

### Single session, multiple sites
One AI session working with Google Sheets in tab 0 and a web app in tab 1:
```
→ browser_tabs: new
→ browser_navigate: https://docs.google.com/spreadsheets/...
→ (read data from sheets)
→ browser_tabs: select index 1
→ browser_navigate: https://app.example.com
→ (paste data into web app)
```

### Two sessions, independent work
- **Session A**: Managing Google Ads campaigns, reading spreadsheets
- **Session B**: Editing Webflow site, deploying changes

Each has its own Chrome, own tabs, zero interference.

### Authenticated workflows
Google Sheets, Google Ads, Webflow Designer, internal dashboards — all work because you're using persistent Chrome profiles with saved logins. No need to re-authenticate every session.

## Configuration Reference

### Files

| File | Purpose |
|------|---------|
| `~/.claude/scripts/playwright-auto.sh` | Auto-selects free port and launches Chrome |
| `~/.claude/configs/playwright-chrome-A.json` | Chrome A config: port 9223 |
| `~/.claude/configs/playwright-chrome-B.json` | Chrome B config: port 9224 |
| `~/.chrome-playwright/` | Chrome A data (persistent profile) |
| `~/.chrome-playwright-2/` | Chrome B data (persistent profile) |

### Chrome config format

```json
{
  "browser": {
    "launchOptions": {
      "args": [
        "--profile-directory=Profile 30",
        "--remote-debugging-port=9223"
      ]
    }
  }
}
```

- `--profile-directory`: Which Chrome profile to use within the user-data-dir
- `--remote-debugging-port`: Fixed CDP port (otherwise Playwright picks a random one)

### Adding more sessions

To support 3+ simultaneous sessions, extend the auto-launcher script with additional ports (9225, 9226, etc.) and user-data-dirs. See the script comments for the pattern.

## Troubleshooting

### "Failed to launch browser" / Profile locked
**Cause**: Another Chrome is using the same `user-data-dir`.
**Fix**: The auto-launcher handles this. If it still fails, check for zombie Chrome processes:
```bash
ps aux | grep "chrome-playwright" | grep -v grep
```

### MCP dies mid-session
**Cause**: Chrome crashed, or someone killed it with `pkill`.
**Fix**: Restart MCP (`/mcp` in Claude Code).
**Prevention**: NEVER use `pkill -f "chrome-playwright"` — the pattern matches the MCP process path too! Use `kill <specific_PID>` instead.

### Second Chrome has no logins
**Cause**: `~/.chrome-playwright-2` was created fresh.
**Fix**: Launch Chrome B manually, log in once. See [First-time setup](#4-first-time-setup-for-chrome-b).

### Plugin override hijacks config
Some MCP plugin systems (Claude Code plugins) can override your `settings.json` config. Check:
```bash
# Should be {} (empty object)
cat ~/.claude/plugins/marketplaces/claude-plugins-official/external_plugins/playwright/.mcp.json
```

### Diagnostic commands
```bash
# Check both Chrome instances
curl -s http://localhost:9223/json/version && echo "A: running" || echo "A: not running"
curl -s http://localhost:9224/json/version && echo "B: running" || echo "B: not running"

# List tabs in Chrome A
curl -s http://localhost:9223/json | python3 -c "
import json, sys
for t in json.load(sys.stdin):
    print(f'{t[\"title\"][:50]} — {t[\"url\"][:70]}')
"

# MCP processes
ps aux | grep "playwright-mcp\|playwright-auto" | grep -v grep
```

## Compatibility

Tested with:
- **Claude Code** (Anthropic CLI) — primary target
- **macOS** (Sonoma / Sequoia)
- **Google Chrome** 145+
- **Playwright MCP** `@playwright/mcp@latest`

Should also work with:
- **Cursor**, **Windsurf**, **VS Code + Continue** — any editor that supports MCP servers
- **Linux** (adjust Chrome path in script)
- **Windows** (needs .bat/PowerShell equivalent of the launcher)

## Contributing

Found a better approach? Have a setup for Cursor or Linux? PRs welcome!

## License

MIT
