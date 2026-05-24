#!/bin/bash
# migrate-ideas-backlog.sh — Migrate pre-2.11 ideas-backlog.md to per-file intake/ideas/*.md
#
# Usage:
#   bash migrate-ideas-backlog.sh [knowledge_folder]
#
# If no argument is provided, resolves knowledge_folder from ~/.claude/aria-knowledge.local.md.
#
# Behavior:
#   - Reads {knowledge_folder}/intake/ideas-backlog.md
#   - Strips HTML comment blocks (cleared-history markers)
#   - Splits on '^### YYYY-MM-DD — ' headers; emits one file per entry
#   - Generates YAML frontmatter (date, project, type, title) per entry
#   - Handles filename collisions by appending -2, -3, ...
#   - After successful migration, renames the original to ideas-backlog.md.pre-2.11-migration
#     (never deletes — preserves rollback)
#
# Exit codes:
#   0  — migration succeeded (or legacy file did not exist, nothing to do)
#   1  — fatal error (missing config, missing output dir, parser failure)

set -euo pipefail

# Resolve knowledge folder
if [ $# -ge 1 ]; then
  KF="$1"
else
  CONFIG="$HOME/.claude/aria-knowledge.local.md"
  if [ ! -f "$CONFIG" ]; then
    echo "Error: no knowledge folder argument given and $CONFIG not found." >&2
    echo "Usage: bash migrate-ideas-backlog.sh [knowledge_folder]" >&2
    exit 1
  fi
  KF=$(sed -n '/^---$/,/^---$/p' "$CONFIG" | grep '^knowledge_folder:' | sed 's/^knowledge_folder: *//')
  if [ -z "$KF" ]; then
    echo "Error: knowledge_folder not set in $CONFIG" >&2
    exit 1
  fi
fi

# Expand leading ~ if present
case "$KF" in
  "~"*) KF="${HOME}${KF#\~}" ;;
esac

# Resolve input + output
INPUT="$KF/intake/ideas-backlog.md"
OUTPUT_DIR="$KF/intake/ideas"

if [ ! -f "$INPUT" ]; then
  echo "No legacy ideas-backlog.md found at $INPUT — nothing to migrate."
  exit 0
fi

if [ ! -d "$OUTPUT_DIR" ]; then
  echo "Error: output directory $OUTPUT_DIR does not exist." >&2
  echo "Run /setup first to create the v2.11 directory structure." >&2
  exit 1
fi

echo "Migrating:"
echo "  input:  $INPUT"
echo "  output: $OUTPUT_DIR/"
echo ""

# Run the parser (embedded python3)
python3 - "$INPUT" "$OUTPUT_DIR" <<'PYEOF'
import os
import re
import sys
from pathlib import Path

input_path = Path(sys.argv[1])
output_dir = Path(sys.argv[2])

content = input_path.read_text()

# Strip HTML comment blocks (can span multiple lines). These are cleared-history
# audit markers — the same information lives in logs/knowledge-audit-log.md.
content = re.sub(r'<!--.*?-->', '', content, flags=re.DOTALL)

# Split into entries on '^### YYYY-MM-DD — ' headers.
entries = []
current_header = None
current_body = []

for line in content.split('\n'):
    m = re.match(r'^### (\d{4}-\d{2}-\d{2})\s+—\s+(.+)$', line)
    if m:
        if current_header is not None:
            entries.append((current_header, '\n'.join(current_body).strip()))
        current_header = (m.group(1), m.group(2).strip())
        current_body = []
    elif current_header is not None:
        current_body.append(line)

if current_header is not None:
    entries.append((current_header, '\n'.join(current_body).strip()))

if not entries:
    print("No active entries found. Backlog contains only cleared-history comments.")
    sys.exit(0)


def slugify(s, max_len=60):
    """Lowercase, alphanumerics + hyphens only, truncated, no leading/trailing hyphens."""
    s = s.lower()
    s = re.sub(r'[^a-z0-9]+', '-', s)
    s = re.sub(r'-+', '-', s).strip('-')
    return s[:max_len].rstrip('-')


def parse_header(rest):
    """Split 'project — title' (first em-dash only, so titles can contain em-dashes)."""
    if '—' in rest:
        project, title = rest.split('—', 1)
        return project.strip(), title.strip()
    # Fallback — no project attribution
    return 'no-project', rest.strip()


def parse_type(body):
    """Read **Type:** line from body, normalize to single word."""
    m = re.search(r'^\*\*Type:\*\*\s*(\S+)', body, re.MULTILINE)
    if m:
        t = m.group(1).strip().lower()
        # Strip any trailing punctuation (e.g., 'feature,' -> 'feature')
        t = re.sub(r'[^a-z]+$', '', t)
        if t in ('feature', 'bug', 'design', 'refactor', 'workflow'):
            return t
    return 'feature'


written = 0
skipped = 0
for (date, rest), body in entries:
    project, title = parse_header(rest)
    project_slug = slugify(project) or 'no-project'
    title_slug = slugify(title, max_len=60) or 'untitled'
    base = f"{date}-{project_slug}-{title_slug}"

    out_path = output_dir / f"{base}.md"
    n = 2
    while out_path.exists() and n < 100:
        out_path = output_dir / f"{base}-{n}.md"
        n += 1
    if out_path.exists():
        print(f"  Skipping (too many collisions): {base}", file=sys.stderr)
        skipped += 1
        continue

    entry_type = parse_type(body)

    frontmatter = (
        "---\n"
        f"date: {date}\n"
        f"project: {project}\n"
        f"type: {entry_type}\n"
        f"title: {title}\n"
        "---\n\n"
    )
    out_path.write_text(frontmatter + body + '\n')
    print(f"  + {out_path.name}")
    written += 1

print("")
print(f"Wrote {written} file(s) to {output_dir}/")
if skipped:
    print(f"Skipped {skipped} entry(ies) due to collision overflow", file=sys.stderr)
    sys.exit(1)
PYEOF

# Rename original to .pre-2.11-migration (preserve, don't delete)
BACKUP="$INPUT.pre-2.11-migration"
if [ -e "$BACKUP" ]; then
  # Unusual but possible — tag with timestamp to avoid overwrite
  BACKUP="$INPUT.pre-2.11-migration.$(date +%s)"
fi
mv "$INPUT" "$BACKUP"
echo ""
echo "Renamed original: $INPUT → $BACKUP"
echo "Migration complete."
echo ""
echo "Next steps:"
echo "  1. Spot-check a few files in $OUTPUT_DIR/"
echo "  2. Run /audit-knowledge to review the migrated ideas"
echo "  3. Once satisfied, you can delete $BACKUP (git history preserves it regardless)"
