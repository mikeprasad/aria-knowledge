#!/bin/sh
# tests/repros/setup-rules-precondition.sh — /setup Step 7ea installs the always-on rules files
# only where a port actually has their writer. The step self-gates with a shell precondition.
#
# Why this exists (2026-10-25): the precondition grepped the manifest for session-start-rules.sh.
# When that script merged into session-start-check.sh, the grep would have answered "skip" on
# Claude Code and /setup would silently have stopped installing the files. Nothing ran the
# precondition, so only a reference census caught it. This runs the command AS SHIPPED, extracted
# from the skill text, so the next rename of the writer fails here instead of in a user's /setup.
set -u
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SKILL="$DIR/plugin-claude-code/skills/setup/SKILL.md"
PASS=0; FAIL=0
ok()  { printf '  PASS  %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL  %s — %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }

# The first ```bash block after the Step 7ea PRECONDITION line.
CMD=$(awk '/^## Step 7ea/{s=1} s&&/PRECONDITION/{p=1} p&&/^```bash/{f=1;next} f&&/^```/{exit} f' "$SKILL")
if [ -n "$CMD" ] && printf '%s' "$CMD" | grep -q 'echo applies'; then ok "control — precondition extracted from the skill"
else bad "control — precondition extracted from the skill" "got: $CMD"; fi

run_for() { CLAUDE_PLUGIN_ROOT="$DIR/$1" sh -c "$CMD" 2>/dev/null; }
check() { got=$(run_for "$1"); if [ "$got" = "$2" ]; then ok "$1 → $2"; else bad "$1 → $2" "got '$got'"; fi; }
check plugin-claude-code      applies
check plugin-antigravity      skip
check plugin-openai-codex     skip
check plugin-cursor-template  skip

printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
