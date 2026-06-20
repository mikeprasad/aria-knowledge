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

# --- H: SESSION.md contract conformance against vendored fixtures ---
# The canonical contract fixtures are OWNED by aria-atlas (the consumer) and
# vendored here verbatim (tests/fixtures/session-contract-vendored/). This pins
# the producer (lib-session-state.sh) to the contract: the header keys it emits
# must all be declared by the canonical in-progress fixture, the three lifecycle
# lastEvent values must match the fixtures' enum, and the body heading must match.
# (A byte-diff is intentionally too strict — bodies differ by content; the
# contract is header keys + state enum + heading names.)
VEND="$REPO_ROOT/tests/fixtures/session-contract-vendored"
hdr_keys() { awk 'NR>1 && /^---$/{exit} /^[A-Za-z][A-Za-z]*:/{sub(/:.*/,""); print}' "$1" | sort -u; }

if [ -d "$VEND" ] && [ -f "$VEND/in-progress.SESSION.md" ]; then
  # H1: every header key the producer emits is declared by the in-progress fixture.
  mkdir -p "$TMP/h"
  : > "$TMP/h/CLAUDE.md"
  ( cd "$TMP/h" && git init -q && git config user.email t@t && git config user.name t && git commit -q --allow-empty -m init ) 2>/dev/null
  kt_ss_mark_inprogress "$TMP/h" "sess-h" "mipr"
  fixture_keys=$(hdr_keys "$VEND/in-progress.SESSION.md")
  missing=""
  for k in $(hdr_keys "$TMP/h/SESSION.md"); do
    printf '%s\n' "$fixture_keys" | grep -qx "$k" || missing="$missing $k"
  done
  [ -z "$missing" ] && ok "H1 producer header keys subset of contract fixture keys" || bad "H1 header-keys" "undeclared:$missing"

  # H2: the three lifecycle lastEvent values == the three the fixtures enumerate.
  enum=$(grep -hE '^lastEvent: (in-progress|wrapup|handoff)$' "$VEND"/*.SESSION.md | sed 's/^lastEvent: //' | sort -u | tr '\n' ' ')
  [ "$enum" = "handoff in-progress wrapup " ] && ok "H2 lifecycle enum matches fixtures (in-progress/wrapup/handoff)" || bad "H2 enum" "got '$enum'"

  # H3: the body heading the producer writes is part of the contract fixture shape.
  grep -q '## Where we left off' "$TMP/h/SESSION.md" && grep -q '## Where we left off' "$VEND/in-progress.SESSION.md" \
    && ok "H3 body heading matches contract" || bad "H3 heading" "'## Where we left off' mismatch"
else
  bad "H vendored-fixtures" "missing $VEND/in-progress.SESSION.md"
fi

# --- I: find_root skips a workspace-index root (marker) and finds the nearer child ---
# I1: sentinel-file marker. ws/ has CLAUDE.md + .aria-workspace-root; ws/child/ is the real root.
mkdir -p "$TMP/wsfile/child/src"
: > "$TMP/wsfile/CLAUDE.md"
: > "$TMP/wsfile/.aria-workspace-root"
: > "$TMP/wsfile/child/CLAUDE.md"
got=$(kt_ss_find_root "$TMP/wsfile/child/src/app.ts")
[ "$got" = "$TMP/wsfile/child" ] && ok "I1 sentinel-marked workspace skipped; child wins" || bad "I1 sentinel" "got '$got'"

# I2: CLAUDE.md line marker (no sentinel file).
mkdir -p "$TMP/wsline/child/src"
printf 'aria_workspace_root: true\n' > "$TMP/wsline/CLAUDE.md"
: > "$TMP/wsline/child/CLAUDE.md"
got=$(kt_ss_find_root "$TMP/wsline/child/src/app.ts")
[ "$got" = "$TMP/wsline/child" ] && ok "I2 line-marked workspace skipped; child wins" || bad "I2 line" "got '$got'"

# I3: a marked root with NO deeper real root -> empty (don't write SESSION.md in a workspace index).
mkdir -p "$TMP/wsonly/loose"
: > "$TMP/wsonly/CLAUDE.md"
: > "$TMP/wsonly/.aria-workspace-root"
got=$(kt_ss_find_root "$TMP/wsonly/loose/x.ts")
[ -z "$got" ] && ok "I3 marked-only container -> empty" || bad "I3 marked-only" "got '$got'"

# --- J: ## Prior sessions ledger add / mark-consumed / prune ---
mkdir -p "$TMP/j"
cat > "$TMP/j/SESSION.md" <<'EOF'
---
lastEvent: handoff
at: 2026-06-20T10:00:00Z
sessionId: sess-active
---

## Next session prompt
```
do the thing
```
EOF

# J1: add prepends a ### block under a created ## Prior sessions heading.
kt_ss_ledger_add "$TMP/j" "sess-old1" "2026-06-19T09:00:00Z" "old focus 1" "old next 1" "old prompt 1"
grep -q '^## Prior sessions$' "$TMP/j/SESSION.md" && ok "J1 heading created" || bad "J1 heading" "no ## Prior sessions"
grep -q '^### sess-old1 · 2026-06-19T09:00:00Z · handoff · unconsumed$' "$TMP/j/SESSION.md" && ok "J1 block added" || bad "J1 block" "no sess-old1 block"

# J2: a second add prepends newest-first (sess-old2 appears before sess-old1).
kt_ss_ledger_add "$TMP/j" "sess-old2" "2026-06-20T08:00:00Z" "old focus 2" "old next 2" "old prompt 2"
order=$(grep -n '^### ' "$TMP/j/SESSION.md" | head -2 | sed 's/:.*sess-/sess-/')
printf '%s\n' "$order" | head -1 | grep -q 'sess-old2' && ok "J2 newest-first" || bad "J2 order" "got '$order'"

# J3: mark_consumed flips the token for the named session only.
kt_ss_ledger_mark_consumed "$TMP/j" "sess-old1" "2026-06-20T09:30:00Z" "sess-active"
grep -q '^### sess-old1 · .* · handoff · consumed 2026-06-20T09:30:00Z by sess-active$' "$TMP/j/SESSION.md" && ok "J3 consumed stamped" || bad "J3 consumed" "old1 not consumed"
grep -q '^### sess-old2 · .* · unconsumed$' "$TMP/j/SESSION.md" && ok "J3 other untouched" || bad "J3 untouched" "old2 changed"

# J4: prune drops consumed blocks, keeps unconsumed.
kt_ss_ledger_prune "$TMP/j"
grep -q 'sess-old1' "$TMP/j/SESSION.md" && bad "J4 prune" "consumed sess-old1 survived" || ok "J4 consumed pruned"
grep -q '^### sess-old2 · .* · unconsumed$' "$TMP/j/SESSION.md" && ok "J4 unconsumed kept" || bad "J4 keep" "old2 lost"

# J5: the active header + Next session prompt are untouched by all ledger ops.
grep -q '^sessionId: sess-active$' "$TMP/j/SESSION.md" && grep -q 'do the thing' "$TMP/j/SESSION.md" && ok "J5 active slot intact" || bad "J5 active" "header/prompt disturbed"

# --- K: read_active_sid + first-edit consumes a prior handoff's ledger block ---
mkdir -p "$TMP/k"
cat > "$TMP/k/SESSION.md" <<'EOF'
---
lastEvent: handoff
at: 2026-06-19T10:00:00Z
sessionId: sess-prev
---

## Where we left off
prev work

## Prior sessions

### sess-prev · 2026-06-19T10:00:00Z · handoff · unconsumed
- focus: prev focus
- next: prev next
- prompt: prev prompt
EOF

# K1: read_active_sid returns the header sessionId.
got=$(kt_ss_read_active_sid "$TMP/k")
[ "$got" = "sess-prev" ] && ok "K1 read_active_sid" || bad "K1 read_active_sid" "got '$got'"

# K2: simulate the post-edit consume — a new session marks the prior block consumed.
prev_sid=$(kt_ss_read_active_sid "$TMP/k")
prev_event=$(awk -F': ' '/^lastEvent:/{print $2; exit}' "$TMP/k/SESSION.md")
if [ "$prev_event" = "handoff" ] && [ "$prev_sid" != "sess-new" ]; then
  kt_ss_ledger_mark_consumed "$TMP/k" "$prev_sid" "2026-06-20T09:00:00Z" "sess-new"
fi
grep -q '^### sess-prev · .* · handoff · consumed 2026-06-20T09:00:00Z by sess-new$' "$TMP/k/SESSION.md" && ok "K2 prior consumed on new-session edit" || bad "K2 consume" "prev not consumed"

# --- L: atlas-isolation — ## Prior sessions must not leak into the Next session prompt block ---
# Reimplement atlas's parse boundary (parse-session.ts): block under "## Next session prompt"
# up to the next "## " heading, then strip one optional surrounding fence.
MS="$REPO_ROOT/tests/fixtures/session-contract-vendored/handoff-multi-session.SESSION.md"
if [ -f "$MS" ]; then
  prompt=$(awk '
    /^## Next session prompt[[:space:]]*$/ { grab=1; next }
    grab && /^## / { exit }
    grab { print }
  ' "$MS" | sed '1{/^```/d;}; ${/^```/d;}')
  printf '%s' "$prompt" | grep -q 'ACTIVE-OPENER' && ok "L active opener present in prompt block" || bad "L active" "active opener missing"
  printf '%s' "$prompt" | grep -q 'OLD-OPENER' && bad "L isolation" "prior-session opener leaked into prompt block" || ok "L prior sessions isolated from prompt block"
else
  bad "L fixture" "missing $MS"
fi

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
