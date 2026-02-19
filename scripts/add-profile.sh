#!/bin/bash
# ============================================================================
# Add Chrome Profile for Multi-Playwright
# ============================================================================
#
# Creates a new Chrome profile and optionally binds directories to it.
#
# Usage:
#   add-profile.sh <name> [account] [dir1 dir2 ...]
#
# Examples:
#   add-profile.sh myproject                           # new profile, no account
#   add-profile.sh work user@company.com               # new profile with account
#   add-profile.sh work user@company.com ~/projects/a  # profile + bind directory
#   add-profile.sh work user@company.com ~/projects/*  # profile + bind glob
#
# What it does:
#   1. Picks the next free port (9223, 9224, ...)
#   2. Adds profile to ~/.claude/chrome-profiles.json
#   3. Creates ~/.chrome-pw-<name> directory
#   4. Registers playwright MCP in Claude Code for each directory
#   5. First Chrome launch will be a clean browser — log in manually
# ============================================================================

set -e

CONFIG="$HOME/.claude/chrome-profiles.json"
LAUNCHER="$HOME/.claude/scripts/playwright-project.sh"

# --- Parse args ---
NAME="${1:?Usage: add-profile.sh <name> [account] [directories...]}"
ACCOUNT="${2:-}"
shift 2 2>/dev/null || shift $# 2>/dev/null
DIRS=("$@")

# --- Validate name ---
if [[ ! "$NAME" =~ ^[a-z][a-z0-9_-]*$ ]]; then
  echo "Error: profile name must be lowercase alphanumeric (got: $NAME)" >&2
  exit 1
fi

# --- Init config if missing ---
if [ ! -f "$CONFIG" ]; then
  echo '{"default":"'"$NAME"'","profiles":{}}' > "$CONFIG"
  echo "Created $CONFIG"
fi

# --- Check if profile already exists ---
if python3 -c "import json; c=json.load(open('$CONFIG')); exit(0 if '$NAME' in c['profiles'] else 1)" 2>/dev/null; then
  echo "Profile '$NAME' already exists. Binding directories only." >&2
  EXISTING=true
else
  EXISTING=false
fi

# --- Find next free port ---
if [ "$EXISTING" = false ]; then
  NEXT_PORT=$(python3 -c "
import json
c = json.load(open('$CONFIG'))
used = {p['port'] for p in c['profiles'].values()}
port = 9223
while port in used:
    port += 1
print(port)
")

  USER_DATA_DIR="\$HOME/.chrome-pw-$NAME"
  ACCOUNT_JSON="null"
  [ -n "$ACCOUNT" ] && [ "$ACCOUNT" != "clean" ] && ACCOUNT_JSON="\"$ACCOUNT\""

  # Add to chrome-profiles.json
  python3 -c "
import json
c = json.load(open('$CONFIG'))
c['profiles']['$NAME'] = {
    'port': $NEXT_PORT,
    'userDataDir': '~/.chrome-pw-$NAME',
    'account': $ACCOUNT_JSON,
    'note': 'Added by add-profile.sh'
}
json.dump(c, open('$CONFIG', 'w'), indent=2)
print('Added profile: $NAME (port $NEXT_PORT)')
"

  # Create user-data directory
  mkdir -p "$HOME/.chrome-pw-$NAME"
  echo "Created $HOME/.chrome-pw-$NAME"
else
  echo "Profile '$NAME' exists, skipping creation."
fi

# --- Bind directories ---
if [ ${#DIRS[@]} -gt 0 ]; then
  echo ""
  echo "Binding directories to profile '$NAME':"
  for pattern in "${DIRS[@]}"; do
    # Expand globs
    expanded=$(eval echo "$pattern" 2>/dev/null)
    for dir in $expanded; do
      abs_dir=$(cd "$dir" 2>/dev/null && pwd)
      if [ -z "$abs_dir" ]; then
        echo "  SKIP: $dir (not found)"
        continue
      fi
      cd "$abs_dir"
      claude mcp add -s local playwright -- "$LAUNCHER" "$NAME" 2>&1 | head -1
      echo "  OK: $abs_dir → $NAME"
    done
  done
fi

# --- Summary ---
echo ""
echo "Done! Profile '$NAME' is ready."
echo ""
echo "Next steps:"
if [ ${#DIRS[@]} -eq 0 ]; then
  echo "  1. Bind a directory:"
  echo "     cd /path/to/project && claude mcp add -s local playwright -- $LAUNCHER $NAME"
fi
echo "  2. Start Claude Code from the project directory:"
echo "     cd /path/to/project && claude"
echo "  3. First launch: log into Google in the new Chrome window"
echo "     (the browser opens clean — your login will be saved)"
