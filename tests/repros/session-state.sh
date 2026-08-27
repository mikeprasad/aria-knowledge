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

# J1: add prepends a ### block under a created ## Pending handoffs heading. (Renamed from
# '## Prior sessions' — these are still-valid prompts awaiting use, not history. Legacy files
# keep their old heading and still prune; asserted at M7.)
kt_ss_ledger_add "$TMP/j" "sess-old1" "2026-06-19T09:00:00Z" "old focus 1" "old next 1" "old prompt 1"
grep -q '^## Pending handoffs$' "$TMP/j/SESSION.md" && ok "J1 heading created" || bad "J1 heading" "no ## Pending handoffs"
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

# --- M: unconsumed handoffs keep their FULL prompt; prune bounds blocks by an explicit
# terminator instead of inferring from "## ".
#
# A SESSION.md may hold SEVERAL still-valid next-session prompts. Collapsing an unconsumed
# prompt to one line degrades a mandate that has not been used yet, so full fidelity is
# required. That in turn means a stored prompt can contain a column-0 "## " (openers do),
# which the old prune treated as a block boundary -- a consumed block would lose its
# boundary and leak its tail into the file.
MD="$TMP/m"; mkdir -p "$MD"

# M1: a full multi-line prompt survives an add/read round-trip uncollapsed.
cat > "$MD/SESSION.md" <<'MEOF'
---
lastEvent: handoff
sessionId: NEW
---

## Next session prompt

ACTIVE
MEOF
FULL='Resume the arc.
## Read first
- a file
Continue.'
kt_ss_ledger_add "$MD" "OLD-A" "2026-07-30T00:00:00Z" "focus" "next" "$FULL"
grep -q '^## Read first$' "$MD/SESSION.md" \
  && ok "M1 full multi-line prompt stored uncollapsed" || bad "M1 fidelity" "prompt was collapsed or dropped"
grep -q 'Continue\.' "$MD/SESSION.md" \
  && ok "M1 prompt tail preserved" || bad "M1 tail" "prompt truncated"

# M2: every stored block carries an explicit terminator.
grep -q '^<!-- aria:entry-end -->$' "$MD/SESSION.md" \
  && ok "M2 block terminator written" || bad "M2 terminator" "no explicit block terminator"

# M3: THE LEAK. A consumed block whose prompt contains a column-0 "## " must be removed
# whole -- no residue. This is the assertion that goes RED against boundary-inference.
kt_ss_ledger_mark_consumed "$MD" "OLD-A" "2026-07-30T01:00:00Z" "tester"
kt_ss_ledger_prune "$MD"
if grep -q 'Continue\.' "$MD/SESSION.md" || grep -q '^## Read first$' "$MD/SESSION.md"; then
  bad "M3 prune leak" "consumed block left residue behind (boundary inference failed)"
else
  ok "M3 consumed block pruned whole, no residue"
fi
grep -q 'ACTIVE' "$MD/SESSION.md" \
  && ok "M3 active prompt untouched by prune" || bad "M3 active" "prune ate the active prompt"

# M4: an UNCONSUMED full-prompt block survives prune untouched.
kt_ss_ledger_add "$MD" "OLD-B" "2026-07-30T02:00:00Z" "focus" "next" "$FULL"
kt_ss_ledger_prune "$MD"
grep -q 'OLD-B' "$MD/SESSION.md" \
  && ok "M4 unconsumed block survives prune" || bad "M4 unconsumed" "prune dropped an unconsumed handoff"
grep -q '^## Read first$' "$MD/SESSION.md" \
  && ok "M4 unconsumed keeps full fidelity through prune" || bad "M4 fidelity" "prompt degraded"

# M5: the section is named for what it holds -- pending work, not history.
grep -q '^## Pending handoffs$' "$MD/SESSION.md" \
  && ok "M5 section named '## Pending handoffs'" || bad "M5 heading" "not using the pending heading"

# M6: atlas isolation still holds -- the pending section must sit AFTER the prompt block so
# the atlas parser (which stops at the first "## " after the prompt) never sees it.
mprompt=$(awk '
  /^## Next session prompt[[:space:]]*$/ { grab=1; next }
  grab && /^## / { exit }
  grab { print }
' "$MD/SESSION.md")
printf '%s' "$mprompt" | grep -q 'ACTIVE' \
  && ok "M6 atlas still reads the active prompt" || bad "M6 atlas active" "active prompt not readable"
printf '%s' "$mprompt" | grep -q 'OLD-B' \
  && bad "M6 atlas isolation" "a pending handoff leaked into the atlas prompt block" \
  || ok "M6 pending handoffs isolated from the atlas prompt block"

# M7: legacy '## Prior sessions' files are grandfathered, not orphaned.
LD="$TMP/mlegacy"; mkdir -p "$LD"
cat > "$LD/SESSION.md" <<'LEOF'
---
lastEvent: handoff
---

## Prior sessions

### LEG-1 · 2026-07-01 · handoff · consumed 2026-07-01 by x
- focus: f
- prompt: legacy one-liner
LEOF
kt_ss_ledger_prune "$LD"
grep -q 'LEG-1' "$LD/SESSION.md" \
  && bad "M7 legacy prune" "legacy consumed entry not pruned" || ok "M7 legacy '## Prior sessions' still pruned"

# --- M8: D2 — the matchers must tolerate hand-written header DECORATION -------------------------
# kt_ss_ledger_add writes ONE canonical shape, but humans hand-write entries: measured 2026-08-27,
# 2 of 25 real headers across every SESSION.md on this machine carry a parenthetical after the sid.
# The old matchers accepted only the canonical shape, returned 0 and changed nothing — so the
# fail-safe contract HID the class, and the failed automatic mark is what forces the manual one that
# reintroduces the unmatchable format.
#
# ⛔ ASSERT THE WRITE LANDS, never only that the pattern fired. Measured: with the match loosened but
# the paired sub() left anchored to `· unconsumed$`, bold and trailing-title headers MATCH and are
# never REWRITTEN — the same silent no-op moved one layer in, now reading as "handled".
DD="$TMP/mdec"; mkdir -p "$DD"
cat > "$DD/SESSION.md" <<'DEOF'
---
lastEvent: handoff
---

## Pending handoffs

### `DEC-BT` · 2026-08-01T00:00:00Z · handoff · unconsumed
- prompt: backticked sid
<!-- aria:entry-end -->

### DEC-TT · 2026-08-01T00:00:00Z · handoff · unconsumed · my title
- prompt: trailing title after the status
<!-- aria:entry-end -->

### DEC-BD · 2026-08-01T00:00:00Z · handoff · **unconsumed**
- prompt: bold status
<!-- aria:entry-end -->

### DEC-CANON · 2026-08-01T00:00:00Z · handoff · unconsumed
- prompt: canonical control
<!-- aria:entry-end -->

### DEC-LIVE · 2026-08-01T00:00:00Z · handoff · unconsumed
- prompt: MUST-SURVIVE-PRUNE
<!-- aria:entry-end -->
DEOF
for _f in DEC-BT DEC-TT DEC-BD DEC-CANON; do
  kt_ss_ledger_mark_consumed "$DD" "$_f" "2026-08-02T00:00:00Z" "tester"
done
for _f in DEC-BT DEC-TT DEC-BD; do
  if awk -v s="$_f" '$0 ~ ("^### .*" s) && /consumed/ && !/unconsumed/ { f=1 } END { exit !f }' "$DD/SESSION.md"; then
    ok "M8 $_f: mark_consumed WROTE the status"
  else
    bad "M8 $_f" "header still unconsumed — the match and its paired write must BOTH tolerate decoration"
  fi
done
# canonical control: proves the probe can succeed, so an all-fail run is not read as a bad probe
awk '$0 ~ /^### .*DEC-CANON/ && /consumed/ && !/unconsumed/ { f=1 } END { exit !f }' "$DD/SESSION.md" \
  && ok "M8 canonical control still marks" || bad "M8 canonical" "even the canonical form stopped marking — the probe or the matcher is broken"
kt_ss_ledger_prune "$DD"
if grep -qE 'DEC-BT|DEC-TT|DEC-BD|DEC-CANON' "$DD/SESSION.md"; then
  bad "M8 prune" "a marked-consumed decorated entry survived prune — prune's own status test is still anchored"
else
  ok "M8 all four marked entries pruned"
fi
# THE INVERSION GUARD. A naive /consumed/ also matches `unconsumed`, which would make prune DELETE
# live handoffs — strictly worse than the bug. M4 above is the canonical instance of this check;
# this is its decorated-fixture sibling.
grep -q 'DEC-LIVE' "$DD/SESSION.md" \
  && ok "M8 live unconsumed entry survives prune (inversion guard)" \
  || bad "M8 INVERSION" "prune deleted a live UNCONSUMED handoff — the status test matched 'unconsumed' as 'consumed'"

# ⚠ NAMED RESIDUAL, deliberately NOT asserted as fixed: a header carrying a TRUNCATED sid while the
# caller passes the full one is matched by neither the old nor the new form — measured, the full sid
# is simply not present in the line, so no loosening of the header pattern can reach it. Closing it
# would need prefix matching, which could mark the WRONG entry. Out of scope by design.

# --- M9: D4 — a stored prompt with a column-0 "### " must not hijack the block boundary ----------
# prune's terminator branch reset `drop` on ANY /^### /, so a consumed block whose stored prompt
# contains such a heading lost its boundary and leaked its tail. Same failure the function's own
# comment says it fixed for "## ". The fixture shape is real, not invented: a live SESSION.md in this
# author's busiest project carries exactly these headings in its ACTIVE body today, so this is one
# demote away from live.
ED="$TMP/mhash"; mkdir -p "$ED"
cat > "$ED/SESSION.md" <<'EEOF'
---
lastEvent: handoff
---

## Pending handoffs

### HSH-OLD · 2026-08-01T00:00:00Z · handoff · consumed 2026-08-02 by x
- prompt:
Some prose.

### Findings recorded this session, all committed and pushed

TAIL-MUST-NOT-LEAK
<!-- aria:entry-end -->

### HSH-LIVE · 2026-08-03T00:00:00Z · handoff · unconsumed
- prompt: LIVE-MUST-SURVIVE
<!-- aria:entry-end -->
EEOF
kt_ss_ledger_prune "$ED"
grep -q 'TAIL-MUST-NOT-LEAK' "$ED/SESSION.md" \
  && bad "M9a prune leak" "a column-0 '### ' inside a stored prompt ended the block early and leaked its tail" \
  || ok "M9a consumed block with an inner '### ' removed whole"
grep -q 'LIVE-MUST-SURVIVE' "$ED/SESSION.md" \
  && ok "M9b adjacent live entry survives" || bad "M9b" "prune ate the adjacent live entry"

# ⛔⛔ M9c IS THE CONTROL THAT DECIDES D4's FIX, and without it the WORSE fix passes. Removing the
# `^### ` reset UNCONDITIONALLY closes M9a — and destroys everything after an unterminated consumed
# block, because that reset is the only recovery path when a terminator is missing. Measured: the
# unconditional form reduced this fixture to its bare heading. The shipped form ends a drop only on a
# line that IS an entry header (>=2 " · " separators — 25/25 real headers carry >=3, 3/3 prose
# headings carry 0), which closes M9a AND keeps this recovery.
FD="$TMP/mnoterm"; mkdir -p "$FD"
cat > "$FD/SESSION.md" <<'FEOF'
---
lastEvent: handoff
---

## Pending handoffs

### NT-OLD · 2026-08-01T00:00:00Z · handoff · consumed 2026-08-02 by x
- prompt: consumed body with NO terminator after it

### NT-LIVE · 2026-08-03T00:00:00Z · handoff · unconsumed
- prompt: NOTERM-LIVE-MUST-SURVIVE
<!-- aria:entry-end -->
FEOF
kt_ss_ledger_prune "$FD"
grep -q 'NOTERM-LIVE-MUST-SURVIVE' "$FD/SESSION.md" \
  && ok "M9c unterminated consumed block does not eat the next live entry" \
  || bad "M9c RECOVERY LOST" "an unterminated consumed block swallowed a LIVE handoff — the boundary reset must be discriminated, not removed"

# --- M10: D3 — every status the LIBRARY emits is in the closed set ------------------------------
# Mike's ruling 2026-08-27: closed set at the WRITER. ⛔ NOT implementable as a rejection branch:
# kt_ss_ledger_add embeds the literal `unconsumed` and has no status parameter, so a validating
# branch would be unreachable code. This asserts the invariant BEHAVIOURALLY instead — on the file
# the writers actually emit — so it reds if a third verb is ever introduced.
CD="$TMP/mclosed"; mkdir -p "$CD"
printf -- '---\nlastEvent: handoff\n---\n' > "$CD/SESSION.md"
kt_ss_ledger_add "$CD" "CS-1" "2026-08-01T00:00:00Z" "f" "n" "p"
kt_ss_ledger_add "$CD" "CS-2" "2026-08-02T00:00:00Z" "f" "n" "p"
kt_ss_ledger_mark_consumed "$CD" "CS-2" "2026-08-03T00:00:00Z" "tester"
_ss_offset() {
  awk '/^### / { n = gsub(/ · /, " · "); if (n < 2) next
                 if ($0 ~ /(^|[^a-z])unconsumed([^a-z]|$)/) next
                 if ($0 ~ /(^|[^a-z])consumed([^a-z]|$)/) next
                 print }' "$1"
}
_out=$(_ss_offset "$CD/SESSION.md")
[ -z "$_out" ] \
  && ok "M10 every status the library emits is in {unconsumed, consumed}" \
  || bad "M10 closed set" "library emitted an out-of-set status: $_out"
# DEAD-INSTRUMENT CONTROL: a check that has only ever returned empty is unproven. Inject the exact
# real-world violation (Projects/SESSION.md carried this verb for four weeks) and require a hit.
printf '### CS-3 · 2026-08-04T00:00:00Z · handoff · RETIRED-BY-HAND 2026-08-15\n' >> "$CD/SESSION.md"
[ -n "$(_ss_offset "$CD/SESSION.md")" ] \
  && ok "M10 control: an out-of-set status IS detected" \
  || bad "M10 DEAD INSTRUMENT" "the closed-set check cannot see a violation, so its empty result proved nothing"

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
