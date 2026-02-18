#!/bin/bash
# ============================================================================
# Smart Playwright MCP Launcher
# ============================================================================
#
# Automatically selects a free Chrome instance for each AI session.
#
# Session 1 → Chrome A (port 9223, ~/.chrome-playwright)
# Session 2 → Chrome B (port 9224, ~/.chrome-playwright-2)
# Session 3+ → Connects to Chrome B via CDP (shares tabs)
#
# IMPORTANT: MCP communicates via STDIO (JSON-RPC).
# - All diagnostic output → stderr (>&2)
# - exec → hands stdin/stdout directly to the MCP process
# ============================================================================

PORT_A=9223
PORT_B=9224
DIR_A="$HOME/.chrome-playwright"
DIR_B="$HOME/.chrome-playwright-2"
CONFIG_A="$HOME/.claude/configs/playwright-chrome-A.json"
CONFIG_B="$HOME/.claude/configs/playwright-chrome-B.json"

# Fast port check (1 second timeout)
check_port() {
  curl -s --max-time 1 "http://localhost:$1/json/version" > /dev/null 2>&1
}

if ! check_port $PORT_A; then
  # Port A is free → launch Chrome A (primary)
  echo "[playwright-auto] Launching Chrome A on port $PORT_A" >&2
  exec npx @playwright/mcp@latest \
    --browser chrome \
    --user-data-dir "$DIR_A" \
    --config "$CONFIG_A"

elif ! check_port $PORT_B; then
  # Port A busy, port B free → launch Chrome B (secondary)
  echo "[playwright-auto] Port $PORT_A busy. Launching Chrome B on port $PORT_B" >&2
  mkdir -p "$DIR_B"
  exec npx @playwright/mcp@latest \
    --browser chrome \
    --user-data-dir "$DIR_B" \
    --config "$CONFIG_B"

else
  # Both Chrome instances already running → connect to B via CDP
  echo "[playwright-auto] Both ports busy. Connecting to Chrome B via CDP ($PORT_B)" >&2
  exec npx @playwright/mcp@latest \
    --cdp-endpoint "http://localhost:$PORT_B"
fi
