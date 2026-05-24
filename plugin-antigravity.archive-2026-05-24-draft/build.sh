#!/bin/sh
# build.sh — assemble plugin-antigravity from the canonical plugin/ source.
# Run once from the repo root after cloning, or after any plugin/ update.
# Usage:  bash plugin-antigravity/build.sh
# Safe to re-run: all targets are overwritten.
#
# What this script adapts (3 mechanical substitutions, everything else verbatim):
#   1. KT_CONFIG default path:   ~/.claude/aria-knowledge.local.md
#                              → ~/.gemini/antigravity/aria-knowledge.local.md
#   2. Plugin manifest dir:      .claude-plugin/plugin.json
#                              → .agent-plugin/plugin.json  (inside SKILL.md refs)
#   3. mkdir path in config.sh:  $HOME/.claude
#                              → $HOME/.gemini/antigravity
#
# PreCompact and PostCompact hook scripts are intentionally NOT copied to bin/ —
# Antigravity uses a persistent sandbox (no context compaction lifecycle).
# hooks/hooks.json is pre-written and does not reference those scripts.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC="$REPO/plugin"
DST="$SCRIPT_DIR"

echo "[aria-knowledge] Building Antigravity port v2.19.1 ..."
echo "  Source: $SRC"
echo "  Dest:   $DST"

# --- bin/ scripts ---
# All scripts are verbatim EXCEPT config.sh (path change) and the two compaction
# scripts (retired — not copied).
mkdir -p "$DST/bin"
for f in "$SRC/bin"/*.sh; do
  name=$(basename "$f")
  case "$name" in
    pre-compact-check.sh|post-compact-check.sh)
      echo "  [skip] $name (compaction hooks retired in Antigravity port)"
      continue
      ;;
    config.sh)
      # 3 path substitutions — see header above
      sed \
        -e 's|$HOME/.claude/aria-knowledge.local.md|$HOME/.gemini/antigravity/aria-knowledge.local.md|g' \
        -e 's|# config.sh \u2014 shared config reader for aria-knowledge hooks$|# config.sh \u2014 shared config reader for aria-knowledge hooks (Antigravity port)|' \
        -e 's|mkdir -p "$HOME/.claude" 2>/dev/null|mkdir -p "$HOME/.gemini/antigravity" 2>/dev/null|g' \
        "$f" > "$DST/bin/config.sh"
      chmod +x "$DST/bin/config.sh"
      echo "  [adapt] config.sh (3 path substitutions)"
      continue
      ;;
  esac
  cp "$f" "$DST/bin/$name"
  chmod +x "$DST/bin/$name"
done
echo "  Copied $(ls "$DST/bin" | grep -v '.keep' | wc -l | tr -d ' ') bin scripts."

# --- skills/ ---
# All SKILL.md files are verbatim EXCEPT setup (config path reference).
mkdir -p "$DST/skills"
for skill_dir in "$SRC/skills"/*/; do
  skill_name=$(basename "$skill_dir")
  mkdir -p "$DST/skills/$skill_name"
  src_skill="$skill_dir/SKILL.md"
  dst_skill="$DST/skills/$skill_name/SKILL.md"
  case "$skill_name" in
    setup)
      # Two path substitutions in setup SKILL.md:
      #   ~/.claude/aria-knowledge.local.md  →  ~/.gemini/antigravity/aria-knowledge.local.md
      #   .claude-plugin/plugin.json         →  .agent-plugin/plugin.json
      sed \
        -e 's|~/.claude/aria-knowledge.local.md|~/.gemini/antigravity/aria-knowledge.local.md|g' \
        -e 's|\.claude-plugin/plugin.json|.agent-plugin/plugin.json|g' \
        "$src_skill" > "$dst_skill"
      echo "  [adapt] skills/setup/SKILL.md (2 path substitutions)"
      ;;
    *)
      cp "$src_skill" "$dst_skill"
      ;;
  esac
done
echo "  Copied $(ls "$DST/skills" | grep -v '.keep' | wc -l | tr -d ' ') skills."

# --- template/ (verbatim — knowledge folder schema is port-agnostic) ---
rm -rf "$DST/template" 2>/dev/null || true
cp -r "$SRC/template" "$DST/template"
echo "  Copied template/."

# --- shared docs (verbatim) ---
cp "$SRC/CONNECTORS.md" "$DST/CONNECTORS.md"
cp "$SRC/QUICKSTART.md" "$DST/QUICKSTART.md"
cp "$SRC/CONFIG.md"     "$DST/CONFIG.md"
cp "$SRC/LICENSE"       "$DST/LICENSE"
echo "  Copied shared docs."

# --- Cleanup placeholder files created during initial scaffolding ---
rm -f "$DST/bin/.keep" "$DST/skills/.keep" 2>/dev/null || true

echo ""
echo "[aria-knowledge] Build complete."
echo "  Port layout:"
echo "    plugin-antigravity/"
echo "    ├── .agent-plugin/plugin.json    (manifest — pre-written)"
echo "    ├── hooks/hooks.json              (5 hooks — pre-written)"
echo "    ├── .mcp.json                     (12 MCP servers — pre-written)"
echo "    ├── bin/                          ($(ls "$DST/bin" | wc -l | tr -d ' ') hook scripts — built)"
echo "    ├── skills/                       ($(ls "$DST/skills" | wc -l | tr -d ' ') skills — built)"
echo "    ├── template/                     (knowledge folder scaffold — built)"
echo "    ├── PORTING.md                    (port notes — pre-written)"
echo "    └── build.sh                      (this script)"
echo ""
echo "  To install in Antigravity, run /plugin add from your project or globally."
echo "  Then run /setup inside Antigravity to create:"
echo "    ~/.gemini/antigravity/aria-knowledge.local.md"
