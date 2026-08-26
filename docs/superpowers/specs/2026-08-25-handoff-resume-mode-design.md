# Design spec — `/handoff resume`

**Status:** GATED 2026-08-25 — `/prospect` verdict **PROCEED-WITH-CHANGES**; all changes applied
below in the same edit that records them. Gate log:
`knowledge/logs/prospect/2026-08-25-file-handoff-resume-mode.md`. **Date:** 2026-08-25.
**Repo:** `aria-knowledge` (skill + SessionStart-directive change).
**Requested by:** Mike, 2026-08-25 — "add a command to /handoff which is /handoff resume which would
load the auto resume using the session.md prompt BUT if there are more than 1 unconsumed prompts,
then summarize and present them for the user to choose, optionally also recommend combining them if
recommended" + "resume prompts should always be checked for staleness, either at summarization
before presentation or at/after user selection".

⚠ **Not committed.** A parallel session is live in this repo (Mike, 2026-08-25). Written and left
for review rather than committed.

---

## 1. The problem, measured

A `SESSION.md` can hold several still-valid next-session prompts: one active (`## Next session
prompt`) plus N demoted-but-unconsumed entries. Measured across the workspace 2026-08-25:

| project | candidates | active | pending |
|---|---:|---:|---:|
| `aria` | 3 | 1 | 2 |
| `proj-a` | 3 | 1 | 2 |
| `proj-b` | 2 | 1 | 1 |
| `proj-c` | 2 | 1 | 1 |
| `proj-d/proj-d-app` | 2 | 1 | 1 |
| `proj-d` | 1 | 0 | 1 |

**Multi-candidate is the norm, not the edge case** — 5 of 6 projects holding pending entries have
≥2 candidates.

⭐ **The feature has already been invented by hand.** `proj-a/SESSION.md`'s *active* prompt reads:
*"Verify state, read BOTH pending handoffs below, then pick one (DEV-1442 AC8 is the stronger
candidate)."* Someone hand-wrote the missing capability into a prompt. That also fixes the expected
output shape: **a pick, with a recommendation** — not a merge.

## 2. What already exists — this composes, it does not build

`bin/session-start-check.sh:309` already emits a SessionStart directive that: locates `SESSION.md`;
auto-resumes without confirmation when the opening message contains "handoff"; otherwise states
`lastEvent` + age and asks y/n; applies `session_stale_days` (default 7) with a
`[resume / archive / keep]` branch; and mentions pending entries.

`bin/lib-session-state.sh`'s `kt_ss_ledger_add` stores **full fidelity** — `- focus:`, `- next:`,
and the complete multi-line `- prompt:`. ⛔ The claim in `aria/aria-knowledge/CLAUDE.md` that
demotion stores a "single-line prompt" is **false**; measured, it stores the whole opener.

⇒ **The summary fields already exist per entry, so the list needs no LLM synthesis**, and `at:` is
per-entry, so staleness is computable mechanically.

## 3. Gaps — three, all measured

- **G1 — no command surface.** `/handoff resume` exists nowhere (grep: one unrelated hit in
  `audit-style/extract-user-prose.py`). The capability is reachable only at session start, once per
  session, only if the hook fires. Decline it, or arrive mid-session, and there is no way back in.
- **G2 — staleness is checked on the active prompt only.** The directive says *"If **the prompt's**
  'at' is older than session_stale_days"* — singular. Pending entries are offered with **no
  staleness check at all**. This is exactly Mike's second message, and it is the multi-prompt case.
- **G3 — a pending entry with no active sibling may surface nothing.** The pending clause is an
  `ALSO:` hanging off *"If it exists with a non-empty '## Next session prompt' block"*. Measured:
  `proj-d` has pending=1, active=0 — the precondition fails and the entry is invisible.

## 4. Decisions

### D1 — staleness is shown at summarization **and** gated at selection (option 1c)

**Decided on measurement, not preference. 5 of 8 unconsumed entries are stale (≥7d):**

| project | age |
|---|---:|
| `aria` | 64d, 63d |
| `proj-b` | 39d |
| `proj-d/proj-d-app` | 33d |
| `proj-d` | 8d |
| `proj-a` | 4d, 1d |
| `proj-c` | 1d |

62% of the pending corpus is stale, two entries by **two months**. A list that did not carry age
would present mostly-dead options as live — the failure is the common case, not the tail. So every
row carries a freshness verdict, **and** selecting a stale entry requires a confirm that offers
`[resume / archive / keep]`, reusing the verbs the SessionStart directive already defines.

⛔ **AMENDED BY THE GATE — `archive` is SPLIT OUT (S5b), and the reason is that it does not exist.**
The draft said *"archive must be reachable from the list"* on the strength of the SessionStart
directive's prose. Measured: `grep -rn 'Archived sessions|kt_ss_ledger_archive'` returns **only the
two prose directives** — there is no function that moves an entry under `## Archived sessions`.
So archive is **new write machinery**, which contradicted this spec's own AC8. This unit ships
`[resume / keep]`; archive becomes its own unit with its own helper.

⚠ The motivation stands: `aria`'s two June entries are exactly the population that should leave the
list, and nothing evicts them by design ("time never evicts"). That is an argument for building
S5b, not for smuggling it in here.

### D2 — combining is recommended only on same-root + disjoint `next:` (option 2a)

The real case argues against a looser rule: `cs`'s own hand-written instruction asks for **"pick
one … the stronger candidate"**, and its two pending `next:` fields overlap heavily (both open
"⛔ NOTHING IS BLOCKED ON US" and both begin with verify-state). Recommending a combine there would
be wrong. Never-recommend (2b) is refuted by the request itself. So: offer a combine **only** when
candidates share a project root and their `next:` fields name disjoint work, presented as an extra
numbered option, never auto-selected.

### D3 — `/handoff resume` sources the active prompt and pending entries as ONE candidate set

Closes G3 by construction rather than by patching the directive's precondition.

## 5. ⛔ The parser is the hard part — measured, not anticipated

The ledger has **four independent format axes**, and a naive parser silently drops candidates:

1. **Two headings** — `## Pending handoffs` (current) and `## Prior sessions` (legacy,
   grandfathered by `kt_ss_ledger_add` and still live in `aria/SESSION.md`).
2. **Two terminators** — the explicit `<!-- aria:entry-end -->` marker, and *nothing* on legacy
   entries. **Measured: `aria` has 2 unconsumed entries and 0 terminators; `df` has 1 and 0.**
   ⇒ **3 of 8 unconsumed entries (37.5%) are invisible to a terminator-based parser**, with no
   error. A terminator-only parse must fall back to "next `### ` or next `## `".
3. **Two prompt serializations** — `- prompt: |` followed by an indented YAML block scalar (legacy),
   and `- prompt:` followed by raw unindented lines (current).
4. **Three-plus header state forms** — `· handoff · unconsumed`, `· consumed <ts> by <sid>`, and
   `· in-progress (demoted, UNFINISHED) · unconsumed`.

**Acceptance must include a negative control: a fixture holding one legacy and one current entry,
asserting both appear.** A parser that finds 5 of 8 looks exactly like a `SESSION.md` with 5
entries.

## 6. Acceptance criteria

- **AC1** `/handoff resume` is a declared mode: `argument-hint`, description triggers, Step 0 parse.
  ⚠ Step 0's fallback **enumerates the valid modes verbatim** ("Use '/handoff', '/handoff auto',
  '/handoff brief', or '/handoff snap'"). Update that string too, or the error lists 4 of 5.
- **AC2** One candidate → states `focus` + age, confirms, executes. Zero → says so, does not error.
- **AC3** ≥2 candidates → a numbered table of `focus` / `next` / age / freshness, built from the
  stored fields with **no synthesis**, followed by a pick.
- **AC4** Every row carries a freshness verdict against `session_stale_days`; picking a stale row
  requires a confirm offering `[resume / archive / keep]`.
- **AC5** ⛔ **Legacy parity:** a fixture holding one legacy entry (`## Prior sessions`, no
  terminator) and one current entry yields **2** candidates. Mutation: remove the legacy fallback →
  the test must go red naming the dropped entry.
  ✅ **SHRUNK by the gate — the fixture EXISTS and already carries the legacy arm.** Extend
  `tests/fixtures/session-contract-vendored/handoff-multi-session.SESSION.md` (which already holds
  `### sess-old · … · handoff · unconsumed` under `## Prior sessions`, no terminator) with one
  current-format entry. Do not author a new fixture. Suite: `tests/repros/session-state.sh`.
- **AC6** A `SESSION.md` with pending entries and **no** active prompt still lists them (G3).
- **AC7** Combine is offered only under D2's predicate, is never auto-selected, and its absence is
  not an error.
- **AC8** Read-only until a selection is made. Marking consumed reuses
  `kt_ss_ledger_mark_consumed`; **this unit introduces no new write path** — which is why archive is
  S5b rather than part of S5.
  ⛔ **Guard required, found by the gate:** that helper interpolates the caller's sid into an **awk
  regex**, unescaped — `$0 ~ ("^### " sid " ")`. aria's live legacy sid is
  `e95b0202 (contract-coherence)`; the parentheses are regex metacharacters that happen to form a
  group matching the same literal, so it matches **by luck**. A sid containing `[`, `*` or `.`
  would mis-match or over-match silently. Extract sid as the text before the first ` · ` and match
  it **literally**, not as a pattern.
- **AC9** Gate B measured after the description edit, not asserted. Headroom at authoring: **427 B**
  (19,541 / 19,968).

## 7. Risks

⚠ Per the `unsourced-risk-section` pattern (canonical 2026-08-20), each item below is a claim the
corpus can answer, and was measured rather than argued.

- **The parser drops legacy entries** — measured at 3 of 8, not hypothesised. Mitigated by AC5 with
  a mutation.
- **Gate B headroom** — 427 B measured. The description gains one mode token; if it exceeds, trim
  rather than raise, per the gate's own instruction.
- **Overlap with the SessionStart directive** — ⛔ **worse than drafted, and already realised.** The
  directive is **byte-identical in two shipped files** — `bin/session-start-check.sh:309` and
  `bin/session-start-rules.sh:102`, md5 `c8e2f2ce…` both. So this is not a future drift risk from
  adding a skill; the contract is restated in two places **today**, independent of this feature.
  ⚠ **S9 is DEFERRED**: a parallel session is editing `session-start-rules.sh` right now, and
  de-duplicating a contract that predates this work belongs in its own unit rather than folded in
  here.

## 8. Out of scope

Changing `kt_ss_ledger_add`'s format; auto-archiving aged entries (time must not evict); porting to
cowork/codex/cursor/antigravity (tracked-drift, Claude-Code-canonical this round); any change to
`/handoff`'s write modes.
