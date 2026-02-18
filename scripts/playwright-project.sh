#!/bin/bash
# ============================================================================
# Project-Aware Playwright MCP Launcher
# ============================================================================
#
# Launches the correct Chrome instance based on your project context.
# Each project gets its own Chrome with the right Google account.
#
# How project is determined (in priority order):
#   1. CLI argument:    playwright-project.sh skillset
#   2. Env variable:    CHROME_PROJECT=skillset
#   3. Default from chrome-profiles.json
#
# Setup:
#   1. Edit ~/.claude/chrome-profiles.json to define your projects
#   2. In ~/.claude/settings.json: "playwright": { "command": "this-script.sh", "args": ["project_name"] }
#   3. Override per directory with project-level settings
#
# If the port is already busy (another session of the same project),
# it connects via CDP instead of launching a new Chrome.
# ============================================================================

CONFIG="$HOME/.claude/chrome-profiles.json"

# Determine project name
PROJECT="${1:-${CHROME_PROJECT:-}}"
if [ -z "$PROJECT" ]; then
  PROJECT=$(python3 -c "import json; print(json.load(open('$CONFIG'))['default'])" 2>/dev/null || echo "default")
fi

# Read profile config
read_config() {
  python3 -c "
import json, os
c = json.load(open('$CONFIG'))
p = c['profiles'].get('$PROJECT')
if not p:
    import sys
    print('ERROR', file=sys.stderr)
    sys.exit(1)
print(p['port'])
print(os.path.expanduser(p['userDataDir']))
" 2>/dev/null
}

CONFIG_OUTPUT=$(read_config)
if [ $? -ne 0 ]; then
  echo "[playwright-project] ERROR: Unknown project '$PROJECT'" >&2
  echo "[playwright-project] Available: $(python3 -c "import json; print(', '.join(json.load(open('$CONFIG'))['profiles'].keys()))" 2>/dev/null)" >&2
  exit 1
fi

PORT=$(echo "$CONFIG_OUTPUT" | sed -n '1p')
USER_DATA_DIR=$(echo "$CONFIG_OUTPUT" | sed -n '2p')

echo "[playwright-project] Project: $PROJECT | Port: $PORT | Dir: $USER_DATA_DIR" >&2

# Check if Chrome is already running on this port
if curl -s --max-time 1 "http://localhost:$PORT/json/version" > /dev/null 2>&1; then
  echo "[playwright-project] Chrome already running on port $PORT, connecting via CDP" >&2
  exec npx @playwright/mcp@latest \
    --cdp-endpoint "http://localhost:$PORT"
else
  # Launch new Chrome instance
  mkdir -p "$USER_DATA_DIR"

  # Create temp config with the port
  TEMP_CONFIG=$(mktemp /tmp/playwright-chrome-XXXXXX.json)
  cat > "$TEMP_CONFIG" << CONF
{
  "browser": {
    "launchOptions": {
      "args": ["--remote-debugging-port=$PORT"]
    }
  }
}
CONF

  echo "[playwright-project] Launching Chrome on port $PORT" >&2
  exec npx @playwright/mcp@latest \
    --browser chrome \
    --user-data-dir "$USER_DATA_DIR" \
    --config "$TEMP_CONFIG"
fi
