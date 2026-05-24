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
#   - hooks.json                   (4 named hook entries)
#   - mcp_config.json              (12 servers, manual updates)
#   - GEMINI.md                    (session-lifecycle content)
#   - bin/antigravity/             (4 wrappers + 1 lib + tests)
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

echo "  Copied + path-substituted $(ls "$DST/bin"/*.sh 2>/dev/null | wc -l | tr -d ' ') canonical bin scripts."

echo ""
echo "[aria-knowledge] Antigravity port build complete."
echo "  Hand-authored files preserved: plugin.json, hooks.json, mcp_config.json, GEMINI.md, bin/antigravity/*, PORTING.md, README.md, SMOKE-TEST.md"
