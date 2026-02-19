#!/bin/bash
# ============================================================================
# Bind Directory to Chrome Profile
# ============================================================================
#
# Binds the current (or specified) directory to a Chrome profile.
# After binding, Claude Code sessions from this directory will use
# that profile's Chrome automatically.
#
# Usage:
#   bind-directory.sh <profile-name> [directory]
#
# Examples:
#   cd ~/my-project && bind-directory.sh skillset        # bind current dir
#   bind-directory.sh skillset ~/my-project              # bind specific dir
#
# Available profiles are listed in ~/.claude/chrome-profiles.json
# To create a new profile, use add-profile.sh
# ============================================================================

set -e

CONFIG="$HOME/.claude/chrome-profiles.json"
LAUNCHER="$HOME/.claude/scripts/playwright-project.sh"

NAME="${1:?Usage: bind-directory.sh <profile-name> [directory]}"
DIR="${2:-.}"

# Validate profile exists
if ! python3 -c "import json; c=json.load(open('$CONFIG')); assert '$NAME' in c['profiles']" 2>/dev/null; then
  echo "Error: profile '$NAME' not found." >&2
  echo "" >&2
  echo "Available profiles:" >&2
  python3 -c "
import json
c = json.load(open('$CONFIG'))
for name, p in c['profiles'].items():
    acc = p.get('account') or 'clean browser'
    print(f'  {name:15s} port {p[\"port\"]}  ({acc})')
" 2>/dev/null >&2
  echo "" >&2
  echo "Create a new profile: add-profile.sh <name> [account]" >&2
  exit 1
fi

# Resolve directory
ABS_DIR=$(cd "$DIR" 2>/dev/null && pwd)
if [ -z "$ABS_DIR" ]; then
  echo "Error: directory '$DIR' not found" >&2
  exit 1
fi

# Register
cd "$ABS_DIR"
claude mcp add -s local playwright -- "$LAUNCHER" "$NAME" 2>&1
echo ""
echo "Bound: $ABS_DIR → $NAME"
echo ""
echo "Now start Claude Code from this directory:"
echo "  cd $ABS_DIR && claude"
