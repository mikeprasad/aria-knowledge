#!/bin/sh
# session-state.sh — tests for scripts/lib-session-state.sh (v2.23.0 first-edit
# in-progress marking). Validates project-root resolution and the light-touch,
# body-preserving, idempotent SESSION.md write.

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO_ROOT/plugin-claude-code/scripts/lib-session-state.sh"

# shellcheck disable=SC1090
. "$LIB"

PASS=0
FAIL=0
ok()   { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad()  { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/aria-ss-test.XXXXXX")

# ⛔ KT_SS_RECEIPTS IS REDIRECTED INTO THE SCRATCH DIR. Without it, every kt_ss_ledger_prune call
# below (11 of them) appends to the user's REAL receipts file at ~/.claude/session-ledger-receipts
# — the suite mutating production state, which is the hazard this file's whole fixture discipline
# exists to avoid. Measured 2026-09-14, the day receipts shipped: 20 of the 22 entries in the live
# file were this suite's temp-dir paths; only 2 were real projects.
#
# ⚑ Why it was missed: the sibling checker suite already guards the EQUIVALENT hazard for its
# watermark cache ("--watermark is REDIRECTED to the scratch dir"), but that guard is scoped to the
# WATERMARK. Receipts are a second global-state file, so the existing guard could not cover them —
# guard-scoped-to-the-wrong-unit, where the real unit is "global state this suite writes".
# ⇒ When a helper gains a NEW side effect on global state, census its CALLERS, not just its author.
#
# Harm was bounded (receipts are advisory-only, capped at 500 lines, and keyed by absolute paths
# that cannot collide with a real ledger) — noise and waste, not corruption. Redirected anyway.
export KT_SS_RECEIPTS="$TMP/session-ledger-receipts"
# chmod first: arm AA6 makes a directory read-only, and rm -rf cannot empty one.
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT

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
# NOTE: this fixture deliberately carries NO `sessionId:` line, so it covers the ABSENT -> INSERTED
# case. The sibling case — an EXISTING sessionId being OVERWRITTEN while the body survives — is
# block O. ⛔ Do NOT add a `sessionId:` line here to cover it: that converts D and silently drops the
# absent-case coverage. Two fixtures, two cases.
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

## Pending handoffs

### sess-earlier · 2026-04-30T00:00:00Z · handoff · unconsumed
- prompt:
```
ar
resume the thing
```
<!-- aria:entry-end -->
SESS
# ⛔ The stored prompt sits in PENDING, not in the active slot, on purpose. Until 2026-10-29 it sat in
# `## Next session prompt` and D asserted the flip over it -- i.e. D pinned the defect that the hook
# rewrote a live handoff's identity. A live ACTIVE prompt now leaves the front matter untouched
# (block O); D keeps the refresh + body-passthrough cases, which need an empty active slot.
kt_ss_mark_inprogress "$TMP/d" "sess-d" "mipr"
grep -q '^lastEvent: in-progress$' "$TMP/d/SESSION.md" && ok "D flipped to in-progress" || bad "D flip" "lastEvent not flipped"
grep -q '^currentFocus: Tranche-2 access-gate migration$' "$TMP/d/SESSION.md" && ok "D preserved currentFocus" || bad "D currentFocus" "lost"
grep -q 'resume the thing' "$TMP/d/SESSION.md" && ok "D preserved the stored Pending prompt" || bad "D body" "stored prompt lost"
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
# (2.58.0 Task 2) A stored column-0 "## " line is escaped on write (spec §3), so full fidelity is the
# ESCAPED form, which the reference decoder turns back into "## Read first".
grep -q '^\\## Read first$' "$MD/SESSION.md" \
  && ok "M1 full multi-line prompt stored uncollapsed" || bad "M1 fidelity" "prompt was collapsed or dropped"
grep -q 'Continue\.' "$MD/SESSION.md" \
  && ok "M1 prompt tail preserved" || bad "M1 tail" "prompt truncated"

# M2: every stored block carries an explicit terminator.
grep -q '^<!-- aria:entry-end -->$' "$MD/SESSION.md" \
  && ok "M2 block terminator written" || bad "M2 terminator" "no explicit block terminator"

# M3: THE LEAK. A consumed block whose prompt contains a column-0 "## " must be removed
# whole -- no residue. This is the assertion that goes RED against boundary-inference.
# ⛔ (2.58.0 Task 2 fix round 1) THE CONSUMED ENTRY IS BUILT BY HAND IN THE RAW PRE-2.58.0 FORM. Since the
# write escape, kt_ss_ledger_add stores `\## Read first`, so an add-written fixture holds no raw `## ` and M3
# could no longer fail for its reason (measured by review: dropping the walker's KT_HASTERM exception or
# prune's HT[] reddened M3 at 841ef44 and only block N at 82879e5). Entries written before 2.58.0 keep raw
# bodies on disk, so that prune rule is still load-bearing -- this fixture is that population.
# The residue check matches "Read first" in ANY form.
cat > "$MD/SESSION.md" <<'M3EOF'
---
lastEvent: handoff
sessionId: NEW
---

## Next session prompt

ACTIVE

## Pending handoffs

### OLD-A · 2026-07-30T00:00:00Z · handoff · consumed 2026-07-30T01:00:00Z by tester
- focus: focus
- next: next
- prompt:
Resume the arc.
## Read first
- a file
Continue.
<!-- aria:entry-end -->
M3EOF
grep -q '^## Read first$' "$MD/SESSION.md" \
  && ok "M3 control: the fixture holds the raw pre-2.58.0 column-0 \"## Read first\" before prune" \
  || bad "M3 control" "fixture lacks the raw ## line -- M3 cannot fail for its reason"
kt_ss_ledger_prune "$MD"
if grep -q 'Continue\.' "$MD/SESSION.md" || grep -q 'Read first' "$MD/SESSION.md"; then
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
grep -q '^\\## Read first$' "$MD/SESSION.md" \
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

# --- M9d: an unterminated consumed block must not eat the next SECTION HEADING ----------------
# ⛔ M9c's sibling, and the half that was MISSING. M9c proves an unterminated consumed block does
# not eat the next live ENTRY, because a well-formed entry header ends the drop. Nothing ended it
# at a `## ` SECTION heading, so the heading and everything under it were destroyed — measured
# 2026-09-09 at 16 lines to 9, and this is the class that deleted two unconsumed handoffs from
# proj-a/SESSION.md on 2026-09-04. The fix reinstates the `## ` reset ONLY for a block with no
# terminator of its own; a terminated block keeps declared boundaries, which is what stops this
# from being the old unconditional reset that leaked a prompt`s inner `## ` line.
HD="$TMP/mheading"; mkdir -p "$HD"
cat > "$HD/SESSION.md" <<'FEOF'
---
lastEvent: handoff
---

## Pending handoffs

### HD-OLD · 2026-08-01T00:00:00Z · handoff · consumed 2026-08-02 by x
- prompt: consumed body with NO terminator after it

## Archived sessions — HEADING-MUST-SURVIVE

### HD-LIVE · 2026-08-03T00:00:00Z · handoff · unconsumed
- prompt: ARCHIVED-LIVE-MUST-SURVIVE
<!-- aria:entry-end -->
FEOF
kt_ss_ledger_prune "$HD"
grep -q 'HEADING-MUST-SURVIVE' "$HD/SESSION.md" \
  && ok "M9d unterminated consumed block does not eat the next section heading" \
  || bad "M9d HEADING DESTROYED" "an unterminated consumed block swallowed a section heading and everything under it"

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

# --- N: PORT PARITY for kt_ss_ledger_add (Unit B, T6) ------------------------------------------
# ⛔ NOTHING ELSE COVERS THIS. This suite sources ONLY the canonical port (LIB, near the top), and
# tests/repros/port-drift-check.sh compares VERSION strings — measured 24 version references and
# ZERO content references — so a fix landing in 1 of the 3 carrying ports passes every existing gate.
# kt_ss_ledger_add is edited in three ports at once; without this arm, two of them can silently rot.
#
# ⛔ THE SELF-CHECK IS A CKSUM, NEVER A LINE COUNT, and it strips FULL-LINE comments ONLY. Measured
# 2026-09-08: a naive `s/#.*$//` CORRUPTS the code — it leaves `if grep -q '^` and `elif grep -q '^`
# with unterminated quotes, because the function body contains '^## Pending handoffs$' — while the
# TOTAL LINE COUNT is 33 either way, since it truncates lines rather than deleting them. So a
# count-based self-check reports the broken extractor healthy. A cksum separates them.
#
# ⛔ A MISSING PATH FAILS, it does not skip. A skip-when-absent arm is a gate with no subject.
# ⚠ The port list is written as LITERAL words, not expanded from a variable: an unquoted variable is
# NOT word-split under zsh, which would silently collapse the loop to a single bogus path.
# ⛔ PARITY IS PER FUNCTION, NOT PER FILE. The ports are deliberately comment-divergent (cursor is a
# lighter variant), so byte-equality of the FILE can never be the test — only comment-normalised
# equality of each shared FUNCTION can. And it must be asserted for every function that ships in more
# than one port: kt_ss_ledger_prune drifted for exactly this reason. It missed the 2026-08-27
# is_entry_header fix in the cursor port and nobody knew, because the parity arm covered only
# kt_ss_ledger_add. Measured 2026-09-09: cursor was TWO fixes behind. Adding a shared function here
# without adding it to _SS_PARITY_FNS re-opens that silence.
_ss_fnsum() {
  [ -f "$1" ] || { printf 'MISSING'; return 0; }
  awk -v fn="$2" '$0 ~ ("^" fn "\\(\\)"){f=1} f{print} f&&/^}$/{exit}' "$1" \
    | grep -vE '^[[:space:]]*#' | grep '[^[:space:]]' | cksum | awk '{print $1}'
}
# (2.58.0) demote_active + add_file are the two entry points /handoff and /wrapup now call instead of
# a model-composed kt_ss_ledger_add; consume_active joined because it now delegates its demote to
# demote_active, so it is edited in four ports at once like the rest of this list.
# (final fix wave) the token-file helpers joined: a model reaches locate/consume only through them.
# (2.58.0 Task 0) the six ledger READERS joined; measured identical in all 4 ports at 1260af0.
# (2.58.0 Task 1a) _kt_ss_awk_regions joined: the one region walker every ledger program splices in.
# (2.58.0 Task 2) _kt_ss_entry_block joined: the one entry builder add and add_verified both write with.
_SS_PARITY_FNS="_kt_ss_awk_regions _kt_ss_entry_block kt_ss_ledger_add kt_ss_ledger_prune kt_ss_ledger_demote_active kt_ss_ledger_add_file kt_ss_ledger_consume_active kt_ss_ledger_add_verified _kt_ss_token_from_file kt_ss_ledger_token_locate_file kt_ss_ledger_consume_active_file kt_ss_ledger_mark_consumed kt_ss_ledger_mark_superseded kt_ss_ledger_candidates kt_ss_ledger_token_locate kt_ss_read_live_prompt kt_ss_read_active_token"
_SS_P1="$REPO_ROOT/plugin-claude-code/scripts/lib-session-state.sh"
_SS_P2="$REPO_ROOT/plugin-antigravity/bin/lib-session-state.sh"
_SS_P3="$REPO_ROOT/plugin-cursor-template/scripts/aria/lib-session-state.sh"
_SS_P4="$REPO_ROOT/plugin-openai-codex/bin/lib-session-state.sh"

for _fn in $_SS_PARITY_FNS; do
  _N1=$(_ss_fnsum "$_SS_P1" "$_fn")
  _N2=$(_ss_fnsum "$_SS_P2" "$_fn")
  _N3=$(_ss_fnsum "$_SS_P3" "$_fn")
  _N4=$(_ss_fnsum "$_SS_P4" "$_fn")
  if [ "$_N1" = MISSING ] || [ "$_N2" = MISSING ] || [ "$_N3" = MISSING ] || [ "$_N4" = MISSING ]; then
    bad "N port parity ($_fn)" "a carrying port path is MISSING (cc=$_N1 ag=$_N2 cu=$_N3 cx=$_N4) — a skip-when-absent arm is a gate with no subject"
  elif [ "$_N1" = 4294967295 ]; then
    # (2.58.0 Task 1a) 4294967295 is the cksum of EMPTY input: no function by that name in the
    # canonical port. Four empty extracts compare equal, so without this a misspelt or fused name in
    # _SS_PARITY_FNS reads as parity -- measured: a dropped space fused add+prune into one name and
    # both left the parity set with every N arm still green.
    bad "N port parity ($_fn)" "$_fn extracts EMPTY from the canonical port — not a function name there"
  elif [ "$_N1" = "$_N2" ] && [ "$_N2" = "$_N3" ] && [ "$_N3" = "$_N4" ]; then
    ok "N $_fn is identical across all 4 carrying ports (comment-normalised cksum)"
  else
    bad "N port parity ($_fn)" "$_fn DIFFERS across ports: cc=$_N1 ag=$_N2 cu=$_N3 cx=$_N4"
  fi
  # (2026-10-14) Codex JOINED the parity set: until then its handoff/wrapup skills called
  # kt_ss_ledger_add/_prune while its lib defined neither, so the call died with
  # `command not found`. The arm that asserted codex carries NO such function was a
  # tripwire for exactly this transition — it went red on the day the functions landed,
  # and is replaced by the 4-port equality above rather than deleted.
done

# --- O: mark_inprogress leaves a LIVE active prompt's identity alone ----------------------------
# ⛔ INVERTED 2026-10-29 FROM A CHARACTERIZATION TEST TO A GUARD. From 2026-09-11 this block asserted
# that an EXISTING sessionId was REPLACED by the marking session's while another session's prompt was
# carried through -- recorded then as "ordinary operation" so the /wrapup and /handoff demote clauses
# could reason about it. That state is the defect: post-edit-check.sh produced it on the first edit of
# any session in a project holding a handoff, and kt_ss_ledger_token_locate then reported the HOOK's
# sid/at for the prompt's own token. Measured 2026-10-29 (session 879f0754): a token naming
# 5ce12827@23:12:55Z located as 879f0754|23:16:12Z, and resolved only after the front matter was
# restored by hand. Plan: docs/superpowers/plans/2026-10-29-inprogress-mark-respects-live-handoff.md
#
# A live active prompt now leaves the front matter byte-identical. O3/O4 are the POSITIVE controls: an
# empty active slot and a fresh `(session in progress)` file ARE still marked, so a mutation that stops
# the hook writing at all goes red here rather than passing as "guarded".
# ⚠ The /wrapup + /handoff gate still must NOT test sessionId: files stamped before this fix, and
# installs that predate it, keep the hook's id over another session's prompt.
mkdir -p "$TMP/o"
: > "$TMP/o/CLAUDE.md"
cat > "$TMP/o/SESSION.md" <<'SESS'
---
lastEvent: handoff
at: 2026-05-02T00:00:00Z
currentFocus: prior arc, mid-flight
nextAction: finish the thing
sessionId: sess-prior
by: mipr
---

## Next session prompt

```
O-SENTINEL-PRIOR-PROMPT
```
SESS
cp "$TMP/o/SESSION.md" "$TMP/o/before.md"
kt_ss_mark_inprogress "$TMP/o" "sess-mine" "mipr"

# O1 — THE GUARD (pre-token prompt): the whole file is byte-identical. Byte equality rather than a
# sessionId grep, because lastEvent and at are the other two keys the locator and atlas read.
cmp -s "$TMP/o/before.md" "$TMP/o/SESSION.md" \
  && ok "O1 live active prompt (no token): front matter left byte-identical" \
  || bad "O1 live-prompt guard" "the file changed: $(diff "$TMP/o/before.md" "$TMP/o/SESSION.md" | grep '^>' | tr '\n' ';') — the hook re-badged another session's handoff"

# O2 — NON-VACUITY CONTROL: the fixture really did hold a live prompt for O1 to protect.
grep -q 'O-SENTINEL-PRIOR-PROMPT' "$TMP/o/SESSION.md" \
  && ok "O2 control: the prior prompt is present" \
  || bad "O2 control" "the body was lost, so O1 proves nothing about a file that still holds a pickup"

# O3 — POSITIVE CONTROL: heading present, active slot EMPTY -> the session IS marked.
mkdir -p "$TMP/o3"; : > "$TMP/o3/CLAUDE.md"
printf -- '---\nlastEvent: handoff\nat: 2026-05-02T00:00:00Z\nsessionId: sess-prior\n---\n\n## Next session prompt\n\n## Pending handoffs\n\n### sess-x · 2026-05-01T00:00:00Z · handoff · unconsumed\n- prompt: kept\n<!-- aria:entry-end -->\n' > "$TMP/o3/SESSION.md"
kt_ss_mark_inprogress "$TMP/o3" "sess-mine" "mipr"
{ grep -q '^sessionId: sess-mine$' "$TMP/o3/SESSION.md" && grep -q '^lastEvent: in-progress$' "$TMP/o3/SESSION.md"; } \
  && ok "O3 control: empty active slot IS marked in-progress" \
  || bad "O3 control" "an empty active slot was not marked — the guard has become 'never write'"

# O4 — POSITIVE CONTROL: a fresh marker body `(session in progress)` counts as empty.
mkdir -p "$TMP/o4"; : > "$TMP/o4/CLAUDE.md"
printf -- '---\nlastEvent: in-progress\nat: 2026-05-02T00:00:00Z\nsessionId: sess-prior\n---\n\n## Next session prompt\n\n```\n(session in progress)\n```\n' > "$TMP/o4/SESSION.md"
kt_ss_mark_inprogress "$TMP/o4" "sess-mine" "mipr"
grep -q '^sessionId: sess-mine$' "$TMP/o4/SESSION.md" \
  && ok "O4 control: a (session in progress) marker IS re-marked" \
  || bad "O4 control" "a marker body was treated as a live prompt"

# O5 — THE GUARD (token-bearing prompt, the shape every handoff since 2026-09-15 writes). The front
# matter here deliberately DISAGREES with the token -- the stamped state a pre-fix install leaves --
# and the hook must not stamp it again either.
mkdir -p "$TMP/o5"; : > "$TMP/o5/CLAUDE.md"
printf -- '---\nlastEvent: handoff\nat: 2026-10-28T23:12:55Z\nsessionId: author-sid\n---\n\n## Next session prompt\n\n```\naria-handoff: proj-a/author-sid@2026-10-28T23:12:55Z\nproj-a\nresume\n```\n' > "$TMP/o5/SESSION.md"
cp "$TMP/o5/SESSION.md" "$TMP/o5/before.md"
kt_ss_mark_inprogress "$TMP/o5" "sess-mine" "mipr"
cmp -s "$TMP/o5/before.md" "$TMP/o5/SESSION.md" \
  && ok "O5 live active prompt (token): front matter left byte-identical" \
  || bad "O5 token guard" "the file changed: $(diff "$TMP/o5/before.md" "$TMP/o5/SESSION.md" | grep '^>' | tr '\n' ';')"

# O6 — POSITIVE CONTROL, and the regression this arm exists for: an EMPTY FENCE in the active slot
# is what /wrapup and /handoff actually leave behind (`## Next session prompt` + a ``` pair with
# nothing between). v2.57.5 counted the two fence lines as content, so after any wrapup or handoff
# the next first edit was never marked in progress. O3/O4 could not see it: their fixtures had no
# fence. Found 2026-10-30 at a /wrapup, measured on the installed copy.
mkdir -p "$TMP/o6"; : > "$TMP/o6/CLAUDE.md"
printf -- '---\nlastEvent: wrapup\nat: 2026-05-02T00:00:00Z\nsessionId: sess-prior\n---\n\n## Where we left off\nDone.\n\n## Next session prompt\n\n```\n```\n\n## Pending handoffs\n' > "$TMP/o6/SESSION.md"
kt_ss_mark_inprogress "$TMP/o6" "sess-mine" "mipr"
{ grep -q '^sessionId: sess-mine$' "$TMP/o6/SESSION.md" && grep -q '^lastEvent: in-progress$' "$TMP/o6/SESSION.md"; } \
  && ok "O6 control: an empty fenced slot (what /wrapup leaves) IS marked in-progress" \
  || bad "O6 empty fence" "an empty fenced prompt block was treated as a live prompt — after every /wrapup or /handoff the hook stops marking"

# --- Q: kt_ss_mark_inprogress BEHAVIOURAL parity across every carrying port ---------------------
# ⛔ THE PARITY SET (_SS_PARITY_FNS, block N) COVERS kt_ss_ledger_add AND kt_ss_ledger_prune ONLY, so
# the function whose behaviour the /wrapup and /handoff demote clauses REASON ABOUT was unguarded --
# and it has already drifted: cksums are identical across claude-code / antigravity / cursor and
# differ on codex.
#
# ⛔ DO NOT "FIX" THIS BY ADDING THE NAME TO _SS_PARITY_FNS. Two measured reasons:
#   1. Block N's fourth arm asserts codex carries NO such function. True for the ledger pair, FALSE
#      for mark_inprogress, which codex legitimately carries -- so the name reddens a correct state.
#   2. Whole-function byte parity is the WRONG UNIT. Codex's copy differs only in its .gitignore
#      handling, a legitimate per-runtime difference; a cksum gate would be red forever and deleted.
#
# ⭐ WHAT IS ASSERTED INSTEAD is the invariant the clauses actually depend on: the front-matter keys
# are REWRITTEN and the BODY PASSES THROUGH. If that ever stops holding in a port, the corrected
# clause's stated reason becomes false in that runtime while every other check stays green.
_Q_LIBS="plugin-claude-code/scripts plugin-antigravity/bin plugin-cursor-template/scripts/aria plugin-openai-codex/bin"
_Q_SEEN=0
for _qd in $_Q_LIBS; do
  _qf="$REPO_ROOT/$_qd/lib-session-state.sh"
  [ -f "$_qf" ] || { bad "Q $_qd" "lib-session-state.sh missing -- a guard with no subject"; continue; }
  _qbody=$(awk '/^kt_ss_mark_inprogress\(\)/{f=1} f{print} f&&/^}$/{exit}' "$_qf")
  [ -n "$_qbody" ] || continue
  _Q_SEEN=$((_Q_SEEN + 1))
  # (a) all five front-matter keys are MATCHED, not merely mentioned.
  # ⛔ THE FIRST VERSION OF THIS ARM GREPPED THE BARE LITERAL AND COULD NOT FAIL. Mutation M10
  # (2026-09-11) broke the `/^headCommit:/` MATCH branch and this arm stayed GREEN, because the
  # string `headCommit:` also appears in the INSERT branch's `print "headCommit: " hc`. So a guard
  # that asks "is the key mentioned?" answers yes for a function that no longer matches it.
  # Asserting the regex-match form is what "handles the key" actually means.
  # Pattern: guard-described-by-its-regex-not-its-invariant.
  _qmiss=""
  for _qk in 'lastEvent' 'at' 'branch' 'headCommit' 'sessionId'; do
    printf '%s' "$_qbody" | grep -qF "/^$_qk:/" || _qmiss="$_qmiss $_qk"
  done
  [ -z "$_qmiss" ] || bad "Q $_qd keys" "kt_ss_mark_inprogress no longer handles:$_qmiss"
  # (b) the body passthrough survives -- exactly one bare `{ print }`
  # ⛔ awk, NOT `grep -c`. Under `set -e` a zero-match `grep -c` PRINTS 0 and EXITS 1, and in a
  # command substitution that aborts the whole suite -- so this arm could not fail, it could only
  # kill the run, and the summary line vanished with it. Found by mutation M9 (2026-09-11), which
  # produced NO output at all rather than a red arm. Block N's own comment ~30 lines up documents
  # this exact trap; awk always prints exactly once and exits 0.
  _qpt=$(printf '%s' "$_qbody" | awk '/\{ print \}/{c++} END{print c+0}')
  [ "$_qpt" -eq 1 ] \
    || bad "Q $_qd passthrough" "expected exactly one bare '{ print }' body passthrough, found $_qpt -- if it is gone, the demote clauses' stated reason is false in this runtime"
done
# ⛔ ANTI-VACUITY: without this, a renamed dir or a moved lib yields _Q_SEEN=0 and a clean run.
[ "$_Q_SEEN" -ge 4 ] \
  && ok "Q mark_inprogress behavioural parity: $_Q_SEEN ports examined, keys + body-passthrough intact" \
  || bad "Q coverage" "only $_Q_SEEN port lib(s) carried kt_ss_mark_inprogress (want >= 4) -- too few subjects to mean anything"

# --- R: the at-ordering guard (D10) -------------------------------------------------------------
# SESSION.md front-matter is a SINGLE-VALUED, last-writer-wins record written by N concurrent
# sessions, and before this block lib-session-state.sh contained ZERO comparisons of the incumbent's
# `at` (censused 2026-09-15). So an older session's /wrapup or /handoff silently regressed a newer
# session's state. Demote protects the incumbent's PROMPT; nothing protected its STATE.
#
# ⛔ THE COMPARISON IS A PLAIN STRING COMPARE ON SECOND-PRECISION Z, AND THE NARROWNESS IS MEASURED,
# not conservative-by-taste: all 8 tracked ledgers carry a second-precision Z front-matter `at:`.
# Minute-precision exists ONLY in entry headers (6, all in one project), which this guard never
# reads -- censusing headers instead of front-matter is how the first draft acquired a requirement
# for a case that cannot occur on the read path.
#
# ⛔ A NON-Z STAMP MUST BE REJECTED, NEVER COMPARED. `2026-09-02T00:20:21+09:00` is LIVE in the
# corpus; a local-offset stamp compares lexicographically against a Z stamp and silently mis-orders
# while looking entirely reasonable. Arms R6/R7 are that case in both operand positions.
#
# ⛔ EVERY AMBIGUOUS INPUT RETURNS 1 (= "not newer" = caller rewrites exactly as today). A brand-new
# guard must not be able to BLOCK a write that works today; the damage it then fails to prevent is
# the damage that already exists, which is strictly the better failure direction.
#
# ⚑ Calls sit inside `if`, so a missing function reds these arms instead of aborting the suite under
# `set -e` (a bare call to an undefined function exits 127 and would kill the run, taking the summary
# line with it -- the same trap block Q documents for `grep -c`).
_r_mk() {  # $1 = dir, $2 = at-value ("" => omit the at: line entirely)
  mkdir -p "$1"
  if [ -n "$2" ]; then
    printf -- '---\nlastEvent: handoff\nat: %s\nsessionId: incumbent\n---\n\n## Next session prompt\n\nbody\n' "$2" > "$1/SESSION.md"
  else
    printf -- '---\nlastEvent: handoff\nsessionId: incumbent\n---\n\n## Next session prompt\n\nbody\n' > "$1/SESSION.md"
  fi
}
_R_RAN=0
_r_arm() {  # $1 = label, $2 = dir, $3 = my_at, $4 = expected exit (0 = incumbent newer)
  _R_RAN=$((_R_RAN + 1))
  # ⛔ CAPTURE THE TRUE EXIT CODE, AND TREAT 127 AS ITS OWN FAILURE. The first version wrote
  # `if kt_ss_active_is_newer ...; then _rgot=0; else _rgot=1; fi`, which collapses "not defined"
  # (127) into "returned 1" -- and SIX of the eight arms expect 1. Measured 2026-09-15 in the red
  # phase: with the helper entirely absent, R3 R4 R5a R5b R6 R7 all went GREEN. They asserted
  # nothing and would have gone on asserting nothing forever.
  # `|| _rgot=$?` keeps this `set -e`-safe while preserving the real status.
  _rgot=0
  kt_ss_active_is_newer "$2" "$3" >/dev/null 2>&1 || _rgot=$?
  if [ "$_rgot" = 127 ]; then
    bad "$1" "kt_ss_active_is_newer is not defined (exit 127) -- this arm asserts nothing"
  elif [ "$_rgot" = "$4" ]; then
    ok "$1"
  else
    bad "$1" "expected exit $4, got $_rgot (incumbent=$(kt_ss_read_active_at "$2" 2>/dev/null), mine=$3)"
  fi
}

if command -v kt_ss_read_active_at >/dev/null 2>&1 && command -v kt_ss_active_is_newer >/dev/null 2>&1; then
  ok "R0 both helpers are defined"
else
  bad "R0 helpers" "kt_ss_read_active_at and/or kt_ss_active_is_newer are not defined in lib-session-state.sh"
fi

_RD="$TMP/r-at"
# R1 -- the reader returns the front-matter value, and ONLY from the front matter.
_r_mk "$_RD/read" "2026-09-15T10:00:00Z"
_R_RAN=$((_R_RAN + 1))
_rv=$(kt_ss_read_active_at "$_RD/read" 2>/dev/null || true)
[ "$_rv" = "2026-09-15T10:00:00Z" ] && ok "R1 read_active_at returns the front-matter at:" \
  || bad "R1 read_active_at" "expected 2026-09-15T10:00:00Z, got '$_rv'"

# R2 (AC18a) -- incumbent NEWER => 0 => caller must NOT rewrite. The headline case.
_r_mk "$_RD/newer" "2026-09-15T12:00:00Z"
_r_arm "R2 incumbent newer => do not rewrite" "$_RD/newer" "2026-09-15T09:00:00Z" 0

# R3 (AC18b) -- incumbent OLDER => 1 => rewrite as today.
# ⛔ THE NON-REGRESSION ARM. Without it, a guard that ALWAYS self-demotes passes R2 and silently
# breaks the normal path -- every session would stop writing its own state.
_r_mk "$_RD/older" "2026-09-15T08:00:00Z"
_r_arm "R3 incumbent older => rewrite (non-regression)" "$_RD/older" "2026-09-15T09:00:00Z" 1

# R4 (AC18e) -- EQUAL => 1. Named because `>` vs `>=` is the one-character defect this shape invites,
# and a fixture built only from distinct stamps cannot catch it.
_r_mk "$_RD/equal" "2026-09-15T09:00:00Z"
_r_arm "R4 equal => not newer => rewrite" "$_RD/equal" "2026-09-15T09:00:00Z" 1

# R5 (AC18c) -- at: absent => 1, and a MISSING FILE => 1. Ambiguity resolves to today's behaviour.
_r_mk "$_RD/noat" ""
_r_arm "R5a no at: in front matter => rewrite" "$_RD/noat" "2026-09-15T09:00:00Z" 1
_r_arm "R5b SESSION.md absent => rewrite" "$_RD/does-not-exist" "2026-09-15T09:00:00Z" 1

# R6/R7 (AC18d) -- a non-Z stamp is REJECTED in EITHER operand position. R6's incumbent is
# lexicographically GREATER than the caller's stamp, so a guard that compared it anyway would return
# 0 and wrongly self-demote; the arm therefore fails loudly if the rejection is dropped.
_r_mk "$_RD/offset" "2026-09-15T22:00:00+09:00"
_r_arm "R6 non-Z incumbent rejected, not compared" "$_RD/offset" "2026-09-15T09:00:00Z" 1
_r_mk "$_RD/callerz" "2026-09-15T12:00:00Z"
_r_arm "R7 non-Z caller arg rejected, not compared" "$_RD/callerz" "2026-09-15T09:00:00+09:00" 1

# ⛔ ANTI-VACUITY: without this, an early `return` or a renamed helper yields zero executed arms and
# a clean run. 8 = R1 + R2 + R3 + R4 + R5a + R5b + R6 + R7.
[ "$_R_RAN" -eq 8 ] \
  && ok "R coverage: $_R_RAN at-ordering arms executed" \
  || bad "R coverage" "only $_R_RAN at-ordering arms executed (want 8) -- too few subjects to mean anything"

# --- S: kt_ss_ledger_mark_consumed is LITERAL and optionally KEY-EXACT (D6) ----------------------
# Two independent defects on ONE matcher, found by two different gates a fortnight apart:
#   1. `$0 ~ ("^### .*" sid)` interpolates the caller's sid into an awk REGEX, unescaped. The live
#      legacy sid `e95b0202 (contract-coherence)` matches BY LUCK -- its parentheses form a group
#      matching the same literal. A sid carrying `[`, `*` or `.` mis-matches or OVER-matches silently.
#   2. The match ignores `at` entirely, so one sid under two timestamps marks BOTH. Measured live on
#      proj-a/SESSION.md, which carried 374e75de under two different `at` values.
#
# ⛔ `at` IS OPTIONAL (5th arg), DELIBERATELY. Making it required would change the existing caller's
# RECALL: post-edit-check.sh resolves the prior session from front matter, and the entry it means to
# consume was demoted with whatever `at` was current THEN -- not necessarily what the front matter
# reads now. Precision gained, recall lost, in a path no test covers. So the literal-match half is
# fixed unconditionally (it is unambiguously a bug) and the key-exact half is opt-in for callers that
# hold the exact key -- which is what the token path in Unit C will have.
_s_mk() {  # $1 = dir
  mkdir -p "$1"
  printf -- '---\nlastEvent: handoff\nsessionId: x\n---\n\n## Pending handoffs\n\n' > "$1/SESSION.md"
}
_s_entry() {  # $1 = dir, $2 = sid, $3 = at
  printf -- '### %s · %s · handoff · unconsumed\n- focus: f\n- prompt:\nbody\n<!-- aria:entry-end -->\n\n' "$2" "$3" >> "$1/SESSION.md"
}
_S_RAN=0
_SD="$TMP/s-consume"

# S1 -- a sid containing regex metacharacters is matched LITERALLY.
# `x[1]` as a regex matches the string "x1", NOT "x[1]", so the literal header goes unmarked today.
_S_RAN=$((_S_RAN + 1))
_s_mk "$_SD/meta"; _s_entry "$_SD/meta" 'x[1]' '2026-09-14T10:00:00Z'
kt_ss_ledger_mark_consumed "$_SD/meta" 'x[1]' '2026-09-15T00:00:00Z' 'tester' >/dev/null 2>&1 || true
if grep -q '· handoff · consumed' "$_SD/meta/SESSION.md"; then ok "S1 metacharacter sid matched literally"
else bad "S1 metacharacter sid" "sid 'x[1]' left its own entry unmarked — the sid is being used as a regex"; fi

# S2 -- and the same escaping prevents OVER-match. `a.c` as a regex matches the UNRELATED entry
# `abc`; literally it matches neither. This is the dangerous direction: it marks someone else's entry.
_S_RAN=$((_S_RAN + 1))
_s_mk "$_SD/over"; _s_entry "$_SD/over" 'abc' '2026-09-14T10:00:00Z'
kt_ss_ledger_mark_consumed "$_SD/over" 'a.c' '2026-09-15T00:00:00Z' 'tester' >/dev/null 2>&1 || true
if grep -q '· handoff · consumed' "$_SD/over/SESSION.md"; then bad "S2 regex over-match" "sid 'a.c' consumed the UNRELATED entry 'abc' — a regex match is marking the wrong session's entry"
else ok "S2 unrelated entry not consumed by a regex-looking sid"; fi

# S3 -- with `at` supplied, ONE sid under TWO timestamps marks exactly the named one.
_S_RAN=$((_S_RAN + 1))
_s_mk "$_SD/exact"
_s_entry "$_SD/exact" 'dup-sid' '2026-09-14T10:00:00Z'
_s_entry "$_SD/exact" 'dup-sid' '2026-09-14T22:00:00Z'
kt_ss_ledger_mark_consumed "$_SD/exact" 'dup-sid' '2026-09-15T00:00:00Z' 'tester' '2026-09-14T22:00:00Z' >/dev/null 2>&1 || true
_sn=$(awk '/· handoff · consumed/{c++} END{print c+0}' "$_SD/exact/SESSION.md")
_sw=$(awk '/2026-09-14T22:00:00Z · handoff · consumed/{c++} END{print c+0}' "$_SD/exact/SESSION.md")
{ [ "$_sn" -eq 1 ] && [ "$_sw" -eq 1 ]; } \
  && ok "S3 at-conjunct marks exactly the named entry" \
  || bad "S3 at-conjunct" "expected exactly 1 consumed and it to be the 22:00 entry; got consumed=$_sn correct=$_sw"

# S4 -- ⛔ NON-REGRESSION: with `at` OMITTED, behaviour is unchanged — every entry for that sid marks.
# Without this arm, making `at` mandatory-in-effect would pass S3 and silently break the live caller.
_S_RAN=$((_S_RAN + 1))
_s_mk "$_SD/compat"
_s_entry "$_SD/compat" 'dup-sid' '2026-09-14T10:00:00Z'
_s_entry "$_SD/compat" 'dup-sid' '2026-09-14T22:00:00Z'
kt_ss_ledger_mark_consumed "$_SD/compat" 'dup-sid' '2026-09-15T00:00:00Z' 'tester' >/dev/null 2>&1 || true
_sc=$(awk '/· handoff · consumed/{c++} END{print c+0}' "$_SD/compat/SESSION.md")
[ "$_sc" -eq 2 ] && ok "S4 at omitted => legacy behaviour, both entries marked (non-regression)" \
  || bad "S4 legacy behaviour" "expected 2 consumed with at omitted, got $_sc — the existing caller's recall changed"

# ⛔ ANTI-VACUITY.
[ "$_S_RAN" -eq 4 ] && ok "S coverage: $_S_RAN consume arms executed" \
  || bad "S coverage" "only $_S_RAN consume arms executed (want 4)"

# --- T: kt_ss_ledger_candidates — one read helper for the whole four-axis parse ------------------
# ⛔ THIS IS A HELPER, NOT PROSE, AND THE REASON IS AC5. The acceptance criterion demands a fixture
# yielding 2 candidates plus a mutation that reddens -- and a shell suite cannot exercise a parser
# that exists only as an instruction inside a SKILL.md. Putting the parse here also means resume,
# the picker and the token lookup share ONE implementation instead of re-deriving it three times.
#
# The four axes it must absorb, each of which silently DROPS candidates when missed:
#   headings      -- `## Pending handoffs` (current) and `## Prior sessions` (legacy, still live)
#   terminators   -- the explicit marker, or NOTHING; fall back to "next ### or next ##"
#   prompt forms  -- `- prompt:` + block, and `- prompt: <text>` inline on one line
#   status forms  -- unconsumed / consumed <ts> by <sid> / in-progress (demoted, UNFINISHED)
#
# ⛔ ARCHIVED SECTIONS ARE NOT CANDIDATES. 89 entries were archived out of proj-a/SESSION.md on
# 2026-09-15 precisely so they would stop being offered; T4 is what stops that being undone.
_T_RAN=0
# ⛔ `|| true` IS LOAD-BEARING. Without it, `_tout=$(_t_cand ...)` against an undefined helper
# returns 127, and under `set -e` a failing command substitution ABORTS THE WHOLE SUITE -- the run
# dies mid-block and the "N passed, M failed" summary never prints, so the red phase reads as a
# hang rather than a failure. Block Q documents this exact trap for `grep -c`; it applies to any
# command substitution whose subject may not exist yet, which in a red phase is all of them.
_t_cand() { kt_ss_ledger_candidates "$1" 2>/dev/null || true; }

MSF="$REPO_ROOT/tests/fixtures/session-contract-vendored/handoff-multi-session.SESSION.md"
TD="$TMP/t-cand"; mkdir -p "$TD/fx"; cp "$MSF" "$TD/fx/SESSION.md"

# T1 (AC5) -- the fixture holds a LEGACY entry (## Prior sessions, no terminator, inline prompt) and
# a CURRENT one (## Pending handoffs, terminator, block prompt), plus an active prompt. All three
# are candidates under D3.
_T_RAN=$((_T_RAN + 1))
_tout=$(_t_cand "$TD/fx"); _tn=$(printf '%s\n' "$_tout" | awk 'NF{c++} END{print c+0}')
if [ "$_tn" -eq 3 ]; then ok "T1 legacy + current + active all parsed (3 candidates)"
else bad "T1 candidate parse" "expected 3 candidates, got $_tn — a parser that finds fewer looks exactly like a file with fewer. got: $(printf '%s' "$_tout" | tr '\n' ';')"; fi

# T2 (AC5 mutation target) -- the LEGACY entry specifically must survive. Named separately so a
# mutation removing the `## Prior sessions` arm reddens with the dropped entry NAMED.
_T_RAN=$((_T_RAN + 1))
printf '%s\n' "$_tout" | grep -q '^sess-old|' \
  && ok "T2 legacy entry (no terminator) present by name" \
  || bad "T2 legacy entry" "sess-old dropped — the legacy heading/terminator fallback is gone"

# T3 (D3) -- the ACTIVE prompt is a candidate, sourced from the front matter.
_T_RAN=$((_T_RAN + 1))
printf '%s\n' "$_tout" | grep -q '^sess-active|.*|active$' \
  && ok "T3 active prompt is a candidate, tagged active" \
  || bad "T3 active candidate" "the active prompt is missing or mis-tagged — G3's converse"

# T4 (AC9) -- ⛔ entries under an ARCHIVED heading are NOT candidates.
_T_RAN=$((_T_RAN + 1))
mkdir -p "$TD/arch"
printf -- '---\nlastEvent: handoff\nsessionId: x\n---\n\n## Archived sessions — 2026-08-01 → 2026-08-02 (stale)\n\n### arch-1 · 2026-08-01T10:00:00Z · handoff · unconsumed\n- focus: archived\n<!-- aria:entry-end -->\n' > "$TD/arch/SESSION.md"
# ⛔ DIFFERENTIAL, not a bare zero. "Archived yields 0" is satisfied by a MISSING HELPER, which is
# exactly how it passed vacuously in the red phase. The same entry under `## Pending handoffs` must
# yield 1, so the HEADING is what moves the result and the arm cannot be green on absence.
mkdir -p "$TD/archctl"
sed 's|^## Archived sessions.*|## Pending handoffs|' "$TD/arch/SESSION.md" > "$TD/archctl/SESSION.md"
_ta=$(_t_cand "$TD/arch"    | awk 'NF{c++} END{print c+0}')
_tc=$(_t_cand "$TD/archctl" | awk 'NF{c++} END{print c+0}')
{ [ "$_ta" -eq 0 ] && [ "$_tc" -eq 1 ]; } \
  && ok "T4 archived not offered, same entry under Pending IS (0 vs 1)" \
  || bad "T4 archived offered" "expected archived=0 and the Pending control=1; got archived=$_ta control=$_tc — a bare zero here is also what a MISSING helper produces"

# T5 (AC6) -- pending entries with NO active prompt are still listed. This is G3, the gap where a
# pending entry currently surfaces nothing at all.
_T_RAN=$((_T_RAN + 1))
mkdir -p "$TD/noactive"
printf -- '---\nlastEvent: wrapup\nsessionId: y\n---\n\n## Pending handoffs\n\n### only-pending · 2026-09-01T10:00:00Z · handoff · unconsumed\n- focus: f\n<!-- aria:entry-end -->\n' > "$TD/noactive/SESSION.md"
_tp=$(_t_cand "$TD/noactive" | awk 'NF{c++} END{print c+0}')
[ "$_tp" -eq 1 ] && ok "T5 pending listed with no active sibling (G3)" \
  || bad "T5 G3" "expected 1 candidate, got $_tp"

# T6 (AC2) -- zero candidates is a CLEAN empty result, never an error.
_T_RAN=$((_T_RAN + 1))
mkdir -p "$TD/empty"; printf -- '---\nlastEvent: wrapup\nsessionId: z\n---\n\n## Where we left off\n\nnothing\n' > "$TD/empty/SESSION.md"
_te=$(_t_cand "$TD/empty" | awk 'NF{c++} END{print c+0}'); _terc=0
kt_ss_ledger_candidates "$TD/empty" >/dev/null 2>&1 || _terc=$?
{ [ "$_te" -eq 0 ] && [ "$_terc" -ne 127 ]; } && ok "T6 zero candidates, clean exit" \
  || bad "T6 empty" "expected 0 candidates and a defined helper; got $_te candidates, exit $_terc"

# T7 -- ⛔ FENCE-AWARENESS, which the implementation names as its mechanism and which NOTHING
# tested until this arm. A stored prompt routinely contains column-0 `### ` and `## ` lines --
# full-fidelity demotion is why -- and a parse that reads them as structure invents a candidate and
# loses the section. Here the fenced prompt carries BOTH; the correct answer is 1, not 2.
_T_RAN=$((_T_RAN + 1))
mkdir -p "$TD/fence"
{ printf -- '---\nlastEvent: handoff\nsessionId: f\n---\n\n## Pending handoffs\n\n'
  printf -- '### real-one · 2026-09-01T10:00:00Z · handoff · unconsumed\n- focus: f\n- prompt:\n'
  printf -- '```\n### fake-entry · 2026-01-01T00:00:00Z · handoff · unconsumed\n## Pending handoffs\nstill the stored prompt\n```\n'
  printf -- '<!-- aria:entry-end -->\n'
} > "$TD/fence/SESSION.md"
_tf=$(_t_cand "$TD/fence" | awk 'NF{c++} END{print c+0}')
_tfk=$(_t_cand "$TD/fence" | grep -c '^fake-entry|' || true)
{ [ "$_tf" -eq 1 ] && [ "$_tfk" -eq 0 ]; } \
  && ok "T7 column-0 markers inside a stored prompt are not structure" \
  || bad "T7 fence-awareness" "expected 1 candidate and 0 fakes; got $_tf candidates, $_tfk fake — a `### ` inside a fenced prompt is being read as an entry"

# ⛔ ANTI-VACUITY.
[ "$_T_RAN" -eq 7 ] && ok "T coverage: $_T_RAN candidate arms executed" \
  || bad "T coverage" "only $_T_RAN candidate arms executed (want 7)"

# --- U: kt_ss_token_locate — find a PASTED prompt by its provenance token ------------------------
# The token travels INSIDE the opener fence, and the 3e opener is reused verbatim in both the
# pasteable artifact and the SESSION.md prompt block -- so the same bytes exist in both places and
# the prompt is SELF-LOCATING. Locate by the token STRING, never by sid: between a /handoff and the
# paste, another session can demote the prompt, which is not hypothetical (measured 2026-09-14, a
# demote 14 minutes later).
#
# ⛔ THREE OUTCOMES, NOT TWO. `archived` is a distinct answer from EMPTY. A token found under an
# archive heading was deliberately taken out of the offer -- 89 entries were archived for exactly
# that reason -- so reporting it as "not found" would invite a caller to resurrect it, while
# reporting it as offerable would undo the archiving. It is LOCATED BUT NOT OFFERED.
_U_RAN=0
_u_loc() { kt_ss_ledger_token_locate "$1" "$2" 2>/dev/null || true; }
_u_tok='aria-handoff: proj-a/tok-sid@2026-09-10T10:00:00Z'
UD="$TMP/u-token"

# U1 (AC-C1) -- token in the ACTIVE prompt block.
_U_RAN=$((_U_RAN + 1)); mkdir -p "$UD/active"
printf -- '---\nlastEvent: handoff\nat: 2026-09-10T10:00:00Z\nsessionId: tok-sid\n---\n\n## Next session prompt\n\n```\n%s\ncs\nresume\n```\n' "$_u_tok" > "$UD/active/SESSION.md"
_uo=$(_u_loc "$UD/active" "$_u_tok")
printf '%s' "$_uo" | grep -q '^tok-sid|2026-09-10T10:00:00Z|.*|active$' \
  && ok "U1 token in the active slot is located, tagged active" \
  || bad "U1 active" "expected tok-sid|...|active, got '$_uo'"

# U2 (AC-C2) -- the SAME token after DEMOTION into Pending. This is the relocation case and the
# reason lookup is by token rather than by sid.
_U_RAN=$((_U_RAN + 1)); mkdir -p "$UD/demoted"
printf -- '---\nlastEvent: handoff\nat: 2026-09-12T09:00:00Z\nsessionId: someone-else\n---\n\n## Pending handoffs\n\n### tok-sid · 2026-09-10T10:00:00Z · handoff · unconsumed\n- focus: f\n- prompt:\n```\n%s\ncs\nresume\n```\n<!-- aria:entry-end -->\n' "$_u_tok" > "$UD/demoted/SESSION.md"
_uo=$(_u_loc "$UD/demoted" "$_u_tok")
printf '%s' "$_uo" | grep -q '^tok-sid|2026-09-10T10:00:00Z|.*|pending$' \
  && ok "U2 token still located after demotion, tagged pending" \
  || bad "U2 demoted" "expected tok-sid|...|pending, got '$_uo' — lookup is following the sid or the slot, not the token"

# U3 (AC-C3) -- ⛔ ARCHIVED is its own answer. Not empty, not offerable.
_U_RAN=$((_U_RAN + 1)); mkdir -p "$UD/archived"
printf -- '---\nlastEvent: handoff\nat: 2026-09-12T09:00:00Z\nsessionId: someone-else\n---\n\n## Archived sessions — 2026-09-01 → 2026-09-10 (stale)\n\n### tok-sid · 2026-09-10T10:00:00Z · handoff · unconsumed\n- focus: f\n- prompt:\n```\n%s\ncs\nresume\n```\n<!-- aria:entry-end -->\n' "$_u_tok" > "$UD/archived/SESSION.md"
_uo=$(_u_loc "$UD/archived" "$_u_tok")
printf '%s' "$_uo" | grep -q '|archived$' \
  && ok "U3 token under an archive heading reports archived, not empty" \
  || bad "U3 archived" "expected a line ending |archived, got '$_uo' — an empty answer invites resurrecting it; an offerable one undoes the archiving"

# U4 (AC-C4) -- an absent token is EMPTY and is not an error.
_U_RAN=$((_U_RAN + 1))
_uo=$(_u_loc "$UD/active" 'aria-handoff: proj-a/nobody@2026-01-01T00:00:00Z')
_urc=0; kt_ss_ledger_token_locate "$UD/active" 'aria-handoff: proj-a/nobody@2026-01-01T00:00:00Z' >/dev/null 2>&1 || _urc=$?
{ [ -z "$_uo" ] && [ "$_urc" -ne 127 ]; } \
  && ok "U4 absent token yields empty, helper defined, no error" \
  || bad "U4 absent" "expected empty and a defined helper; got '$_uo' exit $_urc"

# U5 (AC-C5) -- ⛔ NON-REGRESSION. A tokenless file yields nothing AND kt_ss_ledger_candidates is
# untouched. 152 stored prompts carry no token and must behave exactly as before.
_U_RAN=$((_U_RAN + 1)); mkdir -p "$UD/notoken"
printf -- '---\nlastEvent: handoff\nat: 2026-09-10T10:00:00Z\nsessionId: plain\n---\n\n## Next session prompt\n\n```\ncs\nresume\n```\n' > "$UD/notoken/SESSION.md"
_uo=$(_u_loc "$UD/notoken" "$_u_tok")
_uc=$(kt_ss_ledger_candidates "$UD/notoken" 2>/dev/null | awk 'NF{c++} END{print c+0}')
{ [ -z "$_uo" ] && [ "$_uc" -eq 1 ]; } \
  && ok "U5 tokenless file: no token hit, candidates unaffected" \
  || bad "U5 non-regression" "expected no token hit and 1 candidate; got token='$_uo' candidates=$_uc"

# ⛔ ANTI-VACUITY.
[ "$_U_RAN" -eq 5 ] && ok "U coverage: $_U_RAN token-locate arms executed" \
  || bad "U coverage" "only $_U_RAN token-locate arms executed (want 5)"

# --- V: the active slot's identity comes from its TOKEN, and consume_active is pinned ------------
# Added 2026-10-29 with the block O inversion. Two gaps it closes:
#   1. kt_ss_ledger_consume_active had NO committed test anywhere -- the one function that clears a
#      prompt irreversibly. V1/V2 pin it before its boundary walk is shared with mark_inprogress.
#   2. token_locate's ACTIVE branch and ledger_candidates' active row reported FRONT-MATTER identity.
#      consume_active already read token-first; these two did not, so a hook-stamped file made a
#      pasted token resolve to the stamping session (879f0754|23:16:12Z for 5ce12827@23:12:55Z).
#      Files stamped before the writer fix keep that front matter, so the readers must not trust it.
_V_RAN=0
VD="$TMP/v"
_v_tok='aria-handoff: proj-a/author-sid@2026-10-28T23:12:55Z'
_v_stamped() {  # $1 dir — front matter stamped by another session, token names the author
  mkdir -p "$1"; : > "$1/CLAUDE.md"
  printf -- '---\nlastEvent: in-progress\nat: 2026-10-28T23:16:12Z\ncurrentFocus: the work\nnextAction: do it\nsessionId: stamper-sid\n---\n\n## Next session prompt\n\n```\n%s\nproj-a\nV-SENTINEL resume\n```\n\n## Pending handoffs\n' "$_v_tok" > "$1/SESSION.md"
}

# V1 -- consume_active on a live, token-bearing prompt: demoted under the TOKEN's identity, marked
# consumed by the resuming session, active slot emptied.
_V_RAN=$((_V_RAN + 1)); _v_stamped "$VD/c1"
_v_rc=0; kt_ss_ledger_consume_active "$VD/c1" "resumer-sid" "2026-10-29T00:30:38Z" "$_v_tok" 2>/dev/null || _v_rc=$?
_v_hdr=$(grep '^### author-sid · 2026-10-28T23:12:55Z' "$VD/c1/SESSION.md" || true)
_v_act=$(awk '/^## Next session prompt/{a=1;next} /^## /{a=0} a&&NF' "$VD/c1/SESSION.md")
{ [ "$_v_rc" -eq 0 ] && printf '%s' "$_v_hdr" | grep -q 'consumed 2026-10-29T00:30:38Z by resumer-sid' \
  && [ -z "$_v_act" ] && grep -q 'V-SENTINEL resume' "$VD/c1/SESSION.md"; } \
  && ok "V1 consume_active: demoted under the token's sid/at, consumed, active slot cleared" \
  || bad "V1 consume_active" "header='$_v_hdr' active='$(printf '%s' "$_v_act" | tr '\n' ';')'"

# V2 -- consume_active on a fresh `(session in progress)` marker is a BYTE-for-byte no-op.
_V_RAN=$((_V_RAN + 1)); mkdir -p "$VD/c2"
printf -- '---\nlastEvent: in-progress\nat: 2026-10-28T23:16:12Z\nsessionId: s\n---\n\n## Next session prompt\n\n```\n(session in progress)\n```\n' > "$VD/c2/SESSION.md"
cp "$VD/c2/SESSION.md" "$VD/c2/before.md"
_v_rc=0; kt_ss_ledger_consume_active "$VD/c2" "resumer-sid" "2026-10-29T00:30:38Z" "$_v_tok" 2>/dev/null || _v_rc=$?
[ "$_v_rc" -eq 2 ] && cmp -s "$VD/c2/before.md" "$VD/c2/SESSION.md" \
  && ok "V2 consume_active: a (session in progress) marker is left byte-identical, exit 2" \
  || bad "V2 consume_active no-op" "a marker body was demoted or the file was rewritten"

# V3 -- token_locate on a stamped file reports the TOKEN's identity, not the stamper's.
_V_RAN=$((_V_RAN + 1)); _v_stamped "$VD/l3"
_vo=$(kt_ss_ledger_token_locate "$VD/l3" "$_v_tok" 2>/dev/null || true)
[ "$_vo" = "author-sid|2026-10-28T23:12:55Z|unconsumed|active" ] \
  && ok "V3 token_locate: active prompt reports the token's sid/at over stamped front matter" \
  || bad "V3 token_locate identity" "got '$_vo' — the locator is reading front matter a hook rewrote"

# V4 -- ledger_candidates' active row: same disagreement, same answer.
_V_RAN=$((_V_RAN + 1)); _v_stamped "$VD/l4"
_vo=$(kt_ss_ledger_candidates "$VD/l4" 2>/dev/null | grep '|active$' || true)
[ "$_vo" = "author-sid|2026-10-28T23:12:55Z|unconsumed|active" ] \
  && ok "V4 ledger_candidates: active row reports the token's sid/at" \
  || bad "V4 candidates identity" "got '$_vo'"

# V5 -- consume_active on an EMPTY FENCE (the /wrapup and /handoff template) is a byte no-op: no
# junk entry is demoted into Pending. Same predicate as O6, seen from the other caller.
_V_RAN=$((_V_RAN + 1)); mkdir -p "$VD/c5"
printf -- '---\nlastEvent: wrapup\nat: 2026-10-28T23:16:12Z\nsessionId: s\n---\n\n## Next session prompt\n\n```\n```\n\n## Pending handoffs\n' > "$VD/c5/SESSION.md"
cp "$VD/c5/SESSION.md" "$VD/c5/before.md"
_v_rc=0; kt_ss_ledger_consume_active "$VD/c5" "resumer-sid" "2026-10-29T00:30:38Z" "$_v_tok" 2>/dev/null || _v_rc=$?
[ "$_v_rc" -eq 2 ] && cmp -s "$VD/c5/before.md" "$VD/c5/SESSION.md" \
  && ok "V5 consume_active: an empty fenced slot is left byte-identical, exit 2" \
  || bad "V5 consume_active empty fence" "rc=$_v_rc — an empty fence was demoted, or the refusal was not reported"

# ⛔ ANTI-VACUITY.
[ "$_V_RAN" -eq 5 ] && ok "V coverage: $_V_RAN active-identity arms executed" \
  || bad "V coverage" "only $_V_RAN arms executed (want 5)"

# --- W: consume_active consumes ONLY the prompt the caller located (2.57.8, I-4) ----------------
# The resume flow is locate-then-consume, two calls with a model turn between them, while several
# sessions write one SESSION.md. Before 2.57.8 consume_active took no token and consumed WHATEVER
# was active at call time, so a peer's handoff written in that window was demoted, marked consumed
# and the call exited 0 (measured twice; once 2026-11-06, repaired by hand). Exit 0 now means
# "consumed the expected prompt" and nothing else: 1 = bad/missing token, 2 = the slot does not
# hold that token, 3 = the demote did not land.
_W_RAN=0
WD="$TMP/w"
_w_slot() {  # $1 dir, $2 token line, $3 extra body line
  mkdir -p "$1"; : > "$1/CLAUDE.md"
  printf -- '---\nlastEvent: handoff\nat: 2026-11-06T20:56:20Z\nsessionId: peer-sid\n---\n\n## Next session prompt\n\n```\n%s\n%s\nW-PEER live handoff\n```\n\n## Pending handoffs\n' "$2" "$3" > "$1/SESSION.md"
  cp "$1/SESSION.md" "$1/before.md"
}
_w_a='aria-handoff: proj-a/old-sid@2026-11-06T20:40:00Z'
_w_b='aria-handoff: proj-a/peer-sid@2026-11-06T20:56:20Z'

# W1 (B1) -- the slot now holds a peer's token B; the caller located A. Refuse, touch nothing.
_W_RAN=$((_W_RAN + 1)); _w_slot "$WD/w1" "$_w_b" "body"
_w_rc=0; kt_ss_ledger_consume_active "$WD/w1" "resumer" "2026-11-06T20:57:07Z" "$_w_a" 2>/dev/null || _w_rc=$?
[ "$_w_rc" -eq 2 ] && cmp -s "$WD/w1/before.md" "$WD/w1/SESSION.md" \
  && ok "W1 consume_active refuses a slot holding a different token (exit 2, byte-identical)" \
  || bad "W1 wrong-prompt consume" "rc=$_w_rc — the peer's live handoff was consumed or the file changed"

# W2 (B2) -- no token at all (an un-updated caller): refuse loudly, touch nothing.
_W_RAN=$((_W_RAN + 1)); _w_slot "$WD/w2" "$_w_b" "body"
_w_rc=0; kt_ss_ledger_consume_active "$WD/w2" "resumer" "2026-11-06T20:57:07Z" 2>/dev/null || _w_rc=$?
[ "$_w_rc" -eq 1 ] && cmp -s "$WD/w2/before.md" "$WD/w2/SESSION.md" \
  && ok "W2 consume_active without a token is refused (exit 1, byte-identical)" \
  || bad "W2 tokenless call" "rc=$_w_rc — a caller passing no token still consumed by position"

# W3 (B4) -- the peer prompt QUOTES token A in its prose, but its own first token line is B.
# token_locate's substring match would call A active; consume_active must compare the slot's token.
_W_RAN=$((_W_RAN + 1)); _w_slot "$WD/w3" "$_w_b" "resumed from $_w_a"
_w_rc=0; kt_ss_ledger_consume_active "$WD/w3" "resumer" "2026-11-06T20:57:07Z" "$_w_a" 2>/dev/null || _w_rc=$?
[ "$_w_rc" -eq 2 ] && cmp -s "$WD/w3/before.md" "$WD/w3/SESSION.md" \
  && ok "W3 a quoted token in the prose does not make the slot match (exit 2)" \
  || bad "W3 quoted token" "rc=$_w_rc — identity was taken from a quoted mention, not the slot's own token"

# W4 (B5) -- no SESSION.md at all, with a token: the expected prompt is not there; say so.
_W_RAN=$((_W_RAN + 1)); mkdir -p "$WD/w4"
_w_rc=0; kt_ss_ledger_consume_active "$WD/w4" "resumer" "2026-11-06T20:57:07Z" "$_w_a" 2>/dev/null || _w_rc=$?
[ "$_w_rc" -eq 2 ] && [ ! -e "$WD/w4/SESSION.md" ] \
  && ok "W4 no SESSION.md: refused with exit 2, nothing created" \
  || bad "W4 absent ledger" "rc=$_w_rc"

# W5 (B3) -- the positive case: the slot holds A, the caller passes A WITHOUT the prefix.
_W_RAN=$((_W_RAN + 1)); _w_slot "$WD/w5" "$_w_a" "body"
_w_rc=0; kt_ss_ledger_consume_active "$WD/w5" "resumer" "2026-11-06T20:57:07Z" "proj-a/old-sid@2026-11-06T20:40:00Z" 2>/dev/null || _w_rc=$?
_w_hdr=$(grep '^### old-sid · 2026-11-06T20:40:00Z' "$WD/w5/SESSION.md" || true)
_w_act=$(awk '/^## Next session prompt/{a=1;next} /^## /{a=0} a&&NF' "$WD/w5/SESSION.md")
{ [ "$_w_rc" -eq 0 ] && printf '%s' "$_w_hdr" | grep -q 'consumed 2026-11-06T20:57:07Z by resumer' && [ -z "$_w_act" ]; } \
  && ok "W5 matching token (bare form) consumes: demoted under it, consumed, slot cleared" \
  || bad "W5 matching consume" "rc=$_w_rc header='$_w_hdr' active='$(printf '%s' "$_w_act" | tr '\n' ';')'"

[ "$_W_RAN" -eq 5 ] && ok "W coverage: $_W_RAN expected-token arms executed" \
  || bad "W coverage" "only $_W_RAN arms executed (want 5)"

# --- X: the same contract in EVERY port that carries consume_active (behavioural, per lib) -------
# Byte parity is the wrong unit here for the reason block Q gives; what must hold in each runtime
# is the BEHAVIOUR: a mismatched token is refused untouched, a matching one is consumed.
_X_SEEN=0
for _xd in plugin-claude-code/scripts plugin-antigravity/bin plugin-cursor-template/scripts/aria plugin-openai-codex/bin; do
  _xf="$REPO_ROOT/$_xd/lib-session-state.sh"
  [ -f "$_xf" ] || { bad "X $_xd" "lib-session-state.sh missing -- a guard with no subject"; continue; }
  _X_SEEN=$((_X_SEEN + 1))
  _xn=$(printf '%s' "$_xd" | tr '/' '_')
  _w_slot "$WD/x-$_xn-m" "$_w_b" "body"; _w_slot "$WD/x-$_xn-k" "$_w_a" "body"
  _xr=$( ( . "$_xf"
           r1=0; kt_ss_ledger_consume_active "$WD/x-$_xn-m" "resumer" "2026-11-06T20:57:07Z" "$_w_a" 2>/dev/null || r1=$?
           r2=0; kt_ss_ledger_consume_active "$WD/x-$_xn-k" "resumer" "2026-11-06T20:57:07Z" "$_w_a" 2>/dev/null || r2=$?
           printf '%s %s' "$r1" "$r2" ) )
  if [ "$_xr" = "2 0" ] && cmp -s "$WD/x-$_xn-m/before.md" "$WD/x-$_xn-m/SESSION.md" \
     && grep -q '^### old-sid · .*consumed' "$WD/x-$_xn-k/SESSION.md"; then
    ok "X $_xd: mismatch refused untouched, match consumed"
  else
    bad "X $_xd" "exit codes '$_xr' (want '2 0'), or the mismatched file changed, or the match was not consumed"
  fi
done
[ "$_X_SEEN" -eq 4 ] && ok "X coverage: all 4 carrying ports exercised" \
  || bad "X coverage" "only $_X_SEEN of 4 port libs found"

# --- Y: the ledger takes no free text from a model command (2.58.0) ----------------------------
# /handoff and /wrapup used to tell the model to run
#   kt_ss_ledger_add "<root>" "<sid>" "<at>" "<focus>" "<next>" "<the stored prompt>"
# A stored prompt routinely carries backtick code spans and `$`, and inside double quotes the shell
# EXECUTES them -- code execution from a handoff body. Now the demote is code-only
# (kt_ss_ledger_demote_active reads every value from the file) and the self-demote reads its free
# text from a file the model wrote with its file-write tool (kt_ss_ledger_add_file).
# Every arm runs against EVERY port's lib, in a subshell, so a port that lacks a function or behaves
# differently goes red here, not only in block N's cksum.
#   Y1 a hostile prompt is demoted byte-identical, nothing executes, the token's sid/at win over a
#      disagreeing front matter, and the active slot is NOT cleared (the skill rewrites it)
#   Y2 nothing live (empty fence / in-progress marker / no file) -> exit 1, byte-identical
#   Y3 kt_ss_ledger_add neutered -> demote_active AND consume_active exit 3, byte-identical
#   Y4 hook-artifact annotation, two-sided: tokenless + front-matter sid == caller sid is annotated;
#      a different caller sid, or a token-bearing prompt, is not
#   Y5 add_file stores a hostile body verbatim with its focus/next, nothing executes
#   Y6 add_file refuses a symlinked entry file      Y7 add_file refuses bad headers / args
#   Y8 add_file verifies its write landed (exit 3 when kt_ss_ledger_add is neutered)
#   Y3b/Y8b a header QUOTED inside the active slot is not proof of landing (fix round 1)
#   Y3c the same prompt with the REAL add lands on the first try (fix round 2)
#   Y9 an idempotent re-run (RC-3 byte-identical skip) still reads as landed (fix round 1)
YD="$TMP/y"
_y_tok='aria-handoff: proj-a/tok-sid@2026-11-01T00:00:00Z'
_y_hdr_tok='### tok-sid · 2026-11-01T00:00:00Z · handoff · unconsumed'
_y_annot='⚠ sid is a post-edit-check.sh HOOK ARTIFACT, not attribution — '
_y_hostile() {  # $1 marker path -> a prompt body a shell would execute if it were ever re-composed
  printf '%s\n' '```' "$_y_tok" \
    'run `date` then $(touch '"$1"') and ${HOME} and $HOME' \
    "it's \"quoted\" both ways" 'ARIA_TASK' '## a column-0 heading inside the fence' \
    'focus: a decoy header line' '```'
}
_y_slot() {  # $1 dir, $2 prompt file -- the front matter DISAGREES with the token on purpose
  mkdir -p "$1"; : > "$1/CLAUDE.md"
  { printf -- '---\nlastEvent: handoff\nat: 2026-11-02T00:00:00Z\ncurrentFocus: fm focus line\nnextAction: fm next line\nsessionId: fm-sid\n---\n\n## Where we left off\n\nY-BODY\n\n## Next session prompt\n\n'
    cat "$2"
    printf '\n## Pending handoffs\n'
  } > "$1/SESSION.md"
  cp "$1/SESSION.md" "$1/before.md"
}
# (2.58.0 Task 2) THE REFERENCE DECODER -- test-only, never shipped (spec §3: no code path returns a stored
# body). Removes ONE leading backslash from a line matching ^\\+(## |### |```|<!-- aria:entry-end -->$),
# the inverse of _kt_ss_entry_block's encode. Arms AA..AA5 prove decode(encode(x)) == x.
_ss_ref_decode() { LC_ALL=C awk '/^\\+(## |### |```|<!-- aria:entry-end -->$)/ { $0 = substr($0, 2) } { print }'; }
_y_stored() {  # $1 file, $2 exact header line -> that entry's stored prompt, DECODED (the original text)
  awk -v h="$2" '$0 == h { f = 1; next } f && $0 == "- prompt:" { p = 1; next }
                 p && $0 == "<!-- aria:entry-end -->" { exit } p { print }' "$1" | _ss_ref_decode
}
_y_field() {  # $1 file, $2 exact header line, $3 key -> the value of that entry's "- key: " line
  awk -v h="$2" -v k="- $3: " '$0 == h { f = 1; next }
                               f && index($0, k) == 1 { print substr($0, length(k) + 1); exit }' "$1"
}
_y_active() { awk '/^## Pending handoffs/ { exit } { print }' "$1"; }
_y_arms() {  # $1 tag. The caller has sourced ONE port's lib into this subshell.
  b="$YD/$1"; mkdir -p "$b"

  _y_hostile "$b/M1" > "$b/p1"; _y_slot "$b/d1" "$b/p1"
  r=0; o=$(kt_ss_ledger_demote_active "$b/d1" 2>/dev/null) || r=$?
  _y_stored "$b/d1/SESSION.md" "$_y_hdr_tok" > "$b/s1"
  _y_active "$b/d1/SESSION.md" > "$b/a1"; _y_active "$b/d1/before.md" > "$b/a1b"
  if [ "$r" -eq 0 ] && [ "$o" = "tok-sid@2026-11-01T00:00:00Z" ] && cmp -s "$b/p1" "$b/s1" \
     && [ "$(_y_field "$b/d1/SESSION.md" "$_y_hdr_tok" focus)" = "fm focus line" ] \
     && [ "$(_y_field "$b/d1/SESSION.md" "$_y_hdr_tok" next)" = "fm next line" ] \
     && ! grep -q '^### fm-sid' "$b/d1/SESSION.md" && [ ! -e "$b/M1" ] && cmp -s "$b/a1" "$b/a1b"; then
    echo "OK Y1 demote_active_moves_prompt_verbatim"
  else
    echo "BAD Y1 demote_active_moves_prompt_verbatim -- rc=$r out='$o' stored=$(cmp -s "$b/p1" "$b/s1" && echo same || echo DIFFERS) marker=$([ -e "$b/M1" ] && echo CREATED || echo none) fm-sid-header=$(grep -c '^### fm-sid' "$b/d1/SESSION.md" || true) active=$(cmp -s "$b/a1" "$b/a1b" && echo kept || echo CHANGED)"
  fi

  mkdir -p "$b/d2a" "$b/d2b" "$b/d2c"
  printf -- '---\nlastEvent: wrapup\nat: 2026-11-02T00:00:00Z\nsessionId: s\n---\n\n## Next session prompt\n\n```\n```\n\n## Pending handoffs\n' > "$b/d2a/SESSION.md"
  printf -- '---\nlastEvent: in-progress\nat: 2026-11-02T00:00:00Z\nsessionId: s\n---\n\n## Next session prompt\n\n```\n(session in progress)\n```\n' > "$b/d2b/SESSION.md"
  cp "$b/d2a/SESSION.md" "$b/d2a/before.md"; cp "$b/d2b/SESSION.md" "$b/d2b/before.md"
  r1=0; o1=$(kt_ss_ledger_demote_active "$b/d2a" 2>/dev/null) || r1=$?
  r2=0; o2=$(kt_ss_ledger_demote_active "$b/d2b" 2>/dev/null) || r2=$?
  r3=0; o3=$(kt_ss_ledger_demote_active "$b/d2c" 2>/dev/null) || r3=$?
  if [ "$r1$r2$r3" = "111" ] && [ -z "$o1$o2$o3" ] && cmp -s "$b/d2a/before.md" "$b/d2a/SESSION.md" \
     && cmp -s "$b/d2b/before.md" "$b/d2b/SESSION.md" && [ ! -e "$b/d2c/SESSION.md" ]; then
    echo "OK Y2 demote_active_nothing_live"
  else
    echo "BAD Y2 demote_active_nothing_live -- exits=$r1$r2$r3 (want 111) out='$o1$o2$o3', or a file changed/was created"
  fi

  _y_hostile "$b/M3" > "$b/p3"; _y_slot "$b/d3" "$b/p3"; _y_slot "$b/d3c" "$b/p3"
  rr=$( ( kt_ss_ledger_add() { return 0; }
          x=0; kt_ss_ledger_demote_active "$b/d3" >/dev/null 2>&1 || x=$?
          y=0; kt_ss_ledger_consume_active "$b/d3c" resumer 2026-11-03T00:00:00Z "$_y_tok" >/dev/null 2>&1 || y=$?
          printf '%s %s' "$x" "$y" ) ) || true
  if [ "$rr" = "3 3" ] && cmp -s "$b/d3/before.md" "$b/d3/SESSION.md" && cmp -s "$b/d3c/before.md" "$b/d3c/SESSION.md"; then
    echo "OK Y3 demote_active_verifies_landed (and consume_active through it)"
  else
    echo "BAD Y3 demote_active_verifies_landed -- exits '$rr' (want '3 3'), or a file changed"
  fi

  # Y3b (fix round 1) -- the prompt quotes its OWN entry header at column 0, inside the active slot.
  # A landing check that accepts that header ANYWHERE in the file reads it as proof the demote landed,
  # and consume_active then clears the slot: the prompt is gone from both places.
  { printf '%s\n' '```' "$_y_tok" 'Y3b body'; printf '%s\n' "$_y_hdr_tok" '```'; } > "$b/p3b"
  _y_slot "$b/d3b" "$b/p3b"; _y_slot "$b/d3bc" "$b/p3b"
  rr=$( ( kt_ss_ledger_add() { return 0; }
          x=0; kt_ss_ledger_demote_active "$b/d3b" >/dev/null 2>&1 || x=$?
          y=0; kt_ss_ledger_consume_active "$b/d3bc" resumer 2026-11-03T00:00:00Z "$_y_tok" >/dev/null 2>&1 || y=$?
          printf '%s %s' "$x" "$y" ) ) || true
  if [ "$rr" = "3 3" ] && cmp -s "$b/d3b/before.md" "$b/d3b/SESSION.md" && cmp -s "$b/d3bc/before.md" "$b/d3bc/SESSION.md"; then
    echo "OK Y3b demote_active_landing_ignores_a_quoted_header"
  else
    echo "BAD Y3b demote_active_landing_ignores_a_quoted_header -- exits '$rr' (want '3 3'), slot $(cmp -s "$b/d3bc/before.md" "$b/d3bc/SESSION.md" && echo kept || echo CHANGED)"
  fi

  # Y3c (fix round 2) -- the same self-quoting prompt with the REAL add. Storing it adds TWO lines that
  # start with the header prefix (the entry's header and the quoted line in its body), so a "+1" rule
  # reported a landed demote as not landed (exit 3) and only the retry, via the level-count allowance,
  # returned 0. It must succeed on the first try, with exactly one stored entry.
  _y_slot "$b/d3c" "$b/p3b"; _y_slot "$b/d3cc" "$b/p3b"
  x=0; kt_ss_ledger_demote_active "$b/d3c" >/dev/null 2>&1 || x=$?
  y=0; kt_ss_ledger_consume_active "$b/d3cc" resumer 2026-11-03T00:00:00Z "$_y_tok" >/dev/null 2>&1 || y=$?
  e1=$(grep -c '^<!-- aria:entry-end -->$' "$b/d3c/SESSION.md" || true)
  e2=$(grep -c '^<!-- aria:entry-end -->$' "$b/d3cc/SESSION.md" || true)
  a2=$(awk '/^## Next session prompt/{a=1;next} /^## /{a=0} a&&NF' "$b/d3cc/SESSION.md")
  if [ "$x$y" = "00" ] && [ "$e1" -eq 1 ] && [ "$e2" -eq 1 ] && [ -z "$a2" ]; then
    echo "OK Y3c self_quoting_prompt_lands_first_try"
  else
    echo "BAD Y3c self_quoting_prompt_lands_first_try -- exits $x$y (want 00), stored entries $e1/$e2 (want 1/1), consume slot $([ -z "$a2" ] && echo cleared || echo NOT-cleared)"
  fi

  printf '%s\n' '```' 'Y4 tokenless prompt' '```' > "$b/p4"
  printf '%s\n' '```' "$_y_tok" 'Y4 token prompt' '```' > "$b/p4t"
  _y_slot "$b/d4a" "$b/p4"; _y_slot "$b/d4b" "$b/p4"; _y_slot "$b/d4c" "$b/p4t"
  ra=0; kt_ss_ledger_demote_active "$b/d4a" fm-sid >/dev/null 2>&1 || ra=$?
  rb=0; kt_ss_ledger_demote_active "$b/d4b" other-sid >/dev/null 2>&1 || rb=$?
  rc=0; kt_ss_ledger_demote_active "$b/d4c" tok-sid >/dev/null 2>&1 || rc=$?
  hf='### fm-sid · 2026-11-02T00:00:00Z · handoff · unconsumed'
  fa=$(_y_field "$b/d4a/SESSION.md" "$hf" focus); fb=$(_y_field "$b/d4b/SESSION.md" "$hf" focus)
  fc=$(_y_field "$b/d4c/SESSION.md" "$_y_hdr_tok" focus)
  if [ "$ra$rb$rc" = "000" ] && [ "$fa" = "${_y_annot}fm focus line" ] && [ "$fb" = "fm focus line" ] && [ "$fc" = "fm focus line" ]; then
    echo "OK Y4 hook-artifact annotation: annotated only for a tokenless prompt under the caller's own sid"
  else
    echo "BAD Y4 hook-artifact annotation -- exits=$ra$rb$rc focus a='$fa' b='$fb' c='$fc'"
  fi

  _y_hostile "$b/M5" > "$b/p5"; _y_hostile "$b/M5x" > "$b/p5x"; _y_slot "$b/d5" "$b/p5x"
  { printf 'focus: f one line\nnext: n one line\nprompt:\n'; cat "$b/p5"; } > "$b/e5"
  r=0; kt_ss_ledger_add_file "$b/d5" my-sid 2026-11-03T00:00:00Z "$b/e5" >/dev/null 2>&1 || r=$?
  h5='### my-sid · 2026-11-03T00:00:00Z · handoff · unconsumed'
  _y_stored "$b/d5/SESSION.md" "$h5" > "$b/s5"
  _y_active "$b/d5/SESSION.md" > "$b/a5"; _y_active "$b/d5/before.md" > "$b/a5b"
  if [ "$r" -eq 0 ] && cmp -s "$b/p5" "$b/s5" && [ "$(_y_field "$b/d5/SESSION.md" "$h5" focus)" = "f one line" ] \
     && [ "$(_y_field "$b/d5/SESSION.md" "$h5" next)" = "n one line" ] && [ ! -e "$b/M5" ] && cmp -s "$b/a5" "$b/a5b"; then
    echo "OK Y5 add_file_parses_and_stores"
  else
    echo "BAD Y5 add_file_parses_and_stores -- rc=$r stored=$(cmp -s "$b/p5" "$b/s5" && echo same || echo DIFFERS) marker=$([ -e "$b/M5" ] && echo CREATED || echo none)"
  fi

  _y_slot "$b/d6" "$b/p5x"; ln -s "$b/e5" "$b/e6"
  r=0; kt_ss_ledger_add_file "$b/d6" my-sid 2026-11-03T00:00:00Z "$b/e6" >/dev/null 2>&1 || r=$?
  if [ "$r" -ne 0 ] && cmp -s "$b/d6/before.md" "$b/d6/SESSION.md"; then echo "OK Y6 add_file_refuses_symlink"
  else echo "BAD Y6 add_file_refuses_symlink -- rc=$r, or the ledger changed"; fi

  _y_slot "$b/d7" "$b/p5x"
  printf 'focus: f\nnext: n\nbody without the prompt header\n' > "$b/e7a"
  printf 'next: n\nfocus: f\nprompt:\nbody\n' > "$b/e7b"
  ra=0; kt_ss_ledger_add_file "$b/d7" my-sid 2026-11-03T00:00:00Z "$b/e7a" >/dev/null 2>&1 || ra=$?
  rb=0; kt_ss_ledger_add_file "$b/d7" my-sid 2026-11-03T00:00:00Z "$b/e7b" >/dev/null 2>&1 || rb=$?
  rc=0; kt_ss_ledger_add_file "$b/d7" my-sid 2026-11-03T00:00:00Z "$b/e7-missing" >/dev/null 2>&1 || rc=$?
  rd=0; kt_ss_ledger_add_file "$b/d7" "" 2026-11-03T00:00:00Z "$b/e5" >/dev/null 2>&1 || rd=$?
  if [ "$ra" -ne 0 ] && [ "$rb" -ne 0 ] && [ "$rc" -ne 0 ] && [ "$rd" -ne 0 ] && cmp -s "$b/d7/before.md" "$b/d7/SESSION.md"; then
    echo "OK Y7 add_file_refuses_missing_headers (and a missing file, and an empty sid)"
  else
    echo "BAD Y7 add_file_refuses_missing_headers -- exits $ra/$rb/$rc/$rd (want all non-zero), or the ledger changed"
  fi

  _y_slot "$b/d8" "$b/p5x"
  rr=$( ( kt_ss_ledger_add() { return 0; }
          x=0; kt_ss_ledger_add_file "$b/d8" my-sid 2026-11-03T00:00:00Z "$b/e5" >/dev/null 2>&1 || x=$?
          printf '%s' "$x" ) ) || true
  if [ "$rr" = "3" ] && cmp -s "$b/d8/before.md" "$b/d8/SESSION.md"; then echo "OK Y8 add_file_verifies_landed"
  else echo "BAD Y8 add_file_verifies_landed -- exit '$rr' (want 3), or the ledger changed"; fi

  # Y8b (fix round 1) -- same, for add_file: the active slot already shows the header it would write.
  printf '%s\n' '```' 'incumbent prompt quoting' '### my-sid · 2026-11-03T00:00:00Z · handoff · unconsumed' '```' > "$b/p8b"
  _y_slot "$b/d8b" "$b/p8b"
  rr=$( ( kt_ss_ledger_add() { return 0; }
          x=0; kt_ss_ledger_add_file "$b/d8b" my-sid 2026-11-03T00:00:00Z "$b/e5" >/dev/null 2>&1 || x=$?
          printf '%s' "$x" ) ) || true
  if [ "$rr" = "3" ] && cmp -s "$b/d8b/before.md" "$b/d8b/SESSION.md"; then echo "OK Y8b add_file_landing_ignores_a_quoted_header"
  else echo "BAD Y8b add_file_landing_ignores_a_quoted_header -- exit '$rr' (want 3), or the ledger changed"; fi

  # Y9 (fix round 1) -- an idempotent RE-RUN is not a failed write. kt_ss_ledger_add skips a byte-identical
  # block by design (RC-3), so the stored count stays level; that must still read as landed, or a
  # /handoff whose rewrite was aborted, or a consume_active retried after exit 2, is blocked forever.
  _y_hostile "$b/M9" > "$b/p9"; _y_slot "$b/d9" "$b/p9"
  r1=0; kt_ss_ledger_demote_active "$b/d9" >/dev/null 2>&1 || r1=$?
  r2=0; kt_ss_ledger_demote_active "$b/d9" >/dev/null 2>&1 || r2=$?
  r3=0; kt_ss_ledger_add_file "$b/d9" my-sid 2026-11-03T00:00:00Z "$b/e5" >/dev/null 2>&1 || r3=$?
  r4=0; kt_ss_ledger_add_file "$b/d9" my-sid 2026-11-03T00:00:00Z "$b/e5" >/dev/null 2>&1 || r4=$?
  n1=$(awk -v h="$_y_hdr_tok" '$0 == h { n++ } END { print n + 0 }' "$b/d9/SESSION.md")
  n2=$(grep -c '^### my-sid · 2026-11-03T00:00:00Z · ' "$b/d9/SESSION.md" || true)
  if [ "$r1$r2$r3$r4" = "0000" ] && [ "$n1" -eq 1 ] && [ "$n2" -eq 1 ]; then echo "OK Y9 idempotent_rerun_reads_as_landed"
  else echo "BAD Y9 idempotent_rerun_reads_as_landed -- exits $r1$r2$r3$r4 (want 0000), stored headers $n1/$n2 (want 1/1)"; fi
}
_Y_SEEN=0
for _yd in plugin-claude-code/scripts plugin-antigravity/bin plugin-cursor-template/scripts/aria plugin-openai-codex/bin; do
  _yf="$REPO_ROOT/$_yd/lib-session-state.sh"
  [ -f "$_yf" ] || { bad "Y $_yd" "lib-session-state.sh missing -- a guard with no subject"; continue; }
  _Y_SEEN=$((_Y_SEEN + 1))
  _yout=$( ( . "$_yf"; _y_arms "$(printf '%s' "$_yd" | tr '/' '_')" ) 2>&1 ) || true
  while IFS= read -r _yl; do
    case "$_yl" in
      "OK "*)  ok "$_yd: ${_yl#OK }" ;;
      "BAD "*) _yn=${_yl#BAD }; bad "$_yd: ${_yn%% -- *}" "${_yn#* -- }" ;;
    esac
  done <<YOUT
$_yout
YOUT
  _yn=$(printf '%s\n' "$_yout" | grep -c '^OK ' || true)
  [ "$_yn" -eq 12 ] || bad "Y coverage $_yd" "only $_yn of 12 arms passed -- see the lines above"
done
[ "$_Y_SEEN" -eq 4 ] && ok "Y coverage: all 4 carrying ports exercised" \
  || bad "Y coverage" "only $_Y_SEEN of 4 port libs found"

# --- Z: the resume token reaches the ledger through a FILE, never a shell argument (final fix wave) --
# The SESSION STATE directive used to tell the model to run
#   kt_ss_ledger_token_locate <root> <token>  /  kt_ss_ledger_consume_active <root> <by> <now> <token>
# with the token copied from the user's PASTED text -- third-party text composed into a shell command.
# The _file forms read the token from a file the model wrote with its file-write tool, refuse a link /
# non-regular / foreign file, check the token's shape in code, and call the old functions in-process.
#   Z1 a hostile token (shape-invalid: `$(…)` after the at) via file -> both refused (1), no marker,
#      no output, ledger byte-identical
#   Z2 a valid token via file gives exactly the old call's result (locate output; consume exit + file)
#   Z3 refused (1, untouched): a symlinked file, two lines, an empty file, a directory, a missing path,
#      a bare token without the `aria-handoff:` prefix
#   Z4 consume_active's own refusals pass through: a well-formed token naming a different prompt -> 2
#   Z5 (F6) kt_ss_ledger_add_verified builds its compare block in $TMPDIR, never beside SESSION.md
ZD="$TMP/z"
_z_arms() {  # $1 tag. The caller has sourced ONE port's lib into this subshell.
  b="$ZD/$1"; mkdir -p "$b"
  printf '%s\n' '```' "$_y_tok" 'Z resume body' '```' > "$b/p"

  _y_slot "$b/d1" "$b/p"
  printf 'aria-handoff: proj-a/tok-sid@2026-11-01T00:00:00Z$(touch %s)\n' "$b/MZ1" > "$b/hostile"
  r1=0; o1=$(kt_ss_ledger_token_locate_file "$b/d1" "$b/hostile" 2>/dev/null) || r1=$?
  r2=0; o2=$(kt_ss_ledger_consume_active_file "$b/d1" resumer 2026-11-03T00:00:00Z "$b/hostile" 2>/dev/null) || r2=$?
  if [ "$r1$r2" = "11" ] && [ -z "$o1$o2" ] && [ ! -e "$b/MZ1" ] && cmp -s "$b/d1/before.md" "$b/d1/SESSION.md"; then
    echo "OK Z1 hostile_token_file_refused"
  else
    echo "BAD Z1 hostile_token_file_refused -- exits $r1$r2 (want 11) out='$o1$o2' marker=$([ -e "$b/MZ1" ] && echo CREATED || echo none)"
  fi

  _y_slot "$b/d2a" "$b/p"; _y_slot "$b/d2b" "$b/p"
  printf '%s\n' "$_y_tok" > "$b/tok"
  la=$(kt_ss_ledger_token_locate "$b/d2a" "$_y_tok" 2>/dev/null)
  lb=$(kt_ss_ledger_token_locate_file "$b/d2a" "$b/tok" 2>/dev/null)
  ca=0; kt_ss_ledger_consume_active "$b/d2a" resumer 2026-11-03T00:00:00Z "$_y_tok" >/dev/null 2>&1 || ca=$?
  cb=0; kt_ss_ledger_consume_active_file "$b/d2b" resumer 2026-11-03T00:00:00Z "$b/tok" >/dev/null 2>&1 || cb=$?
  if [ -n "$la" ] && [ "$la" = "$lb" ] && [ "$ca$cb" = "00" ] && cmp -s "$b/d2a/SESSION.md" "$b/d2b/SESSION.md"; then
    echo "OK Z2 token_file_equals_the_old_call"
  else
    echo "BAD Z2 token_file_equals_the_old_call -- locate '$la' vs '$lb', consume exits $ca$cb (want 00), files $(cmp -s "$b/d2a/SESSION.md" "$b/d2b/SESSION.md" && echo same || echo DIFFER)"
  fi

  _y_slot "$b/d3" "$b/p"
  ln -s "$b/tok" "$b/tok-link"
  printf '%s\nsecond line\n' "$_y_tok" > "$b/tok-2"; : > "$b/tok-empty"; mkdir -p "$b/tok-dir"
  printf 'proj-a/tok-sid@2026-11-01T00:00:00Z\n' > "$b/tok-bare"
  zr=""
  for f in "$b/tok-link" "$b/tok-2" "$b/tok-empty" "$b/tok-dir" "$b/tok-missing" "$b/tok-bare"; do
    x=0; xo=$(kt_ss_ledger_token_locate_file "$b/d3" "$f" 2>/dev/null) || x=$?
    y=0; kt_ss_ledger_consume_active_file "$b/d3" resumer 2026-11-03T00:00:00Z "$f" >/dev/null 2>&1 || y=$?
    [ -n "$xo" ] && x="${x}+out"
    zr="$zr$x$y "
  done
  if [ "$zr" = "11 11 11 11 11 11 " ] && cmp -s "$b/d3/before.md" "$b/d3/SESSION.md"; then
    echo "OK Z3 bad_token_files_refused"
  else
    echo "BAD Z3 bad_token_files_refused -- exits '$zr' (want six '11'), or the ledger changed"
  fi

  _y_slot "$b/d4" "$b/p"
  printf 'aria-handoff: proj-a/other-sid@2026-11-01T00:00:00Z\n' > "$b/tok-other"
  r=0; kt_ss_ledger_consume_active_file "$b/d4" resumer 2026-11-03T00:00:00Z "$b/tok-other" >/dev/null 2>"$b/e4" || r=$?
  if [ "$r" -eq 2 ] && cmp -s "$b/d4/before.md" "$b/d4/SESSION.md" && grep -q 'kt_ss_ledger_token_locate_file' "$b/e4"; then
    echo "OK Z4 consume_refusal_passes_through"
  else
    echo "BAD Z4 consume_refusal_passes_through -- exit $r (want 2), or the ledger changed, or stderr does not name the _file re-locate"
  fi

  _y_slot "$b/d5" "$b/p"; mkdir -p "$b/td5"
  { printf 'focus: f\nnext: n\nprompt:\n'; cat "$b/p"; } > "$b/e5"
  ( rm() { :; }; TMPDIR="$b/td5"; export TMPDIR
    kt_ss_ledger_add_file "$b/d5" my-sid 2026-11-03T00:00:00Z "$b/e5" >/dev/null 2>&1 ) || true
  nroot=$(ls -a "$b/d5" | grep -c 'vblk' || true)
  ntmp=$(ls -a "$b/td5" | grep -c 'vblk' || true)
  if [ "$nroot" -eq 0 ] && [ "$ntmp" -ge 1 ]; then
    echo "OK Z5 verify_block_lives_in_tmpdir"
  else
    echo "BAD Z5 verify_block_lives_in_tmpdir -- vblk files beside SESSION.md: $nroot (want 0), in TMPDIR: $ntmp (want >=1, the rm-stub control)"
  fi
}
_Z_SEEN=0
for _zd in plugin-claude-code/scripts plugin-antigravity/bin plugin-cursor-template/scripts/aria plugin-openai-codex/bin; do
  _zf="$REPO_ROOT/$_zd/lib-session-state.sh"
  [ -f "$_zf" ] || { bad "Z $_zd" "lib-session-state.sh missing -- a guard with no subject"; continue; }
  _Z_SEEN=$((_Z_SEEN + 1))
  # The suite sourced the CANONICAL lib at the top, so its new helpers are already defined here: drop
  # them first, or a port that lacks them would borrow canonical's and pass (measured: it did).
  _zout=$( ( unset -f _kt_ss_token_from_file kt_ss_ledger_token_locate_file kt_ss_ledger_consume_active_file
             . "$_zf"; _z_arms "$(printf '%s' "$_zd" | tr '/' '_')" ) 2>&1 ) || true
  while IFS= read -r _zl; do
    case "$_zl" in
      "OK "*)  ok "$_zd: ${_zl#OK }" ;;
      "BAD "*) _zn=${_zl#BAD }; bad "$_zd: ${_zn%% -- *}" "${_zn#* -- }" ;;
    esac
  done <<ZOUT
$_zout
ZOUT
  _zn=$(printf '%s\n' "$_zout" | grep -c '^OK ' || true)
  [ "$_zn" -eq 5 ] || bad "Z coverage $_zd" "only $_zn of 5 arms passed -- see the lines above"
done
[ "$_Z_SEEN" -eq 4 ] && ok "Z coverage: all 4 carrying ports exercised" \
  || bad "Z coverage" "only $_Z_SEEN of 4 port libs found"

# --- AH: NON-REGRESSION GUARDS written BEFORE the 2.58.0 behaviour changes (Task 0) --------------------
# ⚠ These are GUARDS, not fix tests: every arm is EXPECTED GREEN on the untouched tree and is meant to
# STAY green through the later tasks. A red AH arm after a later task means that task changed something
# it was not supposed to.
#
# AH0  positive control: the fixture glob found >= 9 files and every recorded .out is non-empty — a
#      guard over zero files is a gate with no subject.
# AH1  each reader's output on a scratch copy of every vendored contract fixture equals the .out
#      recorded with the canonical lib at 1260af0, byte for byte (cmp).
# AH2  the cursor and codex SESSION STATE directive line, with every AH_EMITTER_SENTENCE removed, has
#      the cksum measured at 3e44761 — so Task 5 may APPEND the sentence and nothing else may move.
#      Removal is by awk index(), never a regex: the sentence holds `.` and `;`.
AH_EMITTER_SENTENCE='A stored prompt line that begins with one backslash before ##, ###, a code fence or the entry-end terminator line is escaped; read it without that one backslash. '
_ah_dump() {
  printf '== kt_ss_ledger_candidates\n';   kt_ss_ledger_candidates "$1"
  printf '== kt_ss_read_live_prompt\n';    kt_ss_read_live_prompt "$1"
  printf '== kt_ss_read_active_token\n';   kt_ss_read_active_token "$1"
  printf '== kt_ss_read_active_sid\n';     kt_ss_read_active_sid "$1"
  printf '== kt_ss_read_active_at\n';      kt_ss_read_active_at "$1"
  printf '== kt_ss_ledger_token_locate\n'; kt_ss_ledger_token_locate "$1" 'aria-handoff: proj-a/none@none'
}
_AH_FIX="$REPO_ROOT/tests/fixtures/session-contract-vendored"
_AH_BASE="$REPO_ROOT/tests/fixtures/session-reader-baseline"
_AH_N=0; _AH_EMPTY=0
for _ahf in "$_AH_FIX"/*.SESSION.md; do
  [ -f "$_ahf" ] || continue
  _AH_N=$((_AH_N + 1))
  _ahb=$(basename "$_ahf" .SESSION.md)
  [ -s "$_AH_BASE/$_ahb.out" ] || _AH_EMPTY=$((_AH_EMPTY + 1))
  mkdir -p "$TMP/ah/$_ahb"; cp "$_ahf" "$TMP/ah/$_ahb/SESSION.md"
  _ah_dump "$TMP/ah/$_ahb" > "$TMP/ah/$_ahb.got" 2>&1 || true
  if cmp -s "$TMP/ah/$_ahb.got" "$_AH_BASE/$_ahb.out"; then
    ok "AH1 $_ahb: reader output equals the recorded baseline"
  else
    bad "AH1 $_ahb" "reader output differs from tests/fixtures/session-reader-baseline/$_ahb.out"
  fi
done
if [ "$_AH_N" -ge 9 ] && [ "$_AH_EMPTY" -eq 0 ]; then
  ok "AH0 positive control: $_AH_N fixtures found, every baseline .out non-empty"
else
  bad "AH0 positive control" "fixtures found: $_AH_N (want >= 9), empty baselines: $_AH_EMPTY (want 0)"
fi

# cksum literals measured at 3e44761 (git show <rev>:<file> | grep 'SESSION STATE —' | cksum):
#   cursor 399152793 (4109 bytes)   codex 1316696697 (4057 bytes)
_ah_directive_sum() {
  [ -f "$1" ] || { printf 'MISSING'; return 0; }
  grep 'SESSION STATE —' "$1" \
    | awk -v s="$AH_EMITTER_SENTENCE" '{ out = ""; while ((i = index($0, s)) > 0) { out = out substr($0, 1, i - 1); $0 = substr($0, i + length(s)) } print out $0 }' \
    | cksum | awk '{print $1}'
}
for _ahp in "cursor:plugin-cursor-template/scripts/aria:399152793" "codex:plugin-openai-codex/bin:1316696697"; do
  _ahn=${_ahp%%:*}; _ahr=${_ahp#*:}; _ahd=${_ahr%:*}; _ahw=${_ahr##*:}
  _ahg=$(_ah_directive_sum "$REPO_ROOT/$_ahd/session-start-check.sh")
  if [ "$_ahg" = "$_ahw" ]; then
    ok "AH2 $_ahn SESSION STATE directive (sentence removed) cksum is the 3e44761 value $_ahw"
  else
    bad "AH2 $_ahn" "directive cksum $_ahg, want $_ahw (3e44761) — the SESSION STATE string changed beyond AH_EMITTER_SENTENCE"
  fi
done

# AH3  GUARD (non-regression, Task 1a): AH1 pins token_locate only on its NO-MATCH path, because no
#      vendored fixture carries an `aria-handoff:` token. This pins the MATCHED paths -- active,
#      pending, terminal, archived -- plus candidates, read_active_token and read_live_prompt, on one
#      token-bearing fixture, against output recorded with the canonical lib at a0e4493 (before the
#      readers moved onto the region walker). Expected GREEN before and after; red = a reader changed.
_ah3_dump() {
  printf '== kt_ss_ledger_candidates\n'; kt_ss_ledger_candidates "$1"
  printf '== kt_ss_read_active_token\n'; kt_ss_read_active_token "$1"
  printf '== kt_ss_read_live_prompt\n'; kt_ss_read_live_prompt "$1"; printf '\n'
  for _ah3t in 'aria-handoff: proj-a/act-sid@2026-07-02T00:00:00Z' 'aria-handoff: proj-a/pend-sid@2026-06-30T00:00:00Z' \
               'aria-handoff: proj-a/done-sid@2026-06-29T00:00:00Z' 'aria-handoff: proj-b/arch-sid@2026-06-01T00:00:00Z' \
               'aria-handoff: proj-a/none@none'; do
    printf '== kt_ss_ledger_token_locate %s\n' "$_ah3t"; kt_ss_ledger_token_locate "$1" "$_ah3t"
  done
}
_AH3_DIR="$REPO_ROOT/tests/fixtures/session-reader-token"
mkdir -p "$TMP/ah3"; cp "$_AH3_DIR/token-match.SESSION.md" "$TMP/ah3/SESSION.md"
_ah3_dump "$TMP/ah3" > "$TMP/ah3.got" 2>&1 || true
if [ "$(grep -c '|' "$_AH3_DIR/baseline.out")" -ge 7 ] && cmp -s "$TMP/ah3.got" "$_AH3_DIR/baseline.out"; then
  ok "AH3 GUARD: matched-token reader output equals the a0e4493 baseline (active, pending, terminal, archived)"
else
  bad "AH3" "matched-token reader output differs from tests/fixtures/session-reader-token/baseline.out (or the baseline holds < 7 rows)"
fi

# --- AG: the readers AND the writers AGREE with the region walker (2.58.0 Task 1a + 1b) ----------------
# One hostile fixture: fenced and unfenced structural lines in ACTIVE, OTHER and inside entries.
# AG(1) the lines kt_ss_read_live_prompt returns == the walker's ACTIVE lines (blank edges trimmed the
#       same way), and kt_ss_read_active_token == the first `aria-handoff:` line in the walker's ACTIVE;
#       and (Task 1b) kt_ss_ledger_prune leaves every walker ACTIVE line untouched.
# AG(2) the pending rows kt_ss_ledger_candidates prints == the walker's LEDGER entry_header lines
#       carrying a word-bounded `unconsumed`; and for every `mk-*` marker line inside an entry,
#       kt_ss_ledger_token_locate attributes it to the entry the walker says owns it (R_ENTRY).
#       (Task 1b, carried (ii)) p4 carries exactly TWO ` · ` and IS an entry header; the p5 line carries
#       exactly ONE and is NOT -- it is body of p4. Together they pin kt_is_entry_header's `n >= 2`.
# AG(3) (Task 1b) mark_consumed / mark_superseded on a sid present both as a real LEDGER header and as
#       fenced content inside another entry change exactly one line: the real header.
_AG="$TMP/ag"; mkdir -p "$_AG"
cat > "$_AG/SESSION.md" <<'AG_FIXTURE'
---
lastEvent: handoff
at: 2026-07-01T00:00:00Z
sessionId: fm-sid
---

## Notes

### n1 · 2026-01-01T00:00:00Z · handoff · unconsumed
```
## Pending handoffs
### q1 · 2026-01-01T00:00:00Z · handoff · unconsumed
```

## Next session prompt

```
aria-handoff: proj-a/ag-act@2026-07-03T00:00:00Z
## Pending handoffs
### f1 · 2026-01-01T00:00:00Z · handoff · unconsumed
### f2 · 2026-01-01T00:00:00Z · handoff · consumed
<!-- aria:entry-end -->
```
### g1 · 2026-01-02T00:00:00Z · handoff · unconsumed
plain active line

## Pending handoffs

### p1 · 2026-06-01T00:00:00Z · handoff · unconsumed
- prompt:
mk-p1a
```
## Next session prompt
### inner · 2026-02-01T00:00:00Z · handoff · unconsumed
### p3 · 2026-06-04T00:00:00Z · handoff · unconsumed
mk-p1f
<!-- aria:entry-end -->
```
<!-- aria:entry-end -->

### p2 · 2026-06-02T00:00:00Z · handoff · consumed 2026-06-03T00:00:00Z by x
- prompt: mk-p2a
<!-- aria:entry-end -->

### p3 · 2026-06-04T00:00:00Z · handoff · unconsumed
- prompt: mk-p3a
### p3b · 2026-06-05T00:00:00Z · handoff · unconsumed
- prompt: mk-p3b
<!-- aria:entry-end -->

### p4 · 2026-06-06T00:00:00Z · unconsumed
- prompt: mk-p4a
### p5 · unconsumed
mk-p5a
<!-- aria:entry-end -->

## Archived sessions

### z1 · 2026-05-01T00:00:00Z · handoff · unconsumed
- prompt: mk-z1a
<!-- aria:entry-end -->
AG_FIXTURE
_ag_trim() { sed -e '/./,$!d' | sed -e ':a' -e '/^[[:space:]]*$/{$d;N;ba' -e '}'; }
_AG_WALK_ACTIVE=$(awk "$(_kt_ss_awk_regions)"'{ k = kt_region($0) } R_SEC == "ACTIVE" && k != "heading" { print }' "$_AG/SESSION.md" | _ag_trim)
_AG_LIVE=$(kt_ss_read_live_prompt "$_AG")
if [ -n "$_AG_LIVE" ] && [ "$_AG_LIVE" = "$_AG_WALK_ACTIVE" ] \
   && printf '%s\n' "$_AG_LIVE" | grep -q '^plain active line$' \
   && [ "$(printf '%s\n' "$_AG_LIVE" | grep -c '^```')" -eq 2 ]; then
  ok "AG(1) kt_ss_read_live_prompt returns exactly the walker's ACTIVE lines (fenced ## and ### kept as content)"
else
  bad "AG(1) read_live_prompt" "reader and walker disagree on the ACTIVE lines (or the positive controls failed)"
fi
_AG_WALK_TOK=$(awk "$(_kt_ss_awk_regions)"'{ k = kt_region($0) } R_SEC == "ACTIVE" && k != "heading" && /^aria-handoff:/ { l = $0; sub(/^aria-handoff:[[:space:]]*/, "", l); sub(/^[^\/]*\//, "", l); i = index(l, "@"); print substr(l, 1, i - 1) "|" substr(l, i + 1); exit }' "$_AG/SESSION.md")
_AG_TOK=$(kt_ss_read_active_token "$_AG")
if [ "$_AG_TOK" = "ag-act|2026-07-03T00:00:00Z" ] && [ "$_AG_TOK" = "$_AG_WALK_TOK" ]; then
  ok "AG(1) kt_ss_read_active_token == the walker's first ACTIVE token ($_AG_TOK)"
else
  bad "AG(1) read_active_token" "reader '$_AG_TOK' vs walker '$_AG_WALK_TOK' (want ag-act|2026-07-03T00:00:00Z)"
fi
# AG(1) prune clause (Task 1b): the fenced `### f2 · … · consumed` + terminator in ACTIVE are prompt
# content. A fence-blind prune reaped them (spec §1 F1).
_AG_WALK_ACTIVE_ALL=$(awk "$(_kt_ss_awk_regions)"'{ k = kt_region($0) } R_SEC == "ACTIVE" { print }' "$_AG/SESSION.md")
mkdir -p "$TMP/ag-pr"; cp "$_AG/SESSION.md" "$TMP/ag-pr/SESSION.md"
kt_ss_ledger_prune "$TMP/ag-pr"
_AG_PR_ACTIVE=$(awk "$(_kt_ss_awk_regions)"'{ k = kt_region($0) } R_SEC == "ACTIVE" { print }' "$TMP/ag-pr/SESSION.md")
if [ -n "$_AG_WALK_ACTIVE_ALL" ] && [ "$_AG_PR_ACTIVE" = "$_AG_WALK_ACTIVE_ALL" ] && ! grep -q '^### p2 ' "$TMP/ag-pr/SESSION.md"; then
  ok "AG(1) kt_ss_ledger_prune leaves every walker ACTIVE line untouched (and still reaps the consumed p2)"
else
  bad "AG(1) prune" "prune changed the walker's ACTIVE lines, or did not reap p2"
fi
_AG_WALK_HDR=$(awk "$(_kt_ss_awk_regions)"'{ k = kt_region($0) } k == "entry_header" && R_SEC == "LEDGER" && /(^|[^a-z])unconsumed([^a-z]|$)/ { n = split(substr($0, 5), f, " · "); print f[1] "|" f[2] "|unconsumed|pending" }' "$_AG/SESSION.md")
_AG_CAND=$(kt_ss_ledger_candidates "$_AG" | grep '|pending$')
if [ "$(printf '%s\n' "$_AG_CAND" | grep -c .)" -eq 4 ] && [ "$_AG_CAND" = "$_AG_WALK_HDR" ] \
   && printf '%s\n' "$_AG_CAND" | grep -q '^p4|2026-06-06T00:00:00Z|unconsumed|pending$' \
   && ! printf '%s\n' "$_AG_CAND" | grep -q '^p5|'; then
  ok "AG(2) kt_ss_ledger_candidates pending rows == the walker's LEDGER entry headers (p1, p3, p3b, p4; not p5)"
else
  bad "AG(2) candidates" "reader rows [$(printf '%s' "$_AG_CAND" | tr '\n' ' ')] vs walker [$(printf '%s' "$_AG_WALK_HDR" | tr '\n' ' ')] (want 4: p1 p3 p3b p4)"
fi
# Walker attribution of every mk-* marker: <marker> <sid>|<at>|<status>|<pending|archived>
_AG_WALK_MK=$(awk "$(_kt_ss_awk_regions)"'
  { k = kt_region($0) }
  k == "entry_header" { n = split(substr($0, 5), f, " · "); hs[FNR] = f[1] "|" f[2]
                        if ($0 ~ /(^|[^a-z])unconsumed([^a-z]|$)/) { st[FNR] = "unconsumed" } else { st[FNR] = "terminal" } }
  R_ENTRY > 0 && match($0, /mk-[a-z0-9]+/) {
    src = "pending"; if (R_SEC == "ARCH") src = "archived"
    print substr($0, RSTART, RLENGTH) " " hs[R_ENTRY] "|" st[R_ENTRY] "|" src
  }' "$_AG/SESSION.md")
_AG_MK_N=0; _AG_MK_BAD=""
for _agm in mk-p1a mk-p1f mk-p2a mk-p3a mk-p3b mk-p4a mk-p5a mk-z1a; do
  _agw=$(printf '%s\n' "$_AG_WALK_MK" | awk -v m="$_agm" '$1 == m { print $2; exit }')
  _agr=$(kt_ss_ledger_token_locate "$_AG" "$_agm")
  if [ -n "$_agw" ] && [ "$_agr" = "$_agw" ]; then _AG_MK_N=$((_AG_MK_N + 1)); else _AG_MK_BAD="$_AG_MK_BAD $_agm(reader=$_agr walker=$_agw)"; fi
done
_AG_P5=$(kt_ss_ledger_token_locate "$_AG" mk-p5a)
if [ "$_AG_MK_N" -eq 8 ] && [ "$_AG_P5" = "p4|2026-06-06T00:00:00Z|unconsumed|pending" ]; then
  ok "AG(2) kt_ss_ledger_token_locate attributes all 8 in-entry markers to the walker's owning entry (mk-p5a -> p4)"
else
  bad "AG(2) token_locate" "disagreement:$_AG_MK_BAD (mk-p5a -> '$_AG_P5', want p4)"
fi
# AG(3): p3's header exists for real in LEDGER AND as fenced content inside p1. Exactly one line may move.
_ag_diffn() { awk 'NR == FNR { a[FNR] = $0; n = FNR; next } { if (!(FNR in a) || a[FNR] != $0) d++; m = FNR } END { if (m != n) d += 1000; print d + 0 }' "$1" "$2"; }
_AG_P3LN=$(awk "$(_kt_ss_awk_regions)"'{ k = kt_region($0) } k == "entry_header" && R_SEC == "LEDGER" && index($0, "### p3 · ") == 1 { print FNR; exit }' "$_AG/SESSION.md")
for _agv in consumed superseded; do
  mkdir -p "$TMP/ag-m-$_agv"; cp "$_AG/SESSION.md" "$TMP/ag-m-$_agv/SESSION.md"
  "kt_ss_ledger_mark_$_agv" "$TMP/ag-m-$_agv" p3 2026-07-09T00:00:00Z ag3 2026-06-04T00:00:00Z
  _agd=$(_ag_diffn "$_AG/SESSION.md" "$TMP/ag-m-$_agv/SESSION.md")
  _agl=$(sed -n "${_AG_P3LN}p" "$TMP/ag-m-$_agv/SESSION.md")
  if [ "$_agd" -eq 1 ] && printf '%s\n' "$_agl" | grep -q '^### p3 · 2026-06-04T00:00:00Z · handoff · consumed 2026-07-09T00:00:00Z by ag3'; then
    ok "AG(3) kt_ss_ledger_mark_$_agv rewrites only the real LEDGER header, not its fenced copy (1 line changed)"
  else
    bad "AG(3) mark_$_agv" "$_agd line(s) changed (want 1: the real header at line $_AG_P3LN, now '$_agl')"
  fi
done

# --- AB..AF (2.58.0 Task 1b, spec §1 F1-F4): every WRITER acts only where the readers look ------------
_wk_lines() { awk "$(_kt_ss_awk_regions)""$1" "$2"; }
# Lines a walker says are a terminator or a fence line OUTSIDE any entry -- leaked structure.
_wk_orphans() { _wk_lines '{ k = kt_region($0) } R_ENTRY == 0 && R_SEC != "ACTIVE" && ($0 == "<!-- aria:entry-end -->" || $0 ~ /^```/) { n++ } END { print n + 0 }' "$1"; }

# AB (F1): a consumed-looking header quoted inside the fenced ACTIVE prompt is prompt content.
_AB="$TMP/ab"; mkdir -p "$_AB"
cat > "$_AB/SESSION.md" <<'AB_FIX'
---
lastEvent: handoff
at: 2026-07-01T00:00:00Z
sessionId: ab-fm
---

## Next session prompt

```
aria-handoff: proj-a/ab-act@2026-07-01T00:00:00Z
### f1 · 2026-01-01T00:00:00Z · handoff · consumed
ab-tail-1
ab-tail-2
```

## Pending handoffs

### ab-live · 2026-06-01T00:00:00Z · handoff · unconsumed
- prompt: ab-live-body
<!-- aria:entry-end -->
AB_FIX
_AB_ACT0=$(_wk_lines '{ k = kt_region($0) } R_SEC == "ACTIVE" { print }' "$_AB/SESSION.md")
_AB_C0=$(kt_ss_ledger_candidates "$_AB")
kt_ss_ledger_prune "$_AB"
_AB_ACT1=$(_wk_lines '{ k = kt_region($0) } R_SEC == "ACTIVE" { print }' "$_AB/SESSION.md")
_AB_C1=$(kt_ss_ledger_candidates "$_AB")
if [ "$_AB_ACT1" = "$_AB_ACT0" ] && printf '%s\n' "$_AB_ACT1" | grep -q '^ab-tail-2$'; then
  ok "AB prune leaves the fenced ACTIVE prompt byte-identical (quoted consumed header is content)"
else
  bad "AB prune ACTIVE" "the ACTIVE region changed under prune"
fi
if [ "$_AB_C1" = "$_AB_C0" ] && [ "$(printf '%s\n' "$_AB_C1" | grep -c .)" -eq 2 ]; then
  ok "AB candidates identical before/after prune (2 rows)"
else
  bad "AB candidates" "before [$(printf '%s' "$_AB_C0" | tr '\n' ' ')] after [$(printf '%s' "$_AB_C1" | tr '\n' ' ')]"
fi

# AC (F2): the same prompt also quotes a raw terminator; consume it, then prune.
_AC="$TMP/ac"; mkdir -p "$_AC"
cat > "$_AC/SESSION.md" <<'AC_FIX'
---
lastEvent: handoff
at: 2026-07-01T00:00:00Z
sessionId: ac-fm
---

## Next session prompt

```
aria-handoff: proj-a/ac-act@2026-07-01T00:00:00Z
### f1 · 2026-01-01T00:00:00Z · handoff · consumed
ac-tail-1
<!-- aria:entry-end -->
ac-tail-2
```

## Pending handoffs

### ac-live · 2026-06-01T00:00:00Z · handoff · unconsumed
- prompt: ac-live-body
<!-- aria:entry-end -->
AC_FIX
_ac_rc=0; kt_ss_ledger_consume_active "$_AC" acby 2026-07-02T00:00:00Z "aria-handoff: proj-a/ac-act@2026-07-01T00:00:00Z" 2>/dev/null || _ac_rc=$?
kt_ss_ledger_prune "$_AC"
_AC_C=$(kt_ss_ledger_candidates "$_AC")
_AC_OR=$(_wk_orphans "$_AC/SESSION.md")
if [ "$_ac_rc" -eq 0 ] && printf '%s\n' "$_AC_C" | grep -q '^ac-live|2026-06-01T00:00:00Z|unconsumed|pending$' \
   && [ "$(printf '%s\n' "$_AC_C" | grep -c .)" -eq 1 ] && [ "$_AC_OR" -eq 0 ] \
   && ! grep -q 'ac-tail-2' "$_AC/SESSION.md" && ! grep -q '^### ac-act ' "$_AC/SESSION.md"; then
  # (fix round 3) Under 1b alone the demoted prompt was stored raw -- a quoted header and terminator inside
  # a fence -- so the parity rule kept it as ambiguous. (Task 2) consume_active now writes through the
  # escaping builder, so the stored body holds no structural line and the consumed entry is REAPED whole;
  # the parity-rule retention is a pre-2.58.0 trade only. The brief's two assertions are unchanged.
  ok "AC consume+prune: the live pending entry is still the only candidate, nothing leaked (0 orphan terminators/fences), the new consumed entry reaped whole"
else
  bad "AC consume+prune" "rc=$_ac_rc candidates [$(printf '%s' "$_AC_C" | tr '\n' ' ')] orphans=$_AC_OR"
fi

# AD (F3): the active prompt QUOTES the anchor heading (fenced, indented, bold). The demote must land
# under the REAL heading. Both instruments are asserted: the walker count (which separates a heading
# from a quotation) and, since Task 2's write escape, a raw `grep -c '^## Pending handoffs$'` -- the
# quoted line is now stored as `\## Pending handoffs`, so raw grep also reads 1 (it read 2 before).
_AD="$TMP/ad"; mkdir -p "$_AD"
cat > "$_AD/SESSION.md" <<'AD_FIX'
---
lastEvent: handoff
at: 2026-07-01T00:00:00Z
sessionId: ad-fm
---

## Next session prompt

```
aria-handoff: proj-a/ad-act@2026-07-02T00:00:00Z
## Pending handoffs
  ## Pending handoffs
**## Pending handoffs**
ad-quote-tail
```

## Pending handoffs

### ad-live · 2026-06-01T00:00:00Z · handoff · unconsumed
- prompt: ad-live-body
<!-- aria:entry-end -->
AD_FIX
_ad_rc=0; kt_ss_ledger_consume_active "$_AD" adby 2026-07-03T00:00:00Z "aria-handoff: proj-a/ad-act@2026-07-02T00:00:00Z" 2>/dev/null || _ad_rc=$?
_AD_LOC=$(kt_ss_ledger_token_locate "$_AD" "aria-handoff: proj-a/ad-act@2026-07-02T00:00:00Z")
_AD_HDR=$(_wk_lines '{ k = kt_region($0) } k == "entry_header" && R_SEC == "LEDGER" && index($0, "### ad-act · 2026-07-02T00:00:00Z · handoff · consumed ") == 1 { n++ } END { print n + 0 }' "$_AD/SESSION.md")
_AD_H=$(_wk_lines '{ k = kt_region($0) } k == "heading" && R_SEC == "LEDGER" { n++ } END { print n + 0 }' "$_AD/SESSION.md")
_AD_OR=$(_wk_orphans "$_AD/SESSION.md")
_AD_RAW=$(grep -c '^## Pending handoffs$' "$_AD/SESSION.md" || true)
if [ "$_ad_rc" -eq 0 ] && [ "$_AD_LOC" = "ad-act|2026-07-02T00:00:00Z|terminal|pending" ] && [ "$_AD_HDR" -eq 1 ] \
   && [ "$_AD_H" -eq 1 ] && [ "$_AD_RAW" -eq 1 ] && [ "$_AD_OR" -eq 0 ] && [ -z "$(kt_ss_read_live_prompt "$_AD")" ]; then
  ok "AD consume_active with a quoted anchor lands the consumed entry under the real heading (1 LEDGER heading by walker AND raw grep, 0 orphans)"
else
  bad "AD consume_active" "rc=$_ad_rc locate='$_AD_LOC' consumed-headers=$_AD_HDR ledger-headings=$_AD_H raw-grep-headings=$_AD_RAW orphans=$_AD_OR"
fi

# AD2 (Review Focus 2): the tolerant anchor set. (a) and (b) are NON-REGRESSION (green before 1b);
# (c) the indented heading is NEW behaviour -- column 0 is required, so add appends a fresh section.
_ad2() {  # <dir> <anchor line, printf-%s> -> builds the file
  mkdir -p "$1"
  printf -- '---\nlastEvent: handoff\n---\n\n## Where we left off\n\n%s\n\nad2-after-anchor\n' "$2" > "$1/SESSION.md"
}
_ad2_landed() {  # <dir> -> 0 when ad2-new is an entry in LEDGER directly under a canonical heading
  _wk_lines '{ k = kt_region($0) } k == "heading" && R_SEC == "LEDGER" { h = FNR }
             k == "entry_header" && R_SEC == "LEDGER" && index($0, "### ad2-new · ") == 1 { e = FNR }
             END { exit !(h > 0 && e == h + 2) }' "$1/SESSION.md"
}
_ad2 "$TMP/ad2a" '**## Pending Handoffs**'
kt_ss_ledger_add "$TMP/ad2a" ad2-new 2026-07-04T00:00:00Z f n p
if _ad2_landed "$TMP/ad2a" && [ "$(grep -c '^## Pending handoffs$' "$TMP/ad2a/SESSION.md")" -eq 1 ] && ! grep -q 'Handoffs' "$TMP/ad2a/SESSION.md"; then
  ok "AD2(a) non-regression: a bold anchor is used and canonicalised to '## Pending handoffs'"
else
  bad "AD2(a)" "bold anchor not used/canonicalised"
fi
_ad2 "$TMP/ad2b" '### pending handoffs  '
kt_ss_ledger_add "$TMP/ad2b" ad2-new 2026-07-04T00:00:00Z f n p
if _ad2_landed "$TMP/ad2b" && [ "$(grep -c '^## Pending handoffs$' "$TMP/ad2b/SESSION.md")" -eq 1 ] && ! grep -qi '^### pending handoffs' "$TMP/ad2b/SESSION.md"; then
  ok "AD2(b) non-regression: '### pending handoffs  ' is used and canonicalised"
else
  bad "AD2(b)" "level-3 / trailing-space anchor not used/canonicalised"
fi
_ad2 "$TMP/ad2c" '  ## Pending handoffs'
kt_ss_ledger_add "$TMP/ad2c" ad2-new 2026-07-04T00:00:00Z f n p
if _ad2_landed "$TMP/ad2c" && [ "$(grep -c '^  ## Pending handoffs$' "$TMP/ad2c/SESSION.md")" -eq 1 ] \
   && [ "$(grep -c '^## Pending handoffs$' "$TMP/ad2c/SESSION.md")" -eq 1 ] \
   && [ "$(grep -n '^## Pending handoffs$' "$TMP/ad2c/SESSION.md" | cut -d: -f1)" -gt "$(grep -n 'ad2-after-anchor' "$TMP/ad2c/SESSION.md" | cut -d: -f1)" ]; then
  ok "AD2(c) new behaviour: an indented heading is NOT an anchor -- add appends a fresh section at EOF, indented line untouched"
else
  bad "AD2(c)" "the indented line was used as an anchor (or the EOF section is missing)"
fi

# AE (census shape): a consumed entry whose prompt holds, fenced, two entry-shaped headers and two raw
# terminators. A fence-blind prune reaps to the first inner terminator and resurrects the rest.
_AE="$TMP/ae"; mkdir -p "$_AE"
cat > "$_AE/SESSION.md" <<'AE_FIX'
---
lastEvent: handoff
---

## Pending handoffs

### ae-c · 2026-06-01T00:00:00Z · handoff · consumed 2026-06-02T00:00:00Z by x
- prompt:
```
### ae-x1 · 2026-01-03T00:00:00Z · handoff · unconsumed
ae-x1-body
<!-- aria:entry-end -->
### ae-x2 · 2026-01-04T00:00:00Z · handoff · unconsumed
<!-- aria:entry-end -->
```
<!-- aria:entry-end -->

### ae-live · 2026-06-05T00:00:00Z · handoff · unconsumed
- prompt: ae-live-body
<!-- aria:entry-end -->
AE_FIX
_AE_C0=$(kt_ss_ledger_candidates "$_AE" | sort)
kt_ss_ledger_prune "$_AE"
_AE_C1=$(kt_ss_ledger_candidates "$_AE" | sort)
_AE_PH=$(printf '%s\n' "$_AE_C1" | grep . | while IFS= read -r _r; do printf '%s\n' "$_AE_C0" | grep -qxF "$_r" || echo x; done | grep -c x || true)
_AE_OR=$(_wk_orphans "$_AE/SESSION.md")
# (fix round 1) the entry's prompt quotes live-looking headers in a fence, so its end cannot be fixed
# without crossing another entry: it is AMBIGUOUS and left in place (AK). Asserted: retained, not reaped.
if [ "$_AE_PH" -eq 0 ] && [ "$_AE_OR" -eq 0 ] && printf '%s\n' "$_AE_C1" | grep -q '^ae-live|' && grep -q '^### ae-c ' "$_AE/SESSION.md"; then
  ok "AE prune of a consumed entry with fenced inner headers/terminators: 0 phantoms, 0 orphans, live kept, ambiguous entry retained"
else
  bad "AE prune" "phantoms=$_AE_PH orphans=$_AE_OR after [$(printf '%s' "$_AE_C1" | tr '\n' ' ')]"
fi

# AE2 (fallback, NON-REGRESSION on "never deletes more than the old prune"): an entry whose fence-aware
# walk never closes because its fence is ODD is LEFT IN PLACE, header to EOF (K2, ruled 2026-11-11).
# The old rule ended it at the first fence-blind terminator and re-exposed what the open fence quotes as
# live entries -- measured on the real corpus: 36 phantoms in 6 files. Asserted: the entry's lines are
# byte-identical, 0 phantoms, no orphan terminator added, and every line the 3e44761 library keeps is
# still present in order (so the new prune deletes a subset of what the old one deleted).
_AE2="$TMP/ae2"; mkdir -p "$_AE2/new" "$_AE2/old"
cat > "$_AE2/new/SESSION.md" <<'AE2_FIX'
---
lastEvent: handoff
---

## Pending handoffs

### ae2-live · 2026-06-01T00:00:00Z · handoff · unconsumed
- prompt: ae2-live-body
<!-- aria:entry-end -->

### ae2-c · 2026-06-02T00:00:00Z · handoff · consumed 2026-06-03T00:00:00Z by x
- prompt:
```
ae2 unclosed fence text
## ae2 heading after
### ae2-l2 · 2026-06-04T00:00:00Z · handoff · unconsumed
ae2-more
<!-- aria:entry-end -->
AE2_FIX
cp "$_AE2/new/SESSION.md" "$_AE2/old/SESSION.md"
cp "$_AE2/new/SESSION.md" "$TMP/ae2.before"
_AE2_C0=$(kt_ss_ledger_candidates "$_AE2/new" | sort)
_AE2_O0=$(_wk_orphans "$_AE2/new/SESSION.md")
if git -C "$REPO_ROOT" show 3e44761:plugin-claude-code/scripts/lib-session-state.sh > "$TMP/old-lib.sh" 2>/dev/null && [ -s "$TMP/old-lib.sh" ]; then
  ( . "$TMP/old-lib.sh"; kt_ss_ledger_prune "$_AE2/old" )
  kt_ss_ledger_prune "$_AE2/new"
  _AE2_C1=$(kt_ss_ledger_candidates "$_AE2/new" | sort)
  _AE2_PH=$(printf '%s\n' "$_AE2_C1" | grep . | while IFS= read -r _r; do printf '%s\n' "$_AE2_C0" | grep -qxF "$_r" || echo x; done | grep -c x || true)
  _AE2_O1=$(_wk_orphans "$_AE2/new/SESSION.md")
  _AE2_TAILB=$(sed -n '/^### ae2-c /,$p' "$TMP/ae2.before")
  _AE2_TAILA=$(sed -n '/^### ae2-c /,$p' "$_AE2/new/SESSION.md")
  # Ordered subsequence: every line the old library kept appears in the new output, in order.
  _AE2_SUB=$(awk 'NR == FNR { o[++on] = $0; next } { if (j < on && $0 == o[j + 1]) j++ } END { if (j == on) { print "y" } else { print "n" } }' "$_AE2/old/SESSION.md" "$_AE2/new/SESSION.md")
  if [ -n "$_AE2_TAILB" ] && [ "$_AE2_TAILA" = "$_AE2_TAILB" ] && [ "$_AE2_PH" -eq 0 ] && [ "$_AE2_O1" -le "$_AE2_O0" ] \
     && [ "$_AE2_SUB" = y ] && printf '%s\n' "$_AE2_C1" | grep -q '^ae2-live|'; then
    ok "AE2 non-regression: an odd-fence open-at-EOF entry is left in place (0 phantoms, no orphan added, deletes a subset of 3e44761)"
  else
    bad "AE2 fallback" "entry-unchanged=$([ "$_AE2_TAILA" = "$_AE2_TAILB" ] && echo y || echo n) phantoms=$_AE2_PH orphans $_AE2_O0->$_AE2_O1 old-kept-subset=$_AE2_SUB"
  fi
else
  bad "AE2 reference" "could not extract the 3e44761 library -- a reference arm with no reference is not a pass"
fi

# AF (F4): a byte-identical block that sits OUTSIDE the ledger (archived, or quoted in the active fence)
# is not the ledger entry. add must write it, add_verified must see the LEDGER count rise.
_af_blk() {  # the exact block kt_ss_ledger_add writes for af-act
  printf '### af-act · 2026-07-05T00:00:00Z · handoff · unconsumed\n- focus: af-focus\n- next: af-next\n- prompt:\naria-handoff: proj-a/af-act@2026-07-05T00:00:00Z\naf plain prompt line\n<!-- aria:entry-end -->\n'
}
_AF_P='aria-handoff: proj-a/af-act@2026-07-05T00:00:00Z
af plain prompt line'
_af_ledger_n() { _wk_lines '{ k = kt_region($0) } k == "entry_header" && R_SEC == "LEDGER" && index($0, "### af-act · 2026-07-05T00:00:00Z · ") == 1 { n++ } END { print n + 0 }' "$1/SESSION.md"; }
_af_file() {  # <dir> <active body: "fence" | "prompt"> <put block under Pending: 0|1>
  mkdir -p "$1"
  {
    printf -- '---\nlastEvent: handoff\ncurrentFocus: af-focus\nnextAction: af-next\n---\n\n## Next session prompt\n\n'
    if [ "$2" = fence ]; then printf '```\n'; _af_blk; printf '```\n'; else printf '%s\n' "$_AF_P"; fi
    printf '\n## Pending handoffs\n\n'
    [ "$3" = 1 ] && { _af_blk; printf '\n'; }
    printf '## Archived sessions\n\n'; _af_blk
  } > "$1/SESSION.md"
}
_af_file "$TMP/af-add" fence 0
kt_ss_ledger_add "$TMP/af-add" af-act 2026-07-05T00:00:00Z af-focus af-next "$_AF_P"
_AF_N=$(_af_ledger_n "$TMP/af-add")
[ "$_AF_N" -eq 1 ] && ok "AF kt_ss_ledger_add writes the entry under Pending despite archived + active-fence copies" \
  || bad "AF add" "Pending holds $_AF_N af-act entries (want 1) -- an out-of-ledger copy suppressed the write"
_af_file "$TMP/af-av" fence 0
_AF_N0=$(_af_ledger_n "$TMP/af-av"); _af_rc=0
kt_ss_ledger_add_verified "$TMP/af-av" af-act 2026-07-05T00:00:00Z af-focus af-next "$_AF_P" || _af_rc=$?
_AF_N1=$(_af_ledger_n "$TMP/af-av")
[ "$_af_rc" -eq 0 ] && [ "$_AF_N1" -eq $((_AF_N0 + 1)) ] \
  && ok "AF kt_ss_ledger_add_verified returns 0 because the LEDGER header count rose by 1 ($_AF_N0 -> $_AF_N1)" \
  || bad "AF add_verified" "rc=$_af_rc LEDGER count $_AF_N0 -> $_AF_N1 (want rc 0 and +1)"
_af_file "$TMP/af-ca" prompt 0
_AF_ARCH0=$(_wk_lines '{ k = kt_region($0) } R_SEC == "ARCH" { print }' "$TMP/af-ca/SESSION.md")
_af_crc=0; kt_ss_ledger_consume_active "$TMP/af-ca" afby 2026-07-06T00:00:00Z "aria-handoff: proj-a/af-act@2026-07-05T00:00:00Z" 2>/dev/null || _af_crc=$?
_AF_ARCH1=$(_wk_lines '{ k = kt_region($0) } R_SEC == "ARCH" { print }' "$TMP/af-ca/SESSION.md")
_AF_CN=$(_wk_lines '{ k = kt_region($0) } k == "entry_header" && R_SEC == "LEDGER" && index($0, "### af-act · 2026-07-05T00:00:00Z · handoff · consumed 2026-07-06T00:00:00Z by afby") == 1 { n++ } END { print n + 0 }' "$TMP/af-ca/SESSION.md")
_AF_UN=$(_wk_lines '{ k = kt_region($0) } k == "entry_header" && R_SEC == "LEDGER" { n++ } END { print n + 0 }' "$TMP/af-ca/SESSION.md")
if [ "$_af_crc" -eq 0 ] && [ "$_AF_CN" -eq 1 ] && [ "$_AF_UN" -eq 1 ] && [ -n "$_AF_ARCH0" ] && [ "$_AF_ARCH1" = "$_AF_ARCH0" ]; then
  ok "AF consume_active: exactly one consumed entry under Pending, the archived copy byte-identical"
else
  bad "AF consume_active" "rc=$_af_crc consumed-in-Pending=$_AF_CN entries-in-Pending=$_AF_UN archive-unchanged=$([ "$_AF_ARCH1" = "$_AF_ARCH0" ] && echo y || echo n)"
fi
# AF0 positive control (Y9 behaviour): the same block already UNDER Pending -> nothing written, rc 0.
_af_file "$TMP/af0" prompt 1
cp "$TMP/af0/SESSION.md" "$TMP/af0.before"
_af0_rc=0; kt_ss_ledger_add_verified "$TMP/af0" af-act 2026-07-05T00:00:00Z af-focus af-next "$_AF_P" || _af0_rc=$?
if [ "$_af0_rc" -eq 0 ] && cmp -s "$TMP/af0.before" "$TMP/af0/SESSION.md"; then
  ok "AF0 control: the block already under Pending -> add writes nothing, add_verified returns 0"
else
  bad "AF0 control" "rc=$_af0_rc, file changed=$(cmp -s "$TMP/af0.before" "$TMP/af0/SESSION.md" && echo n || echo y)"
fi

# AI (carried (i), Task 1a review): a file whose front matter opens on line 1 and NEVER closes. Every
# reader treats it as all front matter (no live prompt), so kt_ss_mark_inprogress used to enter its
# front-matter rewrite and rewrite the first at:/sessionId:/lastEvent: line ANYWHERE in the file.
_AI="$TMP/ai"; mkdir -p "$_AI"
printf -- '---\nlastEvent: handoff\ncurrentFocus: ai-focus\n\n## Notes\n\nai body line\nat: ai-body-at\nsessionId: ai-body-sid\n' > "$_AI/SESSION.md"
cp "$_AI/SESSION.md" "$TMP/ai.before"
kt_ss_mark_inprogress "$_AI" ai-sid mipr
cmp -s "$TMP/ai.before" "$_AI/SESSION.md" \
  && ok "AI mark_inprogress refuses a never-closed front matter (file byte-identical)" \
  || bad "AI mark_inprogress" "rewrote a file whose front matter never closes"
# AI control: the same file with its front matter CLOSED is marked as usual (the refusal is scoped).
mkdir -p "$TMP/ai2"
printf -- '---\nlastEvent: handoff\ncurrentFocus: ai-focus\n---\n\n## Notes\n\nai body line\nat: ai-body-at\nsessionId: ai-body-sid\n' > "$TMP/ai2/SESSION.md"
kt_ss_mark_inprogress "$TMP/ai2" ai-sid mipr
if grep -q '^sessionId: ai-sid$' "$TMP/ai2/SESSION.md" && grep -q '^at: ai-body-at$' "$TMP/ai2/SESSION.md"; then
  ok "AI control: a closed front matter is still marked, and the body's at: line is untouched"
else
  bad "AI control" "a closed front matter was not marked (or its body was rewritten)"
fi

# AJ (carried (iii)): an ACTIVE slot holding only an empty fence pair is NO active prompt.
_aj() {  # <dir> <fence content line or empty>
  mkdir -p "$1"
  { printf -- '---\nlastEvent: wrapup\nat: 2026-07-01T00:00:00Z\nsessionId: aj-fm\n---\n\n## Next session prompt\n\n```\n'
    [ -n "$2" ] && printf '%s\n' "$2"
    printf '```\n\n## Pending handoffs\n\n### aj-live · 2026-06-01T00:00:00Z · handoff · unconsumed\n- prompt: aj\n<!-- aria:entry-end -->\n'; } > "$1/SESSION.md"
}
_aj "$TMP/aj" ""
_aj "$TMP/aj-c" "aj real prompt line"
if ! kt_ss_ledger_candidates "$TMP/aj" | grep -q '|active$' && [ "$(kt_ss_ledger_candidates "$TMP/aj" | grep -c .)" -eq 1 ] \
   && kt_ss_ledger_candidates "$TMP/aj-c" | grep -q '^aj-fm|2026-07-01T00:00:00Z|unconsumed|active$'; then
  ok "AJ an empty fence pair in ACTIVE yields no |active row (control: one prompt line does)"
else
  bad "AJ empty fence" "candidates on an empty fence pair: [$(kt_ss_ledger_candidates "$TMP/aj" | tr '\n' ' ')]"
fi

# AK / AK2 (fix round 1, I1): a consumed entry e1 whose prompt opens a fence it never closes, followed by
# an older LIVE entry l1 whose prompt does the same. Pass 1's in-entry fence count is back to even inside
# l1, so l1's terminator would close e1 and pass 2 would reap l1 with it -- deleting a live handoff the
# old prune kept. An entry whose span holds a FENCED well-formed `unconsumed` header cannot be bounded
# without crossing another entry, so it is AMBIGUOUS and left in place. AK2 is the CRLF form, where no
# terminator matches and e1 would close only at l0's header.
_ak_fix() {  # <dir> <lf|crlf>
  mkdir -p "$1"
  cat > "$1/SESSION.md.lf" <<'AK_FIX'
## Pending handoffs

### e1 · 2026-01-02T00:00:00Z · handoff · consumed 2026-01-03T00:00:00Z by x
- prompt:
```
e1 prompt with unclosed fence
<!-- aria:entry-end -->

### l1 · 2026-01-01T00:00:00Z · handoff · unconsumed
- prompt:
```
l1 prompt also unclosed
<!-- aria:entry-end -->

### l0 · 2025-12-01T00:00:00Z · handoff · unconsumed
- prompt: plain
<!-- aria:entry-end -->
AK_FIX
  if [ "$2" = crlf ]; then awk '{ printf "%s\r\n", $0 }' "$1/SESSION.md.lf" > "$1/SESSION.md"; else cp "$1/SESSION.md.lf" "$1/SESSION.md"; fi
  rm -f "$1/SESSION.md.lf"
}
for _akm in lf crlf; do
  _akd="$TMP/ak-$_akm"; _ak_fix "$_akd/new" "$_akm"; _ak_fix "$_akd/old" "$_akm"
  _akn="AK"; [ "$_akm" = crlf ] && _akn="AK2"
  if [ -s "$TMP/old-lib.sh" ]; then
    ( . "$TMP/old-lib.sh"; KT_SS_RECEIPTS="$_akd/old-receipts"; kt_ss_ledger_prune "$_akd/old" )
    kt_ss_ledger_prune "$_akd/new"
    _akl1=$(grep -c '^### l1 · 2026-01-01T00:00:00Z · handoff · unconsumed' "$_akd/new/SESSION.md" || true)
    # Fragment match: $TMP may carry a doubled slash from TMPDIR, the receipt a pwd-derived path.
    _akrc=$(grep -cF "/ak-$_akm/new/SESSION.md|l1|" "$KT_SS_RECEIPTS" 2>/dev/null || true)
    _aksub=$(awk 'NR == FNR { o[++on] = $0; next } { if (j < on && $0 == o[j + 1]) j++ } END { if (j == on) { print "y" } else { print "n" } }' "$_akd/old/SESSION.md" "$_akd/new/SESSION.md")
    if [ "$_akl1" -eq 1 ] && [ "$_akrc" -eq 0 ] && [ "$_aksub" = y ]; then
      ok "$_akn ($_akm) a consumed entry that cannot be bounded is left in place: live l1 survives, no receipt names l1, old output is a subsequence"
    else
      bad "$_akn ($_akm)" "l1 headers=$_akl1 receipts naming l1=$_akrc old-kept-subset=$_aksub"
    fi
  else
    bad "$_akn reference" "no 3e44761 library extracted (AE2 extracts it) -- a reference arm with no reference is not a pass"
  fi
done

# AL (fix round 1, m2): the EVEN-parity open-at-EOF fallback runs the old fence-blind rule -- but only
# inside LEDGER/ARCH. Here the ledger sits ABOVE `## Next session prompt`, the last entry e1 is consumed
# and unterminated, and the active prompt quotes a consumed header in a fence: the old rule reaped it
# with the prompt tail (F1 again). Front matter, ACTIVE and other sections must print unconditionally.
_AL="$TMP/al"; mkdir -p "$_AL"
cat > "$_AL/SESSION.md" <<'AL_FIX'
## Pending handoffs

### l1 · 2026-01-03T00:00:00Z · handoff · unconsumed
- prompt: live
<!-- aria:entry-end -->

### e1 · 2026-01-02T00:00:00Z · handoff · consumed 2026-01-03T00:00:00Z by x
- focus: unterminated last entry

## Next session prompt

```
aria-handoff: proj-a/al-act@2026-02-02T00:00:00Z
### f1 · 2026-01-01T00:00:00Z · handoff · consumed
quoted line A
quoted line B
```

## Notes
keep
AL_FIX
_AL_A0=$(_wk_lines '{ k = kt_region($0) } R_SEC == "ACTIVE" || R_SEC == "OTHER" { print }' "$_AL/SESSION.md")
kt_ss_ledger_prune "$_AL"
_AL_A1=$(_wk_lines '{ k = kt_region($0) } R_SEC == "ACTIVE" || R_SEC == "OTHER" { print }' "$_AL/SESSION.md")
if [ "$_AL_A1" = "$_AL_A0" ] && printf '%s\n' "$_AL_A1" | grep -q '^quoted line B$' && ! grep -q '^### e1 ' "$_AL/SESSION.md" \
   && grep -q '^### l1 ' "$_AL/SESSION.md"; then
  ok "AL the even-parity fallback stays in the ledger: ACTIVE and Notes byte-identical, e1 still reaped, l1 kept"
else
  bad "AL fallback scope" "ACTIVE/OTHER changed under the open-at-EOF fallback (or e1 not reaped / l1 lost)"
fi

# AM (fix round 2, a): AMBIGUOUS keys on ANY fenced well-formed header that is not word-bounded
# `consumed` -- the old prune kept every such header. A swallowed middle entry whose status was
# hand-written (`RETIRED`) must survive like a live one.
_AM="$TMP/am"; mkdir -p "$_AM/new" "$_AM/old"
cat > "$_AM/new/SESSION.md" <<'AM_FIX'
## Pending handoffs

### e1 · 2026-01-02T00:00:00Z · handoff · consumed 2026-01-03T00:00:00Z by x
- prompt:
```
e1 unclosed
<!-- aria:entry-end -->

### r1 · 2026-01-01T00:00:00Z · handoff · RETIRED
- prompt:
```
r1 unclosed
<!-- aria:entry-end -->

### l0 · 2025-12-01T00:00:00Z · handoff · unconsumed
- prompt: plain
<!-- aria:entry-end -->
AM_FIX
cp "$_AM/new/SESSION.md" "$_AM/old/SESSION.md"
( . "$TMP/old-lib.sh"; KT_SS_RECEIPTS="$_AM/old-receipts"; kt_ss_ledger_prune "$_AM/old" )
kt_ss_ledger_prune "$_AM/new"
_AM_R1=$(grep -c '^### r1 · ' "$_AM/new/SESSION.md" || true)
_AM_RC=$(grep -cF "/am/new/SESSION.md|r1|" "$KT_SS_RECEIPTS" 2>/dev/null || true)
_AM_SUB=$(awk 'NR == FNR { o[++on] = $0; next } { if (j < on && $0 == o[j + 1]) j++ } END { if (j == on) { print "y" } else { print "n" } }' "$_AM/old/SESSION.md" "$_AM/new/SESSION.md")
if [ "$_AM_R1" -eq 1 ] && [ "$_AM_RC" -eq 0 ] && [ "$_AM_SUB" = y ]; then
  ok "AM a fenced non-consumed header (RETIRED) also makes an entry ambiguous: r1 survives, no receipt, old output is a subsequence"
else
  bad "AM ambiguous predicate" "r1 headers=$_AM_R1 receipts naming r1=$_AM_RC old-kept-subset=$_AM_SUB"
fi

# AN (fix round 2, b): the ambiguity must lie INSIDE the entry. A legacy consumed entry with no
# terminator ends at the next section heading; a fence in `## Notes` below it quoting an unconsumed
# header is not part of it, so the entry is reaped exactly as the old prune reaps it.
_AN="$TMP/an"; mkdir -p "$_AN/new" "$_AN/old"
cat > "$_AN/new/SESSION.md" <<'AN_FIX'
## Pending handoffs

### l1 · 2026-01-03T00:00:00Z · handoff · unconsumed
- prompt: live
<!-- aria:entry-end -->

### e1 · 2026-01-02T00:00:00Z · handoff · consumed 2026-01-03T00:00:00Z by x
- focus: legacy unterminated

## Notes

```
### q1 · 2026-01-01T00:00:00Z · handoff · unconsumed
```
AN_FIX
cp "$_AN/new/SESSION.md" "$_AN/old/SESSION.md"
( . "$TMP/old-lib.sh"; KT_SS_RECEIPTS="$_AN/old-receipts"; kt_ss_ledger_prune "$_AN/old" )
kt_ss_ledger_prune "$_AN/new"
if cmp -s "$_AN/old/SESSION.md" "$_AN/new/SESSION.md" && ! grep -q '^### e1 ' "$_AN/new/SESSION.md" && grep -q '^### q1 ' "$_AN/new/SESSION.md"; then
  ok "AN a fenced header in a LATER section does not make an unterminated entry ambiguous: reaped exactly as the old prune does"
else
  bad "AN ambiguity scope" "the unterminated consumed entry was kept (or the Notes quote was touched)"
fi

# AO (fix round 3): the ROOT signal. A consumed entry whose in-entry fence count is ODD where the old
# prune would end it cannot be bounded: the walker's end lies further on, past lines the old prune kept.
# Here the next "entry" is malformed (one ` · `), so there is no well-formed header to find -- the
# header-hunting predicate missed it and r1's lines were deleted. The parity rule keeps e1 in place.
_AO="$TMP/ao"; mkdir -p "$_AO/new" "$_AO/old"
cat > "$_AO/new/SESSION.md" <<'AO_FIX'
## Pending handoffs

### e1 · 2026-01-02T00:00:00Z · handoff · consumed 2026-01-03T00:00:00Z by x
- prompt:
```
e1 unclosed
<!-- aria:entry-end -->

### r1 · 2026-01-01T00:00:00Z
- prompt:
```
r1 unclosed
<!-- aria:entry-end -->

### l0 · 2025-12-01T00:00:00Z · handoff · unconsumed
<!-- aria:entry-end -->
AO_FIX
cp "$_AO/new/SESSION.md" "$_AO/old/SESSION.md"
( . "$TMP/old-lib.sh"; KT_SS_RECEIPTS="$_AO/old-receipts"; kt_ss_ledger_prune "$_AO/old" )
kt_ss_ledger_prune "$_AO/new"
_AO_SUB=$(awk 'NR == FNR { o[++on] = $0; next } { if (j < on && $0 == o[j + 1]) j++ } END { if (j == on) { print "y" } else { print "n" } }' "$_AO/old/SESSION.md" "$_AO/new/SESSION.md")
if [ "$_AO_SUB" = y ] && grep -q '^r1 unclosed$' "$_AO/new/SESSION.md" && grep -q '^### l0 ' "$_AO/new/SESSION.md"; then
  ok "AO a consumed entry whose fence is open where the old prune ends it stays in place (malformed r1 kept; old output is a subsequence)"
else
  bad "AO parity rule" "lines the old prune kept were deleted (old-kept-subset=$_AO_SUB)"
fi

# AP (fix round 3): the parity rule's second clause. A TERMINATED consumed entry whose prompt has an
# unfenced "## " before a fenced header: the old prune ends it at that heading (its first fence-blind
# boundary is the header, not a terminator) and keeps the rest, while the walker reaps to the terminator.
# Same mismatch at even parity -> the entry is left in place, so nothing the old prune kept is deleted.
_AP="$TMP/ap"; mkdir -p "$_AP/new" "$_AP/old"
cat > "$_AP/new/SESSION.md" <<'AP_FIX'
## Pending handoffs

### e1 · 2026-01-02T00:00:00Z · handoff · consumed 2026-01-03T00:00:00Z by x
- prompt:
## ap sub heading
```
### x1 · 2026-01-01T00:00:00Z · handoff · unconsumed
```
<!-- aria:entry-end -->

### l0 · 2025-12-01T00:00:00Z · handoff · unconsumed
<!-- aria:entry-end -->
AP_FIX
cp "$_AP/new/SESSION.md" "$_AP/old/SESSION.md"
( . "$TMP/old-lib.sh"; KT_SS_RECEIPTS="$_AP/old-receipts"; kt_ss_ledger_prune "$_AP/old" )
kt_ss_ledger_prune "$_AP/new"
_AP_SUB=$(awk 'NR == FNR { o[++on] = $0; next } { if (j < on && $0 == o[j + 1]) j++ } END { if (j == on) { print "y" } else { print "n" } }' "$_AP/old/SESSION.md" "$_AP/new/SESSION.md")
if [ "$_AP_SUB" = y ] && grep -q '^### x1 ' "$_AP/new/SESSION.md" && grep -q '^### l0 ' "$_AP/new/SESSION.md"; then
  ok "AP a terminated consumed entry the old prune ends at a heading stays in place (old output is a subsequence)"
else
  bad "AP parity rule (heading clause)" "lines the old prune kept were deleted (old-kept-subset=$_AP_SUB)"
fi

# AQ / AQ2 (fix round 4): a ledger with NO exact terminator (legacy, or any CRLF ledger). The old prune
# ends a consumed entry at its first `### ` of any shape; when that line is a plain sub-heading rather
# than a well-formed entry header, the walker (which closes only at well-formed headers) would reap the
# sub-heading and its note, which the old prune kept. A non-entry heading at the old boundary therefore
# makes the entry ambiguous, and it stays.
_aq_fix() {  # <dir> <lf|crlf>
  mkdir -p "$1"
  cat > "$1/SESSION.md.lf" <<'AQ_FIX'
## Prior sessions

### e1 · 2026-01-02T00:00:00Z · handoff · consumed
- focus: legacy
### Subheading kept by old
note text kept by old
### l1 · 2026-01-01T00:00:00Z · handoff · unconsumed
- focus: live

## Notes
keep
AQ_FIX
  if [ "$2" = crlf ]; then awk '{ printf "%s\r\n", $0 }' "$1/SESSION.md.lf" > "$1/SESSION.md"; else cp "$1/SESSION.md.lf" "$1/SESSION.md"; fi
  rm -f "$1/SESSION.md.lf"
}
for _aqm in lf crlf; do
  _aqd="$TMP/aq-$_aqm"; _aq_fix "$_aqd/new" "$_aqm"; _aq_fix "$_aqd/old" "$_aqm"
  _aqn="AQ"; [ "$_aqm" = crlf ] && _aqn="AQ2"
  ( . "$TMP/old-lib.sh"; KT_SS_RECEIPTS="$_aqd/old-receipts"; kt_ss_ledger_prune "$_aqd/old" )
  kt_ss_ledger_prune "$_aqd/new"
  _aqsub=$(awk 'NR == FNR { o[++on] = $0; next } { if (j < on && $0 == o[j + 1]) j++ } END { if (j == on) { print "y" } else { print "n" } }' "$_aqd/old/SESSION.md" "$_aqd/new/SESSION.md")
  if [ "$_aqsub" = y ] && grep -q '^note text kept by old' "$_aqd/new/SESSION.md" && grep -q '^### l1 ' "$_aqd/new/SESSION.md"; then
    ok "$_aqn ($_aqm) a non-entry heading at the old boundary keeps the consumed entry (old output is a subsequence)"
  else
    bad "$_aqn ($_aqm)" "lines the old prune kept were deleted (old-kept-subset=$_aqsub)"
  fi
done

# --- AA..AA5 (2.58.0 Task 2, spec §3): one entry builder escapes structural prompt lines on write ---------
# A stored prompt line matching ^\\*(## |### |```|<!-- aria:entry-end -->$) gets ONE leading backslash
# (mbox-style, injective). No decoder ships in the library: this suite carries the REFERENCE decoder
# (_ss_ref_decode, defined before block Y) and proves decode(encode(x)) == x.
_aa_decode() { _ss_ref_decode; }
_aa_hdr='### aa · 2026-01-01T00:00:00Z · handoff · unconsumed'
_aa_tok='aria-handoff: proj-a/aa@2026-01-01T00:00:00Z'
_aa_mk() {  # <dir> -> a fresh SESSION.md whose last line is the `## Pending handoffs` heading
  mkdir -p "$1"
  printf -- '---\nlastEvent: handoff\n---\n\n## Where we left off\n\naa-body\n\n## Pending handoffs\n' > "$1/SESSION.md"
}
printf '%s\n' '### f · 2026-01-01T00:00:00Z · handoff · consumed' '### f · 2026-01-01T00:00:00Z · handoff · unconsumed' \
  '## Pending handoffs' '## Where we left off' '<!-- aria:entry-end -->' '```' '\## x' '\\```' "$_aa_tok" > "$TMP/aa-prompt"
awk '{ printf "%s\r\n", $0 }' "$TMP/aa-prompt" > "$TMP/aa-prompt-crlf"
# The `- prompt:` line of the aa entry (the hostile prompt holds no such line, so the first one is ours).
_aa_p() { awk -v h="$_aa_hdr" '$0 == h { f = 1 } f && $0 == "- prompt:" { print FNR; exit }' "$1"; }
# Walker verdict over the stored prompt lines p+1..p+n: "<non-body lines>|<terminator at p+n+1>".
_aa_walk() {  # <file> <p> <n>
  awk -v p="$2" -v n="$3" "$(_kt_ss_awk_regions)"'
    { k = kt_region($0) }
    FNR > p && FNR <= p + n && (k != "body" || R_ENTRY != p - 3) { nb++ }
    FNR == p + n + 1 && k == "terminator" { t = 1 }
    END { print (nb + 0) "|" (t + 0) }' "$1"
}
_aa_stored() { awk -v p="$2" -v n="$3" 'FNR > p && FNR <= p + n' "$1"; }  # <file> <p> <n>

# AA: the hostile prompt, LF.
_AA="$TMP/aa"; _aa_mk "$_AA"
kt_ss_ledger_add "$_AA" aa 2026-01-01T00:00:00Z aa-focus aa-next "$(cat "$TMP/aa-prompt")"
_aa_n=$(grep -c '' "$TMP/aa-prompt"); _AA_P=$(_aa_p "$_AA/SESSION.md")
_AA_W=$(_aa_walk "$_AA/SESSION.md" "${_AA_P:-0}" "$_aa_n")
[ "$_AA_W" = "0|1" ] && ok "AA(1) every stored prompt line is body of the aa entry; its terminator closes it" \
  || bad "AA(1) walker" "non-body|terminator = $_AA_W (want 0|1), prompt line ${_AA_P:-none}"
_aa_stored "$_AA/SESSION.md" "${_AA_P:-0}" "$_aa_n" | _aa_decode > "$TMP/aa-dec"
cmp -s "$TMP/aa-dec" "$TMP/aa-prompt" && ok "AA(2) reference decode of the stored prompt is byte-identical to the input" \
  || bad "AA(2) round trip" "decoded stored prompt differs from the input"
_AA_C=$(kt_ss_ledger_candidates "$_AA"); _AA_L=$(kt_ss_ledger_token_locate "$_AA" "$_aa_tok")
if [ "$(printf '%s\n' "$_AA_C" | grep -c .)" -eq 1 ] && [ "$_AA_C" = "aa|2026-01-01T00:00:00Z|unconsumed|pending" ] \
   && [ "$_AA_L" = "aa|2026-01-01T00:00:00Z|unconsumed|pending" ]; then
  ok "AA(3) exactly one candidate, and the token locates the aa entry |pending"
else
  bad "AA(3) candidates/locate" "candidates [$(printf '%s' "$_AA_C" | tr '\n' ' ')] locate '$_AA_L'"
fi

# AA2 (Review Focus 1): the same prompt with CRLF line ends.
_AA2="$TMP/aa2"; _aa_mk "$_AA2"
kt_ss_ledger_add "$_AA2" aa 2026-01-01T00:00:00Z aa-focus aa-next "$(cat "$TMP/aa-prompt-crlf")"
_AA2_P=$(_aa_p "$_AA2/SESSION.md")
_aa_stored "$_AA2/SESSION.md" "${_AA2_P:-0}" "$_aa_n" | _aa_decode > "$TMP/aa2-dec"
_AA2_C=$(kt_ss_ledger_candidates "$_AA2")
if cmp -s "$TMP/aa2-dec" "$TMP/aa-prompt-crlf" && [ "$(printf '%s\n' "$_AA2_C" | grep -c .)" -eq 1 ] \
   && [ "$(_aa_walk "$_AA2/SESSION.md" "${_AA2_P:-0}" "$_aa_n")" = "0|1" ]; then
  ok "AA2 the CRLF prompt round-trips byte-identically, stays body, and yields 1 candidate"
else
  bad "AA2 CRLF" "round trip $(cmp -s "$TMP/aa2-dec" "$TMP/aa-prompt-crlf" && echo same || echo DIFFERS), candidates [$(printf '%s' "$_AA2_C" | tr '\n' ' ')]"
fi

# AA3 (Review Focus 3): an empty prompt keeps the 3e44761 block format exactly -- NON-REGRESSION (green on
# 841ef44 too); a prompt that is exactly ``` stores \``` and decodes back -- NEW.
_AA3="$TMP/aa3"; _aa_mk "$_AA3"
kt_ss_ledger_add "$_AA3" aa 2026-01-01T00:00:00Z aa-focus aa-next ""
awk -v h="$_aa_hdr" '$0 == h { f = 1 } f { print } f && $0 == "<!-- aria:entry-end -->" { exit }' "$_AA3/SESSION.md" > "$TMP/aa3-blk"
printf '%s\n' "$_aa_hdr" '- focus: aa-focus' '- next: aa-next' '- prompt:' '' '<!-- aria:entry-end -->' > "$TMP/aa3-want"
cmp -s "$TMP/aa3-blk" "$TMP/aa3-want" && ok "AA3 (non-regression) an empty prompt stores the 3e44761 block byte-for-byte" \
  || bad "AA3 empty prompt" "stored block differs from the 3e44761 format"
_AA3F="$TMP/aa3f"; _aa_mk "$_AA3F"
kt_ss_ledger_add "$_AA3F" aa 2026-01-01T00:00:00Z aa-focus aa-next '```'
_AA3F_P=$(_aa_p "$_AA3F/SESSION.md")
_AA3F_S=$(_aa_stored "$_AA3F/SESSION.md" "${_AA3F_P:-0}" 1)
if [ "$_AA3F_S" = '\```' ] && [ "$(printf '%s\n' "$_AA3F_S" | _aa_decode)" = '```' ]; then
  ok "AA3 a prompt that is exactly a fence stores \\\`\`\` and decodes back"
else
  bad "AA3 fence prompt" "stored '$_AA3F_S' (want \\\`\`\`)"
fi

# AA4: the AA prompt through kt_ss_ledger_add_verified returns 0 and the LEDGER entry-header count (every
# sid, walker-counted) rises by exactly 1 -- the quoted headers are not entries.
_aa_lh() { _wk_lines '{ k = kt_region($0) } k == "entry_header" && R_SEC == "LEDGER" { n++ } END { print n + 0 }' "$1"; }
_AA4="$TMP/aa4"; _aa_mk "$_AA4"; _aa4_0=$(_aa_lh "$_AA4/SESSION.md")
_aa4_rc=0; kt_ss_ledger_add_verified "$_AA4" aa 2026-01-01T00:00:00Z aa-focus aa-next "$(cat "$TMP/aa-prompt")" || _aa4_rc=$?
_aa4_1=$(_aa_lh "$_AA4/SESSION.md")
if [ "$_aa4_rc" -eq 0 ] && [ "$_aa4_1" -eq $((_aa4_0 + 1)) ]; then
  ok "AA4 add_verified lands the hostile prompt (rc 0) and the LEDGER header count rises by exactly 1"
else
  bad "AA4 add_verified" "rc=$_aa4_rc LEDGER headers $_aa4_0 -> $_aa4_1 (want +1)"
fi

# AA5: Task 1b's prune keeps a consumed PRE-2.58.0 entry whose prompt holds a raw structural line. That
# trade must not reach NEW entries: written through kt_ss_ledger_add and marked consumed, it IS reaped.
_AA5="$TMP/aa5"; _aa_mk "$_AA5"
kt_ss_ledger_add "$_AA5" aa 2026-01-01T00:00:00Z aa-focus aa-next "$(cat "$TMP/aa-prompt")"
kt_ss_ledger_mark_consumed "$_AA5" aa 2026-01-02T00:00:00Z aa-by 2026-01-01T00:00:00Z
kt_ss_ledger_prune "$_AA5"
_AA5_LEFT=$(grep -c -e 'proj-a/aa@' -e '^### aa ' -e 'Where we left off' -e '^\\' "$_AA5/SESSION.md" || true)
_AA5_OR=$(_wk_orphans "$_AA5/SESSION.md")
if [ "$_AA5_LEFT" -eq 1 ] && [ "$_AA5_OR" -eq 0 ] && [ -z "$(kt_ss_ledger_candidates "$_AA5")" ] && grep -q '^aa-body$' "$_AA5/SESSION.md"; then
  ok "AA5 a consumed entry written with a hostile prompt is reaped whole by prune (no retention, 0 orphans)"
else
  bad "AA5 prune of a new hostile entry" "matching lines left=$_AA5_LEFT (want 1: the real heading) orphans=$_AA5_OR"
fi

# AA6..AA8 (Task 2 fix round 1) -- failure paths and exact bytes, run against EVERY port's lib in a subshell.
#   AA6 the project dir is read-only (SESSION.md itself writable): add returns 0 and leaves SESSION.md
#       byte-identical; add_verified returns 1. NON-REGRESSION (green at 841ef44 too): it pins the outcome.
#   AA7 prompts `x` and `x`+newline store exactly the expected block bytes. NON-REGRESSION.
#   AA8 an EMPTY block build (shimmed builder) must never read as landed: add_verified returns 1 and the
#       file is unchanged. Before the fix the expected rise walked to 0, n1 == n0 + 0, and it returned 0.
_aa_port_arms() {  # $1 tag; the caller has sourced ONE port's lib into this subshell
  b="$TMP/aap/$1"; mkdir -p "$b"
  _aa_mk "$b/d6"; cp "$b/d6/SESSION.md" "$b/before6"
  chmod 555 "$b/d6"
  if ( : > "$b/d6/probe" ) 2>/dev/null; then
    rm -f "$b/d6/probe" 2>/dev/null
    echo "BAD AA6 readonly_dir -- instrument: a file could still be created in the 555 dir (running as root?)"
  else
    r1=0; kt_ss_ledger_add "$b/d6" aa 2026-01-01T00:00:00Z f n 'p' 2>/dev/null || r1=$?
    r2=0; kt_ss_ledger_add_verified "$b/d6" aa 2026-01-01T00:00:00Z f n 'p' 2>/dev/null || r2=$?
    if [ "$r1$r2" = "01" ] && cmp -s "$b/before6" "$b/d6/SESSION.md"; then echo "OK AA6 readonly_dir_writes_nothing_and_does_not_report_landed"
    else echo "BAD AA6 readonly_dir -- exits add=$r1 add_verified=$r2 (want 0/1), file $(cmp -s "$b/before6" "$b/d6/SESSION.md" && echo same || echo CHANGED)"; fi
  fi
  chmod 755 "$b/d6"

  p_nl='x
'
  for v in plain nl; do
    _aa_mk "$b/d7$v"
    if [ "$v" = plain ]; then kt_ss_ledger_add "$b/d7$v" aa 2026-01-01T00:00:00Z f n 'x'
      printf '%s\n' "$_aa_hdr" '- focus: f' '- next: n' '- prompt:' 'x' '<!-- aria:entry-end -->' > "$b/want7$v"
    else kt_ss_ledger_add "$b/d7$v" aa 2026-01-01T00:00:00Z f n "$p_nl"
      printf '%s\n' "$_aa_hdr" '- focus: f' '- next: n' '- prompt:' 'x' '' '<!-- aria:entry-end -->' > "$b/want7$v"
    fi
    awk -v h="$_aa_hdr" '$0 == h { f = 1 } f { print } f && $0 == "<!-- aria:entry-end -->" { exit }' "$b/d7$v/SESSION.md" > "$b/got7$v"
    if cmp -s "$b/want7$v" "$b/got7$v"; then echo "OK AA7 exact_block_bytes_$v"
    else echo "BAD AA7 exact_block_bytes_$v -- stored block differs from the expected bytes"; fi
  done

  _aa_mk "$b/d8"; cp "$b/d8/SESSION.md" "$b/before8"
  r=$( ( _kt_ss_entry_block() { :; }
         x=0; kt_ss_ledger_add_verified "$b/d8" aa 2026-01-01T00:00:00Z f n 'p' >/dev/null 2>&1 || x=$?
         printf '%s' "$x" ) ) || true
  if [ "$r" = "1" ] && cmp -s "$b/before8" "$b/d8/SESSION.md"; then echo "OK AA8 empty_build_never_reads_as_landed"
  else echo "BAD AA8 empty_build_never_reads_as_landed -- add_verified exit '$r' (want 1), file $(cmp -s "$b/before8" "$b/d8/SESSION.md" && echo same || echo CHANGED)"; fi
}
_AAP_SEEN=0
for _ad in plugin-claude-code/scripts plugin-antigravity/bin plugin-cursor-template/scripts/aria plugin-openai-codex/bin; do
  _af="$REPO_ROOT/$_ad/lib-session-state.sh"
  [ -f "$_af" ] || { bad "AA6-8 $_ad" "lib-session-state.sh missing -- a guard with no subject"; continue; }
  _AAP_SEEN=$((_AAP_SEEN + 1))
  _aout=$( ( . "$_af"; _aa_port_arms "$(printf '%s' "$_ad" | tr '/' '_')" ) 2>&1 ) || true
  while IFS= read -r _al; do
    case "$_al" in
      "OK "*)  ok "$_ad: ${_al#OK }" ;;
      "BAD "*) _an=${_al#BAD }; bad "$_ad: ${_an%% -- *}" "${_an#* -- }" ;;
    esac
  done <<AAOUT
$_aout
AAOUT
  _an=$(printf '%s\n' "$_aout" | grep -c '^OK ' || true)
  [ "$_an" -eq 4 ] || bad "AA6-8 coverage $_ad" "only $_an of 4 arms passed -- see the lines above"
done
[ "$_AAP_SEEN" -eq 4 ] && ok "AA6-8 coverage: all 4 carrying ports exercised" || bad "AA6-8 coverage" "only $_AAP_SEEN of 4 port libs found"

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
