# Multi-Playwright for Claude Code

Run multiple Claude Code sessions with isolated Chrome browsers. Each project gets its own Chrome instance with the right Google account.

## Problem

- Multiple Claude Code sessions fight over the same Chrome
- Different projects need different Google accounts (work vs personal)
- Sessions overwrite each other's cookies and tabs

## Solution

```
Directory you launch Claude from  →  determines Chrome profile
```

| Directory              | Profile    | Chrome          | Account            |
|------------------------|------------|-----------------|---------------------|
| `~/projects/work-*`   | work       | Port 9223       | user@company.com   |
| `~/projects/personal-*`| personal  | Port 9224       | me@gmail.com       |
| `~/projects/dev-*`    | dev        | Port 9225       | (clean browser)    |

Multiple sessions in the same project **share** Chrome via CDP (Chrome DevTools Protocol).

## Quick Start

### 1. Create your config

```bash
cp projects.example projects.conf
```

Edit `projects.conf`:
```
work      | user@company.com   | ~/projects/work-* ~/projects/client-*
personal  | me@gmail.com       | ~/ ~/projects/blog ~/projects/hobby
dev       | clean              | ~/projects/dev-* ~/projects/experiments
```

Format: `name | google_account | directories` (space-separated, supports `*` globs)

### 2. Run setup

```bash
./setup.sh
```

This will:
- Generate `~/.claude/chrome-profiles.json` (profile registry)
- Install `~/.claude/scripts/playwright-project.sh` (launcher)
- Register Playwright MCP in Claude Code for each directory
- Create Chrome data directories (`~/.chrome-pw-*`)

### 3. Restart Claude Code

```bash
cd ~/projects/work-app && claude
```

First launch for each profile: log into Google in the Chrome window that opens. Your login persists across sessions.

## Adding a New Profile

```bash
# Create profile + bind directories
./scripts/add-profile.sh myproject user@example.com ~/projects/myproject

# Or bind a directory to an existing profile
cd ~/projects/new-repo
./scripts/bind-directory.sh work
```

## How It Works

```
claude (from ~/projects/work-app)
  ↓
~/.claude.json has: playwright → playwright-project.sh work
  ↓
playwright-project.sh reads chrome-profiles.json
  ↓
work → port 9223, ~/.chrome-pw-work
  ↓
Port 9223 free?
  ├─ Yes → Launch new Chrome on port 9223
  └─ No  → Connect to existing Chrome via CDP
  ↓
Playwright MCP connected
```

### Multiple sessions, same project

When you open a second Claude Code session for the same project, the launcher detects Chrome is already running on that port and connects via CDP. Both sessions share the same Chrome — they can see each other's tabs.

### Unregistered directories

If you start Claude Code from a directory that wasn't in your `projects.conf`, it uses the **default profile** (first one listed). You can always bind it later:

```bash
cd ~/some-new-project
~/.claude/scripts/bind-directory.sh work
# restart claude
```

## CLAUDE.md Instructions for Agents

Add this to your project's `CLAUDE.md` so the AI agent knows about the browser profile system:

```markdown
## Browser Profile

This session uses the Playwright MCP with a project-specific Chrome profile.
The Chrome profile is determined by the directory Claude Code was launched from.

- You CANNOT switch Chrome profiles within a session
- To use a different profile: exit this session, cd to the right directory, start claude again
- Available profiles are in ~/.claude/chrome-profiles.json
- To bind this directory to a different profile: ~/.claude/scripts/bind-directory.sh <profile-name>
```

## File Structure

```
~/.claude/
├── chrome-profiles.json              # Profile registry (name → port + dir)
├── scripts/
│   └── playwright-project.sh         # Smart launcher (picks Chrome by project)
└── .claude.json                      # MCP registrations live here (NOT settings.json)

~/.chrome-pw-work/                    # Chrome data for "work" profile
~/.chrome-pw-personal/                # Chrome data for "personal" profile
~/.chrome-pw-dev/                     # Chrome data for "dev" profile
```

## Important Notes

### MCP registration is in `.claude.json`, not `settings.json`

Claude Code reads MCP server config from `~/.claude.json` (the state file), **not** from `settings.json`. Use `claude mcp add` to register servers — it writes to the correct location.

```bash
# Register for current directory (local scope)
claude mcp add -s local playwright -- ~/.claude/scripts/playwright-project.sh work

# Register global default (user scope)
claude mcp add -s user playwright -- ~/.claude/scripts/playwright-project.sh
```

### Never kill Chrome with pkill

```bash
# BAD — kills the MCP process too
pkill -f "chrome-playwright"

# GOOD — close Chrome normally or let the session end
```

### Changes need a full restart

After changing MCP config, fully restart Claude Code (`/exit` then `claude`). The `/mcp` command alone doesn't reload the config.

## Troubleshooting

**"1 MCP server failed" at startup**
- The launcher script isn't registered for this directory
- Fix: `cd /path/to/project && claude mcp add -s local playwright -- ~/.claude/scripts/playwright-project.sh <profile>`

**Wrong Chrome profile opens**
- Check: `claude mcp get playwright` — shows which launcher args are configured
- Stale config in `.claude.json` may override — clear it:
  ```bash
  jq '.projects["/path/to/dir"].mcpServers = {}' ~/.claude.json > /tmp/cj.tmp && mv /tmp/cj.tmp ~/.claude.json
  ```
  Then re-register with `claude mcp add`

**Chrome already running / port locked**
- Another session is using this Chrome. The launcher should auto-connect via CDP.
- If stuck: close all Claude Code sessions for that project, then try again.

## License

MIT
