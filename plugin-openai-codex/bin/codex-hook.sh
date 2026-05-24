#!/bin/sh
# Codex hook wrapper for ARIA Knowledge.

set -u

EVENT="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

export ARIA_CODEX_PLUGIN_ROOT="$PLUGIN_ROOT"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"

if [ -z "${KT_CONFIG:-}" ]; then
  if [ -f "$HOME/.codex/aria-knowledge.local.md" ]; then
    export KT_CONFIG="$HOME/.codex/aria-knowledge.local.md"
  else
    export KT_CONFIG="$HOME/.claude/aria-knowledge.local.md"
  fi
fi

python3 "$PLUGIN_ROOT/bin/codex-hook.py" "$EVENT"
