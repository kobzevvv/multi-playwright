#!/bin/bash
# ============================================================================
# Project-Aware Playwright MCP Launcher (v2)
# ============================================================================
#
# Launches Chrome OURSELVES with the correct debugging port, then connects
# Playwright MCP via --cdp-endpoint. This ensures Chrome always listens on
# our port, not a random one chosen by @playwright/mcp.
#
# Why: @playwright/mcp appends its own --remote-debugging-port=RANDOM after
# our flag. Chromium takes the last value → Chrome ends up on a random port.
# By launching Chrome independently, we guarantee the port is correct.
#
# Flow:
#   CDP alive on PORT? → connect via --cdp-endpoint
#   Chrome on WRONG port (old script)? → kill, relaunch on correct port
#   No Chrome? → launch Chrome (nohup &), wait for CDP, connect
#
# Chrome lives independently of MCP. Session ends → MCP dies → Chrome stays.
# New session → finds Chrome on port → connects instantly.
# ============================================================================

CONFIG="$HOME/.claude/chrome-profiles.json"
PID_DIR="$HOME/.claude/chrome-pids"
CHROME_BIN="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
LOG_DIR="$HOME/.claude/chrome-logs"

# Playwright-compatible automation flags (extracted from @playwright/mcp)
CHROME_FLAGS=(
  --disable-field-trial-config
  --disable-background-networking
  --disable-background-timer-throttling
  --disable-backgrounding-occluded-windows
  --disable-back-forward-cache
  --disable-breakpad
  --disable-client-side-phishing-detection
  --disable-component-extensions-with-background-pages
  --disable-component-update
  --no-default-browser-check
  --disable-default-apps
  --disable-dev-shm-usage
  --disable-features=AvoidUnnecessaryBeforeUnloadCheckSync,BoundaryEventDispatchTracksNodeRemoval,DestroyProfileOnBrowserClose,DialMediaRouteProvider,GlobalMediaControls,HttpsUpgrades,LensOverlay,MediaRouter,PaintHolding,ThirdPartyStoragePartitioning,Translate,AutoDeElevate,RenderDocument,OptimizationHints,AutomationControlled
  --enable-features=CDPScreenshotNewSurface
  --allow-pre-commit-input
  --disable-hang-monitor
  --disable-ipc-flooding-protection
  --disable-popup-blocking
  --disable-prompt-on-repost
  --disable-renderer-backgrounding
  --force-color-profile=srgb
  --metrics-recording-only
  --no-first-run
  --password-store=basic
  --use-mock-keychain
  --no-service-autorun
  --export-tagged-pdf
  --disable-search-engine-choice-screen
  --unsafely-disable-devtools-self-xss-warnings
  --disable-infobars
  --disable-sync
)

# --- Determine project ---
PROJECT="${1:-${CHROME_PROJECT:-}}"
if [ -z "$PROJECT" ]; then
  PROJECT=$(python3 -c "import json; print(json.load(open('$CONFIG'))['default'])" 2>/dev/null || echo "default")
fi

# --- Read profile config ---
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
  echo "[launcher] ERROR: Unknown project '$PROJECT'" >&2
  echo "[launcher] Available: $(python3 -c "import json; print(', '.join(json.load(open('$CONFIG'))['profiles'].keys()))" 2>/dev/null)" >&2
  exit 1
fi

PORT=$(echo "$CONFIG_OUTPUT" | sed -n '1p')
USER_DATA_DIR=$(echo "$CONFIG_OUTPUT" | sed -n '2p')

echo "[launcher] Project: $PROJECT | Port: $PORT | Dir: $USER_DATA_DIR" >&2

mkdir -p "$PID_DIR" "$LOG_DIR"

# --- Helper: check if CDP is alive on our port ---
check_cdp() {
  curl -s --max-time 2 "http://localhost:$PORT/json/version" 2>/dev/null
}

# --- Helper: find Chrome PID using our user-data-dir ---
find_chrome_pid() {
  pgrep -f "Google Chrome.*--user-data-dir=$USER_DATA_DIR" 2>/dev/null | head -1
}

# --- Helper: remove SingletonLock if Chrome crashed ---
cleanup_singleton_lock() {
  local lock_file="$USER_DATA_DIR/SingletonLock"
  if [ -L "$lock_file" ] || [ -f "$lock_file" ]; then
    # Check if the PID in the lock is actually running
    local lock_target
    lock_target=$(readlink "$lock_file" 2>/dev/null)
    if [ -n "$lock_target" ]; then
      local lock_pid
      lock_pid=$(echo "$lock_target" | cut -d'-' -f1)
      if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
        echo "[launcher] Removing stale SingletonLock (PID $lock_pid is dead)" >&2
        rm -f "$lock_file"
      fi
    fi
  fi
}

# --- Helper: launch Chrome as a background process ---
launch_chrome() {
  mkdir -p "$USER_DATA_DIR"
  cleanup_singleton_lock

  echo "[launcher] Launching Chrome on port $PORT..." >&2

  nohup "$CHROME_BIN" \
    "${CHROME_FLAGS[@]}" \
    --remote-debugging-port="$PORT" \
    --user-data-dir="$USER_DATA_DIR" \
    about:blank \
    > "$LOG_DIR/$PROJECT.log" 2>&1 &

  local chrome_pid=$!
  echo "$chrome_pid" > "$PID_DIR/$PROJECT.pid"
  echo "[launcher] Chrome PID: $chrome_pid" >&2

  # Wait for CDP to become available (up to 10 seconds)
  local attempts=0
  local max_attempts=20
  while [ $attempts -lt $max_attempts ]; do
    if check_cdp > /dev/null; then
      echo "[launcher] CDP ready on port $PORT" >&2
      return 0
    fi
    # Check Chrome is still alive
    if ! kill -0 "$chrome_pid" 2>/dev/null; then
      echo "[launcher] ERROR: Chrome exited prematurely. Log:" >&2
      tail -5 "$LOG_DIR/$PROJECT.log" >&2
      return 1
    fi
    sleep 0.5
    attempts=$((attempts + 1))
  done

  echo "[launcher] ERROR: CDP did not become ready in 10s" >&2
  return 1
}

# --- Helper: kill Chrome process for this profile ---
kill_chrome() {
  local pid="$1"
  local reason="$2"
  echo "[launcher] Killing Chrome PID $pid ($reason)" >&2
  kill "$pid" 2>/dev/null
  # Wait for it to exit
  local wait=0
  while kill -0 "$pid" 2>/dev/null && [ $wait -lt 10 ]; do
    sleep 0.5
    wait=$((wait + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    echo "[launcher] Force-killing Chrome PID $pid" >&2
    kill -9 "$pid" 2>/dev/null
  fi
  rm -f "$PID_DIR/$PROJECT.pid"
}

# --- Cleanup old temp configs from previous script version ---
rm -f /tmp/playwright-chrome-*.json 2>/dev/null

# ============================================================================
# Main logic
# ============================================================================

CDP_RESPONSE=$(check_cdp)

if [ -n "$CDP_RESPONSE" ]; then
  # CDP is alive on our port — just connect
  echo "[launcher] Chrome already running on port $PORT, connecting via CDP" >&2
  exec npx @playwright/mcp@latest --cdp-endpoint "http://localhost:$PORT"
fi

# CDP not on our port. Is Chrome running with our data dir on a wrong port?
EXISTING_PID=$(find_chrome_pid)

if [ -n "$EXISTING_PID" ]; then
  # Chrome is running but not on our port — old script or Playwright override
  echo "[launcher] Found Chrome (PID $EXISTING_PID) with our data dir but CDP not on port $PORT" >&2

  # Check if this Chrome is on a different port (the bug scenario)
  WRONG_PORT=$(ps -p "$EXISTING_PID" -o args= 2>/dev/null | grep -oE 'remote-debugging-port=[0-9]+' | tail -1 | cut -d= -f2)
  if [ -n "$WRONG_PORT" ] && [ "$WRONG_PORT" != "$PORT" ]; then
    echo "[launcher] Chrome is on wrong port $WRONG_PORT (expected $PORT)" >&2
  fi

  kill_chrome "$EXISTING_PID" "wrong port or unresponsive"
fi

# Also check stale PID file
if [ -f "$PID_DIR/$PROJECT.pid" ]; then
  STALE_PID=$(cat "$PID_DIR/$PROJECT.pid")
  if [ -n "$STALE_PID" ] && ! kill -0 "$STALE_PID" 2>/dev/null; then
    echo "[launcher] Removing stale PID file (PID $STALE_PID is dead)" >&2
    rm -f "$PID_DIR/$PROJECT.pid"
  fi
fi

# Launch Chrome ourselves
if ! launch_chrome; then
  echo "[launcher] Failed to launch Chrome, exiting" >&2
  exit 1
fi

# Connect Playwright MCP to our Chrome
exec npx @playwright/mcp@latest --cdp-endpoint "http://localhost:$PORT"
