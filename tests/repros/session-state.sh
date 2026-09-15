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
_SS_PARITY_FNS="kt_ss_ledger_add kt_ss_ledger_prune"
_SS_P1="$REPO_ROOT/plugin-claude-code/bin/lib-session-state.sh"
_SS_P2="$REPO_ROOT/plugin-antigravity/bin/lib-session-state.sh"
_SS_P3="$REPO_ROOT/plugin-cursor-template/scripts/aria/lib-session-state.sh"
_SS_P4="$REPO_ROOT/plugin-openai-codex/bin/lib-session-state.sh"

for _fn in $_SS_PARITY_FNS; do
  _N1=$(_ss_fnsum "$_SS_P1" "$_fn")
  _N2=$(_ss_fnsum "$_SS_P2" "$_fn")
  _N3=$(_ss_fnsum "$_SS_P3" "$_fn")
  if [ "$_N1" = MISSING ] || [ "$_N2" = MISSING ] || [ "$_N3" = MISSING ]; then
    bad "N port parity ($_fn)" "a carrying port path is MISSING (cc=$_N1 ag=$_N2 cu=$_N3) — a skip-when-absent arm is a gate with no subject"
  elif [ "$_N1" = "$_N2" ] && [ "$_N2" = "$_N3" ]; then
    ok "N $_fn is identical across all 3 carrying ports (comment-normalised cksum)"
  else
    bad "N port parity ($_fn)" "$_fn DIFFERS across ports: cc=$_N1 ag=$_N2 cu=$_N3"
  fi
  # ⚠ NOT `grep -c ... || echo 0`: grep -c PRINTS 0 and EXITS 1 with no matches, so the `||` fires on
  # top of the printed 0 and the value becomes "0\n0" — which fails `-eq` and sent this arm red on
  # its first run. awk always prints exactly once and exits 0.
  _N4=$(awk -v fn="$_fn" '$0 ~ fn {c++} END{print c+0}' "$_SS_P4" 2>/dev/null)
  [ -n "$_N4" ] || _N4=0
  [ "$_N4" -eq 0 ] \
    && ok "N plugin-openai-codex carries no $_fn, so it is correctly out of the parity set" \
    || bad "N codex port ($_fn)" "plugin-openai-codex now carries $_fn ($_N4 refs) and must join the parity set"
done

# --- O: mark_inprogress OVERWRITES an existing sessionId while the body survives ----------------
# ⛔ THIS IS THE CASE-3 SIGNATURE, AND IT WAS ASSERTED NOWHERE before 2026-09-11. Block D covers the
# neighbouring case (sessionId ABSENT, so the helper INSERTS one) and asserts body preservation there
# ("D preserved Next session prompt"). Block K has a sessionId but never calls kt_ss_mark_inprogress.
# So the state that matters most had no coverage: an EXISTING id REPLACED with the marking session's,
# while ANOTHER session's prompt is carried through untouched.
#
# Why it matters beyond this helper: post-edit-check.sh produces exactly this state on the first edit
# of any session in a project that holds a handoff. It is the reason /wrapup Step 6.5 and /handoff 3f
# must NOT test sessionId — a front-matter sessionId names whoever last TOUCHED the file, not whoever
# wrote the body. Design record:
#   docs/superpowers/specs/2026-09-11-demote-gate-sessionid-conjunct-design.md
#
# ⭐ THIS IS A CHARACTERIZATION TEST. It passes BOTH before and after the skill-clause fix, by design:
# it does not guard the fix, it establishes that the precondition the fix reasons about is produced by
# ORDINARY OPERATION rather than by an edge case. Expecting it to go red after the fix would be wrong,
# and predicting that is the tell that a mutation set contains no characterization arm.
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
kt_ss_mark_inprogress "$TMP/o" "sess-mine" "mipr"

# O1 — THE CLAIM: an existing sessionId is REPLACED by the marking session's id.
grep -q '^sessionId: sess-mine$' "$TMP/o/SESSION.md" \
  && ok "O1 existing sessionId OVERWRITTEN by the marking session" \
  || bad "O1 sessionId overwrite" "an existing sessionId was NOT replaced — the case-3 state cannot arise, and the demote clauses' stated reason would be wrong"

# O2 — NON-VACUITY CONTROL, not a second claim. Block D owns body preservation; this exists only so O1
# cannot pass against a file the helper mangled into something holding no pickup at all.
grep -q 'O-SENTINEL-PRIOR-PROMPT' "$TMP/o/SESSION.md" \
  && ok "O2 control: the prior prompt survived the overwrite" \
  || bad "O2 control" "the body was lost, so O1 proves nothing about a file that still holds a pickup"

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
_Q_LIBS="plugin-claude-code/bin plugin-antigravity/bin plugin-cursor-template/scripts/aria plugin-openai-codex/bin"
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
#      cs/SESSION.md, which carried 374e75de under two different `at` values.
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

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
