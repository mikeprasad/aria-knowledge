#!/bin/sh
# build.sh — assemble plugin-antigravity from canonical plugin/ source.
# Run after any plugin/ update to propagate canonical changes.
#
# Usage: bash plugin-antigravity/build.sh
# Safe to re-run.
#
# What this script adapts:
#   1. KT_CONFIG default path:   ~/.claude/aria-knowledge.local.md
#                              → ~/.gemini/antigravity/aria-knowledge.local.md
#   2. mkdir paths inside scripts: $HOME/.claude → $HOME/.gemini/antigravity
#   3. SKILL.md path references (7 substitutions, in order):
#        ~/.claude/aria-knowledge.local.md  → ~/.gemini/antigravity/aria-knowledge.local.md
#        ~/.claude/projects/                → ~/.gemini/antigravity/transcripts/
#        ~/.claude/active-batch.json        → ~/.gemini/antigravity/active-batch.json
#        ~/.claude/projects                 → ~/.gemini/antigravity/transcripts   (no-slash)
#        ~/.claude/plugins                  → ~/.gemini/config/plugins
#        ~/.claude/plans/                   → ~/.gemini/antigravity/plans/
#        ~/.claude/                         → ~/.gemini/antigravity/   (catch-all, last)
#   4. ADR-094 runtime-gate prose: stripped from skill descriptions via:
#        \*\*Bare-slash canonical \(Claude Code\)\.\*\*.*RUNTIME GATE:.*\(ADR-094 §Part 3[^)]*\)\.[[:space:]]+
#
# What this script does NOT touch (hand-authored, durable across rebuilds):
#   - plugin.json                  (marker file, never changes)
#   - hooks.json                   (5 named hook entries)
#   - mcp_config.json              (12 servers, manual updates)
#   - GEMINI.md                    (session-lifecycle content)
#   - bin/antigravity/             (5 wrappers + 1 lib + tests)
#   - workflows/                   (10 thin-shim workflows for slash-command invocation)
#   - rules/                       (plugin-bundled rules for Always-On activation)
#   - overlays/skills/             (port-specific skill bodies applied after canonical copy)
#   - PORTING.md, README.md, SMOKE-TEST.md

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="$REPO/plugin"
DST="$SCRIPT_DIR"

# --- version.txt sidecar (synced from canonical plugin manifest) ---
# Antigravity's plugin.json schema is marker-only per docs/plugins (just {"name": "..."}).
# /setup needs the version, so we ship it as a sidecar file and sync it here.
CANONICAL_VERSION=$(grep '"version"' "$SRC/.claude-plugin/plugin.json" | head -1 | sed 's/.*"version": *"\([^"]*\)".*/\1/')
if [ -n "$CANONICAL_VERSION" ]; then
  echo "$CANONICAL_VERSION" > "$DST/version.txt"
fi

echo "[aria-knowledge] Building Antigravity port (flat layout) ..."
echo "  Source: $SRC"
echo "  Dest:   $DST"

# --- skills/ (copy + path-substitute + strip ADR-094 prose) ---
rm -rf "$DST/skills" 2>/dev/null || true
cp -R "$SRC/skills" "$DST/skills"

# 7 path substitutions, more-specific first then catch-all
find "$DST/skills" -name 'SKILL.md' -exec sed -i.bak \
  -e 's|~/\.claude/aria-knowledge\.local\.md|~/.gemini/antigravity/aria-knowledge.local.md|g' \
  -e 's|~/\.claude/projects/|~/.gemini/antigravity/transcripts/|g' \
  -e 's|~/\.claude/active-batch\.json|~/.gemini/antigravity/active-batch.json|g' \
  -e 's|~/\.claude/projects|~/.gemini/antigravity/transcripts|g' \
  -e 's|~/\.claude/plugins|~/.gemini/config/plugins|g' \
  -e 's|~/\.claude/plans/|~/.gemini/antigravity/plans/|g' \
  -e 's|~/\.claude/|~/.gemini/antigravity/|g' \
  {} +
find "$DST/skills" -name 'SKILL.md.bak' -delete

# Strip ADR-094 runtime-gate prose from skill descriptions (BSD-sed compatible)
find "$DST/skills" -name 'SKILL.md' -exec sed -i.bak -E \
  's|\*\*Bare-slash canonical \(Claude Code\)\.\*\*.*RUNTIME GATE:.*\(ADR-094 §Part 3[^)]*\)\.[[:space:]]+||g' \
  {} +
find "$DST/skills" -name 'SKILL.md.bak' -delete

# Strip allowed-tools + argument-hint from SKILL.md frontmatter (not in
# Antigravity's documented schema per docs/skills; recognized fields are
# name + description only).
find "$DST/skills" -name 'SKILL.md' -exec sed -i.bak \
  -e '/^allowed-tools:/d' \
  -e '/^argument-hint:/d' \
  {} +
find "$DST/skills" -name 'SKILL.md.bak' -delete

# Patch setup/SKILL.md to read version from version.txt sidecar
# (Antigravity plugin.json schema has no version field per docs/plugins).
if [ -f "$DST/skills/setup/SKILL.md" ]; then
  sed -i.bak \
    -e 's|\${CLAUDE_PLUGIN_ROOT}/\.claude-plugin/plugin\.json|${CLAUDE_PLUGIN_ROOT}/version.txt|g' \
    "$DST/skills/setup/SKILL.md"
  # Replace the grep+sed bash subshell with a simple cat
  sed -i.bak -E \
    's|^INSTALLED_VERSION=\$\(grep .*version\.txt.* head -1 .* sed .*\)$|INSTALLED_VERSION=$(cat "${CLAUDE_PLUGIN_ROOT}/version.txt")|' \
    "$DST/skills/setup/SKILL.md"
  rm -f "$DST/skills/setup/SKILL.md.bak"
fi

# --- Apply port-specific skill overlays ---
# Overlays at plugin-antigravity/overlays/skills/<name>/SKILL.md replace the
# canonical-derived version for skills whose behavioral logic doesn't fit
# Antigravity (e.g., scan Claude Code-specific filesystem layouts). The
# canonical 27 other skills work fine via path-substitution alone; only these
# need port-specific bodies. Overlays run LAST so they override path
# substitutions + frontmatter strip + setup patch (when applicable).
# Drift detection: diff plugin/skills/<name>/SKILL.md
#                      plugin-antigravity/overlays/skills/<name>/SKILL.md
if [ -d "$DST/overlays/skills" ]; then
  overlay_count=0
  for overlay in "$DST/overlays/skills"/*/SKILL.md; do
    [ -f "$overlay" ] || continue
    skill_name=$(basename "$(dirname "$overlay")")
    if [ -d "$DST/skills/$skill_name" ]; then
      cp "$overlay" "$DST/skills/$skill_name/SKILL.md"
      overlay_count=$((overlay_count + 1))
    fi
  done
  if [ "$overlay_count" -gt 0 ]; then
    echo "  Applied $overlay_count port-specific skill overlay(s)."
  fi
fi

echo "  Copied $(find "$DST/skills" -maxdepth 1 -type d | wc -l | tr -d ' ') skill directories."

# --- template/ (knowledge folder scaffold) ---
rm -rf "$DST/template" 2>/dev/null || true
cp -R "$SRC/template" "$DST/template"

find "$DST/template" -name '*.md' -exec sed -i.bak \
  -e 's|~/\.claude/aria-knowledge\.local\.md|~/.gemini/antigravity/aria-knowledge.local.md|g' \
  -e 's|~/\.claude/projects/|~/.gemini/antigravity/transcripts/|g' \
  -e 's|~/\.claude/active-batch\.json|~/.gemini/antigravity/active-batch.json|g' \
  -e 's|~/\.claude/projects|~/.gemini/antigravity/transcripts|g' \
  -e 's|~/\.claude/plugins|~/.gemini/config/plugins|g' \
  -e 's|~/\.claude/plans/|~/.gemini/antigravity/plans/|g' \
  -e 's|~/\.claude/|~/.gemini/antigravity/|g' \
  -e 's|`\.claude/settings\.local\.json`|`hooks.json`|g' \
  {} +
find "$DST/template" -name '*.bak' -delete

echo "  Copied template/."

# --- bin/ canonical scripts (copied + uniform path-substituted) ---
# Skip 4 canonical scripts whose hook events were retired in the Antigravity
# port (see PORTING.md "Retired hooks"): pre-compact-check.sh, post-compact-
# check.sh (PreCompact/PostCompact → /snapshot skill); session-start-check.sh
# (SessionStart → GEMINI.md); task-context-check.sh (TaskCreated → inline
# context-loading in /distill, /codemap skills).
mkdir -p "$DST/bin"
# Remove stale top-level canonical scripts from prior builds (glob doesn't
# recurse, so bin/antigravity/*.sh wrappers are left untouched).
rm -f "$DST/bin"/*.sh
for f in "$SRC/bin"/*.sh; do
  name=$(basename "$f")
  case "$name" in
    pre-compact-check.sh|post-compact-check.sh|session-start-check.sh|task-context-check.sh)
      echo "  [skip] $name (no Antigravity equivalent event)"
      continue
      ;;
  esac
  cp "$f" "$DST/bin/$name"
  chmod +x "$DST/bin/$name"
done

# Uniform sed pass across every canonical bin script — covers both $HOME/.claude
# (bash form, in code) and ~/.claude (tilde form, in comments). More-specific
# substitutions first, then catch-alls.
find "$DST/bin" -maxdepth 1 -name '*.sh' -exec sed -i.bak \
  -e 's|$HOME/.claude/aria-knowledge.local.md|$HOME/.gemini/antigravity/aria-knowledge.local.md|g' \
  -e 's|$HOME/.claude/active-batch.json|$HOME/.gemini/antigravity/active-batch.json|g' \
  -e 's|$HOME/.claude/projects|$HOME/.gemini/antigravity/transcripts|g' \
  -e 's|$HOME/.claude/plugins|$HOME/.gemini/config/plugins|g' \
  -e 's|$HOME/.claude/plans|$HOME/.gemini/antigravity/plans|g' \
  -e 's|mkdir -p "$HOME/.claude"|mkdir -p "$HOME/.gemini/antigravity"|g' \
  -e 's|$HOME/.claude|$HOME/.gemini/antigravity|g' \
  -e 's|~/\.claude/aria-knowledge\.local\.md|~/.gemini/antigravity/aria-knowledge.local.md|g' \
  -e 's|~/\.claude/active-batch\.json|~/.gemini/antigravity/active-batch.json|g' \
  -e 's|~/\.claude/projects|~/.gemini/antigravity/transcripts|g' \
  -e 's|~/\.claude/plugins|~/.gemini/config/plugins|g' \
  -e 's|~/\.claude/plans|~/.gemini/antigravity/plans|g' \
  -e 's|~/\.claude|~/.gemini/antigravity|g' \
  {} +
find "$DST/bin" -maxdepth 1 -name '*.bak' -delete

# Patch save-transcript.sh to read transcriptPath from cache file (set by
# pre-invocation-aria.sh hook). Antigravity's transcript lives at a single
# known path per workspace, delivered via hook stdin — not in a directory
# of jsonl files like Claude Code's ~/.claude/projects/ layout.
# The canonical discovery block is multi-line (find | stat | sort | head | cut)
# which is fragile to sed-patch after path substitution. We replace the entire
# file body with a heredoc that preserves all non-discovery logic verbatim.
if [ -f "$DST/bin/save-transcript.sh" ]; then
  cat > "$DST/bin/save-transcript.sh" << 'SAVE_TRANSCRIPT_EOF'
#!/bin/sh
# save-transcript.sh — on-demand transcript snapshot for the /snapshot skill.
# Antigravity port: reads transcript path from cache file written by the
# aria-pre-invocation hook (pre-invocation-aria.sh), which captures
# transcriptPath from hook stdin on every model call. The canonical Claude Code
# variant walks ~/.claude/projects/ for the most-recently-modified *.jsonl —
# that directory layout doesn't exist in Antigravity.
# Mirrors the archival logic from the canonical but uses the cached path.
# Bypasses KT_AUTO_CAPTURE — that gate scopes to hook-driven auto capture,
# not explicit user invocation.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

if [ "$KT_CONFIGURED" = "false" ] || [ -n "$KT_CONFIG_ERROR" ]; then
  echo "aria-knowledge is not configured. Run /setup first." >&2
  [ -n "$KT_CONFIG_ERROR" ] && echo "Config error: $KT_CONFIG_ERROR" >&2
  exit 1
fi

if [ ! -d "$KT_KNOWLEDGE_FOLDER" ]; then
  echo "Knowledge folder not found: $KT_KNOWLEDGE_FOLDER" >&2
  exit 1
fi

# Antigravity port: locate transcript via the cache file written by the
# aria-pre-invocation hook on every model call. If the cache doesn't exist,
# the hook hasn't fired yet — user needs to let the agent respond once first.
TRANSCRIPT_CACHE="$HOME/.gemini/antigravity/.last-transcript-path"
if [ ! -f "$TRANSCRIPT_CACHE" ]; then
  echo "Transcript cache not found at $TRANSCRIPT_CACHE" >&2
  echo "The aria-pre-invocation hook writes this file before each model call." >&2
  echo "Let the agent respond to one message first, then re-run /snapshot." >&2
  exit 1
fi

TRANSCRIPT_PATH=$(cat "$TRANSCRIPT_CACHE")
if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  echo "Transcript file not found at ${TRANSCRIPT_PATH:-<empty>} (cache may be stale)" >&2
  echo "Cache: $TRANSCRIPT_CACHE" >&2
  exit 1
fi

# Derive a short identifier from the transcript filename for the snapshot name.
# Antigravity transcript files are typically named transcript.jsonl or include
# a conversation id; fall back to a timestamp if neither yields a clean id.
SESSION_ID=$(basename "$TRANSCRIPT_PATH" .jsonl)
SESSION_SHORT=$(printf '%s' "$SESSION_ID" | cut -c1-8)
TODAY=$(date +%Y-%m-%d)

CAPTURES_DIR="$KT_KNOWLEDGE_FOLDER/intake/pre-compact-captures"
mkdir -p "$CAPTURES_DIR" 2>/dev/null

SNAPSHOT_FILE="$CAPTURES_DIR/${TODAY}_${SESSION_SHORT}.md"

if ! cp "$TRANSCRIPT_PATH" "$SNAPSHOT_FILE" 2>/dev/null; then
  echo "Failed to write snapshot to $SNAPSHOT_FILE" >&2
  exit 1
fi

echo "Transcript snapshot saved → $SNAPSHOT_FILE"
echo "Source: $TRANSCRIPT_PATH"
echo "Run /extract now (in-context), or /audit-knowledge will review this snapshot at the next audit cycle."
SAVE_TRANSCRIPT_EOF
  chmod +x "$DST/bin/save-transcript.sh"
  echo "  Patched save-transcript.sh: cache-reading transcript discovery (Antigravity port)."
fi

echo "  Copied + path-substituted $(ls "$DST/bin"/*.sh 2>/dev/null | wc -l | tr -d ' ') canonical bin scripts."

echo ""
echo "[aria-knowledge] Antigravity port build complete."
echo "  Hand-authored files preserved: plugin.json, hooks.json, mcp_config.json, GEMINI.md, bin/antigravity/*, PORTING.md, README.md, SMOKE-TEST.md"
