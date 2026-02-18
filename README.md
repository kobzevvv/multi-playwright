# Playwright MCP Multi-Session Guide

> How to run multiple AI coding sessions (Claude Code, Cursor, etc.) with browser automation — without them fighting over the same Chrome instance. Supports **multiple projects with different Google accounts**.

## The Problem

You're using [Playwright MCP](https://github.com/microsoft/playwright-mcp) to give your AI assistant browser access. It works great — until:

1. **You open a second session** → `Profile already in use`
2. **You work on multiple projects** with different Google accounts → wrong account, mixed cookies
3. **Your personal Chrome** and the AI's Chrome interfere with each other

## The Solution

A **project-aware launcher** that maps each project to its own Chrome instance with the right account:

```
┌─────────────────────────────────────────────────────────────────┐
│                     chrome-profiles.json                        │
│  "work"     → port 9223, ~/.chrome-pw-work,     you@company    │
│  "personal" → port 9224, ~/.chrome-pw-personal,  you@gmail     │
│  "dev"      → port 9225, ~/.chrome-pw-dev,       (clean)       │
└──────────────────────────┬──────────────────────────────────────┘
                           │
           playwright-project.sh reads config
                           │
        ┌──────────────────┼──────────────────┐
        ▼                  ▼                  ▼
┌───────────────┐  ┌───────────────┐  ┌───────────────┐
│ Chrome (9223) │  │ Chrome (9224) │  │ Chrome (9225) │
│ Work account  │  │ Personal acct │  │ Clean browser │
│ Sheets, Ads   │  │ Gmail, Docs   │  │ Dev tools     │
└───────┬───────┘  └───────┬───────┘  └───────┬───────┘
        │                  │                  │
┌───────┴───────┐  ┌───────┴───────┐  ┌───────┴───────┐
│ Claude Code   │  │ Claude Code   │  │ Claude Code   │
│ ~/work-proj/  │  │ ~/personal/   │  │ ~/dev-proj/   │
└───────────────┘  └───────────────┘  └───────────────┘
```

Each Chrome instance is **fully independent** — different ports, different data dirs, different accounts. Your personal Chrome (launched from the Dock) is not affected at all.

## Quick Setup

### 1. Create the profile registry

Copy and edit to match your projects:

```bash
mkdir -p ~/.claude/configs
cp configs/chrome-profiles-example.json ~/.claude/chrome-profiles.json
# Edit ~/.claude/chrome-profiles.json with your projects/accounts
```

Example `chrome-profiles.json`:
```json
{
  "default": "work",
  "profiles": {
    "work": {
      "port": 9223,
      "userDataDir": "~/.chrome-pw-work",
      "account": "you@company.com",
      "note": "Work Google account"
    },
    "personal": {
      "port": 9224,
      "userDataDir": "~/.chrome-pw-personal",
      "account": "you@gmail.com",
      "note": "Personal account"
    },
    "dev": {
      "port": 9225,
      "userDataDir": "~/.chrome-pw-dev",
      "account": null,
      "note": "Clean browser for testing"
    }
  }
}
```

### 2. Install the launcher script

```bash
mkdir -p ~/.claude/scripts
cp scripts/playwright-project.sh ~/.claude/scripts/
chmod +x ~/.claude/scripts/playwright-project.sh
```

### 3. Configure MCP (global default)

In `~/.claude/settings.json`:

```json
{
  "mcpServers": {
    "playwright": {
      "command": "~/.claude/scripts/playwright-project.sh",
      "args": ["work"]
    }
  }
}
```

This sets the **default** project. Sessions started from any directory will use this unless overridden.

### 4. Override per project directory

Create project-level settings so Claude Code auto-selects the right Chrome:

```bash
# For personal projects started from ~/
# File: ~/.claude/projects/-Users-YOU/settings.json
{
  "mcpServers": {
    "playwright": {
      "command": "~/.claude/scripts/playwright-project.sh",
      "args": ["personal"]
    }
  }
}
```

Claude Code encodes directory paths by replacing `/` with `-` and prepending `-`:
- `/Users/you/work/project-a/` → `~/.claude/projects/-Users-you-work-project-a/settings.json`
- `/Users/you/` → `~/.claude/projects/-Users-you/settings.json`

### 5. First-time login per Chrome instance

Each new Chrome instance starts clean. Log in to your accounts **once**:

```bash
# Launch Chrome for "personal" profile manually
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --remote-debugging-port=9224 \
  --user-data-dir=$HOME/.chrome-pw-personal
```

Log in to Google, close Chrome. The session persists permanently.

## How It Works

### Launcher logic

```
START
  ├─ Read project name from: arg > $CHROME_PROJECT env > config default
  ├─ Look up port + userDataDir from chrome-profiles.json
  ├─ Port free? → Launch new Chrome → Done
  └─ Port busy? → Connect via CDP (another session already running) → Done
```

### Multi-tab within a session

Each session can manage multiple browser tabs:

```
browser_tabs → action: list              # see all tabs
browser_tabs → action: new               # open new tab
browser_tabs → action: select, index: 0  # switch to tab
browser_tabs → action: close, index: 1   # close tab
```

Switching tabs preserves full page context.

### Personal Chrome is not affected

| | Your Chrome | Playwright Chrome |
|---|---|---|
| Data dir | `~/Library/Application Support/Google/Chrome/` | `~/.chrome-pw-*/` |
| CDP port | None | 9223 / 9224 / 9225 |
| Launched by | You (Dock icon) | Playwright MCP |
| Affects the other? | No | No |

## Use Cases

### Multiple businesses, different Google accounts
- **Company A** session → Chrome with `team@company-a.com` (Google Ads, Sheets)
- **Company B** session → Chrome with `admin@company-b.com` (different Ads account)
- **Personal** session → Chrome with `you@gmail.com` (personal docs, recruiting)

Each runs independently, correct account every time.

### Two sessions, same project
Both connect to the same Chrome via CDP, sharing tabs. Use `browser_tabs` to coordinate which tab each session uses.

### Clean browser for development
A `dev` profile with no account — perfect for testing websites, debugging, experiments.

## Adding a New Project

1. Add entry to `~/.claude/chrome-profiles.json`:
```json
"new-project": {
  "port": 9226,
  "userDataDir": "~/.chrome-pw-newproject",
  "account": "account@example.com",
  "note": "Description"
}
```

2. Create project-level settings for relevant directories:
```bash
mkdir -p ~/.claude/projects/-Users-YOU-path-to-project
echo '{"mcpServers":{"playwright":{"command":"~/.claude/scripts/playwright-project.sh","args":["new-project"]}}}' \
  > ~/.claude/projects/-Users-YOU-path-to-project/settings.json
```

3. First launch → log in to accounts in the new Chrome window.

## Troubleshooting

### "Failed to launch browser" / Profile locked
Another Chrome is using the same `user-data-dir`. Check for zombie processes:
```bash
ps aux | grep "chrome-pw" | grep -v grep
```

### MCP dies mid-session
Chrome crashed or was killed. Restart: `/mcp` in Claude Code.

**NEVER** use `pkill -f "chrome-pw"` — it matches the MCP process path too. Use `kill <specific_PID>`.

### Wrong Google account
Check which project your session is using:
```bash
# The launcher prints this to stderr on startup:
# [playwright-project] Project: work | Port: 9223 | Dir: ~/.chrome-pw-work
```

### Plugin override hijacks config
```bash
# Should be {} (empty object)
cat ~/.claude/plugins/marketplaces/claude-plugins-official/external_plugins/playwright/.mcp.json
```

### Diagnostic commands
```bash
# Check all Chrome instances
for port in 9223 9224 9225; do
  curl -s --max-time 1 "http://localhost:$port/json/version" > /dev/null 2>&1 \
    && echo "Port $port: running" || echo "Port $port: not running"
done

# List tabs on a specific Chrome
curl -s http://localhost:9223/json | python3 -c "
import json, sys
for t in json.load(sys.stdin):
    print(f'{t[\"title\"][:50]} — {t[\"url\"][:70]}')
"
```

## File Structure

```
~/.claude/
├── chrome-profiles.json              # Project → Chrome mapping
├── scripts/
│   └── playwright-project.sh         # Smart launcher
├── settings.json                     # Global MCP config (default project)
└── projects/
    ├── -Users-you-work-project/
    │   └── settings.json             # Override: "work" project
    └── -Users-you-personal/
        └── settings.json             # Override: "personal" project

~/.chrome-pw-work/                    # Chrome data for work
~/.chrome-pw-personal/                # Chrome data for personal
~/.chrome-pw-dev/                     # Chrome data for dev (clean)
```

## Compatibility

Tested with:
- **Claude Code** (Anthropic CLI) — primary target
- **macOS** (Sonoma / Sequoia)
- **Google Chrome** 145+
- **Playwright MCP** `@playwright/mcp@latest`

Should also work with:
- **Cursor**, **Windsurf**, **VS Code + Continue** — any editor supporting MCP
- **Linux** (adjust Chrome path in launch command)
- **Windows** (needs PowerShell equivalent of the launcher)

## Contributing

Found a better approach? Have a setup for Cursor or Linux? PRs welcome!

## License

MIT
