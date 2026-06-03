#!/bin/sh
# session-state.sh — tests for bin/lib-session-state.sh (v2.23.0 first-edit
# in-progress marking). Validates project-root resolution and the light-touch,
# body-preserving, idempotent SESSION.md write.

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO_ROOT/plugin-claude-code/bin/lib-session-state.sh"

# shellcheck disable=SC1090
. "$LIB"

PASS=0
FAIL=0
ok()   { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad()  { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/aria-ss-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

# --- A: find_root walks up to nearest CLAUDE.md ---
mkdir -p "$TMP/proj/sub/deep"
: > "$TMP/proj/CLAUDE.md"
got=$(kt_ss_find_root "$TMP/proj/sub/deep/file.ts")
[ "$got" = "$TMP/proj" ] && ok "A find_root nearest CLAUDE.md" || bad "A find_root" "got '$got' want '$TMP/proj'"

# --- A2: PROGRESS.md also counts as a root marker; nearest wins ---
mkdir -p "$TMP/proj/sub2"
: > "$TMP/proj/sub2/PROGRESS.md"
got=$(kt_ss_find_root "$TMP/proj/sub2/x.md")
[ "$got" = "$TMP/proj/sub2" ] && ok "A2 find_root nearest PROGRESS.md" || bad "A2 find_root" "got '$got'"

# --- B: no marker anywhere -> empty ---
mkdir -p "$TMP/bare/x"
got=$(kt_ss_find_root "$TMP/bare/x/file.ts")
[ -z "$got" ] && ok "B find_root empty when no marker" || bad "B find_root" "got '$got' want empty"

# --- C: mark_inprogress creates a fresh SESSION.md when absent ---
mkdir -p "$TMP/c"
: > "$TMP/c/CLAUDE.md"
kt_ss_mark_inprogress "$TMP/c" "sess-123" "mipr"
[ -f "$TMP/c/SESSION.md" ] || bad "C create" "no SESSION.md written"
if grep -q '^lastEvent: in-progress$' "$TMP/c/SESSION.md" 2>/dev/null; then ok "C fresh lastEvent in-progress"; else bad "C create" "lastEvent not in-progress"; fi
grep -q '^sessionId: sess-123$' "$TMP/c/SESSION.md" && ok "C sessionId written" || bad "C sessionId" "missing"

# --- D: refresh preserves body + Next session prompt + currentFocus ---
mkdir -p "$TMP/d"
: > "$TMP/d/CLAUDE.md"
cat > "$TMP/d/SESSION.md" <<'SESS'
---
lastEvent: handoff
at: 2026-05-01T00:00:00Z
currentFocus: Tranche-2 access-gate migration
nextAction: ship it
branch: master
headCommit: deadbee
by: mipr
---

## Where we left off

Did the thing.

## Next session prompt

```
ar
resume the thing
```
SESS
kt_ss_mark_inprogress "$TMP/d" "sess-d" "mipr"
grep -q '^lastEvent: in-progress$' "$TMP/d/SESSION.md" && ok "D flipped to in-progress" || bad "D flip" "lastEvent not flipped"
grep -q '^currentFocus: Tranche-2 access-gate migration$' "$TMP/d/SESSION.md" && ok "D preserved currentFocus" || bad "D currentFocus" "lost"
grep -q 'resume the thing' "$TMP/d/SESSION.md" && ok "D preserved Next session prompt" || bad "D body" "Next session prompt lost"
grep -q '## Where we left off' "$TMP/d/SESSION.md" && ok "D preserved body heading" || bad "D body" "body lost"
# 'at' must have changed away from the stale value
if grep -q '^at: 2026-05-01T00:00:00Z$' "$TMP/d/SESSION.md"; then bad "D at-refresh" "at not refreshed"; else ok "D refreshed at"; fi
# exactly one frontmatter block (no duplicate header)
hdr=$(grep -c '^---$' "$TMP/d/SESSION.md")
[ "$hdr" = "2" ] && ok "D single frontmatter block" || bad "D frontmatter" "found $hdr fences, want 2"

# --- E: idempotent — second call doesn't duplicate keys or corrupt ---
kt_ss_mark_inprogress "$TMP/d" "sess-d" "mipr"
le=$(grep -c '^lastEvent:' "$TMP/d/SESSION.md")
[ "$le" = "1" ] && ok "E idempotent (single lastEvent)" || bad "E idempotent" "found $le lastEvent lines"

# --- F: gitignore ensured in a git repo ---
mkdir -p "$TMP/f"
: > "$TMP/f/CLAUDE.md"
( cd "$TMP/f" && git init -q && git config user.email t@t && git config user.name t ) 2>/dev/null
kt_ss_mark_inprogress "$TMP/f" "sess-f" "mipr"
if [ -f "$TMP/f/.gitignore" ] && grep -q '^SESSION.md$' "$TMP/f/.gitignore"; then ok "F SESSION.md gitignored"; else bad "F gitignore" "not added"; fi

# --- G: find_root rejects the projects container (direct child of $HOME) ---
# Bug B regression: the projects root (e.g. ~/Projects) has a master CLAUDE.md;
# it must NOT be treated as a project. A file directly under it resolves to empty;
# a file in a real sub-project resolves to that sub-project.
mkdir -p "$TMP/home/Projects/proj/src"
: > "$TMP/home/Projects/CLAUDE.md"          # master index at the container
: > "$TMP/home/Projects/proj/CLAUDE.md"     # a real project inside it
got=$(HOME="$TMP/home" kt_ss_find_root "$TMP/home/Projects/loose-file.ts")
[ -z "$got" ] && ok "G container rejected (file directly under projects root)" || bad "G container-reject" "got '$got' want empty"
got=$(HOME="$TMP/home" kt_ss_find_root "$TMP/home/Projects/proj/src/app.ts")
[ "$got" = "$TMP/home/Projects/proj" ] && ok "G real sub-project still resolves" || bad "G sub-project" "got '$got' want '$TMP/home/Projects/proj'"

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
