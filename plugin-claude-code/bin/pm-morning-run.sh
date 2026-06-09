#!/bin/sh
set -eu
# pm-morning-run.sh — launchd entrypoint. Orchestrates collect -> claude(reason) -> notify.
# Code-only (needs Bash + launchd). Config via config.sh + pm_cfg.
BIN="$(cd "$(dirname "$0")" && pwd)"
. "$BIN/config.sh"
. "$BIN/pm-lib.sh"
KT_KNOWLEDGE_FOLDER="${KT_KNOWLEDGE_FOLDER:-}"   # config.sh leaves it unset when unconfigured; keep set -u safe
FACTS="$HOME/.claude/aria-pm-facts.json"
CLAUDE_BIN=$(command -v claude || echo "$HOME/.claude/local/claude")
OUTDIR=$(apm_expand_tilde "$(pm_cfg pm_digest_dir "$KT_KNOWLEDGE_FOLDER/pm-reviews")")
mkdir -p "$OUTDIR"

# 1. deterministic scan (shell side, NOT the LLM)
sh "$BIN/pm-collect.sh" "$FACTS" || true

# 1b. ensure pm-reviews/ is gitignored in the knowledge folder, if it is a repo (PM digests are personal).
if git -C "$KT_KNOWLEDGE_FOLDER" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  _gi="$KT_KNOWLEDGE_FOLDER/.gitignore"
  grep -qxF 'pm-reviews/' "$_gi" 2>/dev/null || printf 'pm-reviews/\n' >> "$_gi"
fi

# 1c. checkpoint-before-write: when light-writes are on, isolate ARIA's upcoming appends by committing
# any dirty, TRACKED IDEAS-BACKLOG.md in each ACTIVE project first (named-path). Also ensure each ACTIVE
# project gitignores PM-REVIEW.md (personal; mirrors SESSION.md). The headless agent has no Bash.
if [ "$(pm_cfg pm_light_writes true)" = "true" ]; then
  jq -r '.projects[]|select(.tier=="ACTIVE").path' "$FACTS" 2>/dev/null | while IFS= read -r p; do
    pp=$(apm_expand_tilde "$p")
    apm_checkpoint_backlog "$pp" || true
    if git -C "$pp" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      grep -qxF 'PM-REVIEW.md' "$pp/.gitignore" 2>/dev/null || printf 'PM-REVIEW.md\n' >> "$pp/.gitignore"
    fi
  done
fi

# 2. LLM reasoning — Read/Edit/Write only (no Bash) so it can't hang on a permission prompt
( cd "$HOME/Projects" && "$CLAUDE_BIN" -p "/aria-assist generate" \
    --allowedTools "Read" "Edit" "Write" ) || true

# 3. notify from the one-line summary the skill wrote
BODY="Morning review ready"
[ -f "$OUTDIR/.last-summary" ] && BODY="$(cat "$OUTDIR/.last-summary")"
sh "$BIN/pm-notify.sh" "Morning review ready" "$BODY" || true

# 4. record last-run status into the .aria-assist.json overlay (best-effort; atlas reads this)
apm_write_assist_status lastRun "$(jq -n \
  --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg r "ok" \
  --arg d "$(date -u +%Y-%m-%d)" --arg s "$(cat "$OUTDIR/.last-summary" 2>/dev/null || echo '')" \
  '{at:$at, result:$r, digest:$d, summary:$s}')" || true

echo "pm-morning-run OK $(date -u +%Y-%m-%dT%H:%M:%SZ)"
