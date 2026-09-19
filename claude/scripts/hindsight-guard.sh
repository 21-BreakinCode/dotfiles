#!/usr/bin/env bash
set -euo pipefail

# Run a Hindsight hook only if cwd matches a mapped bank path.
# Usage: hindsight-guard.sh <hook-script.js>

CONFIG="$HOME/.hindsight/coding-agent.json"
HOOK="${1:-}"

if [[ -z "$HOOK" ]] || [[ ! -f "$CONFIG" ]] || [[ ! -f "$HOOK" ]]; then
  cat >/dev/null 2>&1 || :
  exit 0
fi

if ! command -v jq &>/dev/null; then
  exec node "$HOOK"
fi

CWD="$(pwd)"
MATCH=$(jq -r --arg cwd "$CWD" '
  .mapPathToBank // {} | keys[] | select($cwd | startswith(.))
' "$CONFIG" 2>/dev/null | head -1)

if [[ -n "$MATCH" ]]; then
  exec node "$HOOK"
else
  cat >/dev/null 2>&1 || :
  exit 0
fi
