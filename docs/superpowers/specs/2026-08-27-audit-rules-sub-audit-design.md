# /audit rules — user-rule mining sub-audit (design)

**Date:** 2026-08-27 · **Status:** GATED — gate 1 /prospect PROCEED-WITH-CHANGES 2026-08-27, amendments A1–A6 applied in place (gate log: `knowledge/logs/prospect/2026-08-27-file-audit-rules-sub-audit.md`); gate 2 runs on the plan · **Target:** plugin-claude-code (canonical; other ports tracked-drift)

## 1. Problem

A user's corrections accumulate as memory rows, backlog entries, and index lines faster than any
process promotes them into numbered standing rules — and a memory row has measurably weaker standing
than a rule: the maintainer's corpus held one behavior corrected **six times across three memory
rows** while the rows sat unpromoted, and rows were violated repeatedly *while recorded*. The
existing promotion path (`/audit-knowledge`'s backlog review) dispositions everything but goes deep
on nothing: it routes candidates, it does not census recurrence, verify quotes at source, rank, or
execute the multi-surface promotion mechanics. On 2026-08-27 the full pipeline was run **by hand**
— harvest → dedupe → classify → rank → approval table → promotion of six new rules — and every step
proved mechanizable. That manual run is this design's reference implementation.

## 2. Decision summary

| # | Decision | Basis |
|---|---|---|
| D1 | New facet skill **`audit-rules`**, verb `rules` in the `/audit` dispatcher | user ruling 2026-08-27 ("attach to /audit"); family precedent `/audit usage` (v2.41.0) |
| D2 | v1 harvests **distilled surfaces only** — never transcripts | measured: the manual run found all 7 candidates without transcripts; `/audit style` already owns transcript mining and stages its output where this skill harvests |
| D3 | Candidate unit is a **theme cluster**, not a row | the strongest manual candidate spanned 3 memory rows describing one behavior |
| D4 | Classify each candidate **TRANSCRIPTION vs DERIVED** (Rule 23's one-step test), with a citation gate: an index row's slug is never evidence — open the topic file | a rule draft in the manual run nearly shipped a falsified claim borrowed from an unopened slug |
| D5 | Propose only at **≥2 instances in distinct sessions/arcs**; below-bar candidates go to a visible **watch list**, never silently dropped | single-arc clusters held with a named revisit trigger in the manual run |
| D6 | Disposition vocabulary: `new rule · amend existing rule/row · fold · decline-with-reason · hold-below-bar` | the manual run used all five |
| D7 | Approval is **fail-closed and human-only**: the skill never writes a rule without an explicit per-run approval naming the candidates | Rule 23; mirrors `/audit style`'s "default never writes memory" invariant |
| D8 | **`promote <labels>` re-entry** runs only the promotion mechanics for an already-presented set | approval may arrive in a later session; re-harvesting to honor it wastes the run and can shift labels |
| D9 | Promotion mechanics are a fixed checklist incl. a **≤240-BYTE digest-lead check** and regeneration via `bin/session-start-rules.sh` (the sole sanctioned digest writer) | the manual run shipped a truncated digest lead because the check measured chars while the generator truncates bytes |
| D10 | The skill names only plugin-known surfaces; extra always-on index files are handled **generically, keyed on where the harvest found each candidate** | the plugin is public; a user's private index layout must not be hardcoded |
| D11 | **Opt-in only, never cadence-fired**; `/audit-knowledge` couples by a one-line pointer | matches style/usage posture |
| D12 *(amended by gate 1 A6)* | Gate B: write a **real (~400 B) description** and raise `ARIA_SKILL_BUDGET` **deliberately in the adding commit** with justification — never a crippled description, never trimming another skill's | live-measured 346 B headroom of 19,968 cannot fit a functional description; `release.sh:69`'s own comment names the deliberate raise as the intended path for a skill-adding commit; v2.41.0's release note predicted this skill would trip the budget |
| D13 | Runtime gate is a **Bash capability precondition**, not a Cowork redirect | no Cowork counterpart exists; the `/auto` F4 lesson (2026-08-26): a colliding-name gate template applied to a non-colliding skill produces a dead redirect |
| D14 | Shipped tests are **fixture-based** with mutation-proven negatives | the repo is public; the maintainer's corpus cannot ship as a fixture |
| D15 | v2 trigger for transcripts, named now: add a transcript pass only if a promoted rule's census shows a correction that existed **only** in transcripts — otherwise that gap is a capture-pipeline defect to fix at source | keeps v1 scope honest without foreclosing v2 |

## 3. What it is not

- **Not `/audit-knowledge`** — that is a breadth pass dispositioning all knowledge; this is a depth
  pass on one shape (recurring user corrections → standing-rule candidates).
- **Not `/audit style`** — that mines transcripts bottom-up for *revealed* style rules and stages
  them; this mines the *already-distilled* corpus for promotion-ready candidates. Style is a feeder:
  its staged output lands in `rules-backlog.md`, which this skill harvests.
- **Not an `/extract` mode** — extract is session-scoped and runs at close under time pressure;
  this is a cross-session pass with an interactive approval loop.
- **Never a writer of `working-rules.md`** — that file is plugin-managed. Promotion targets are the
  user-owned surfaces only: `rules/user-rules.md`, memory `feedback_*.md`, project-tier
  `working-rules.md` — the same three targets `/audit-knowledge` already defines.

## 4. Skill flow (audit-rules/SKILL.md)

**Step 0 — config + surfaces.** Resolve `knowledge_folder` from `~/.claude/aria-knowledge.local.md`
(stop with the standard "run /setup" message if unconfigured). Harvest surfaces, in priority order:

1. `{knowledge_folder}/rules/user-rules.md` — the existing rule set (dedupe target, amendment target).
2. `{knowledge_folder}/intake/rules-backlog.md` — staged candidates (incl. `/audit style` output).
3. The user-memory directory for the current project (`~/.claude/projects/<cwd-encoded>/memory/`):
   `MEMORY.md` and `feedback_*.md` topic files.
4. Any always-on index files that carry feedback rows — *(concretized by gate 1 A5:)* discovered by
   following the `@`-import chain from the project's CLAUDE.md lineage plus `[[link]]`/markdown-link
   references from `MEMORY.md` rows, **depth-bounded to 2 hops**; anything deeper is out of harvest
   scope and the scan-health section says so. Never a hardcoded path list (D10).
5. `{knowledge_folder}/intake/insights-backlog.md` — *(bounded by gate 1 A4:)* **corroboration only,
   never a primary candidate source** in v1 (an insight alone is below the D5 bar until a second
   instance corroborates), and read only for entries newer than the boundary stamped in
   `{knowledge_folder}/logs/rule-audit-log.md` (created lazily, mirroring `/audit style`'s run log;
   the boundary advances only on a stage/promote disposition, never on cancel).

**Step 1 — harvest correction candidates.** Scan for the correction signature: a dated verbatim
user quote attached to a behavioral instruction, a `⛔`/"NEVER"/"ALWAYS" clause with an incident, a
row naming ≥2 instances, or a backlog entry typed as a rule candidate. Cluster by THEME (D3): rows
that cross-link each other or describe one behavior from different angles form one candidate.

**Step 2 — dedupe.** Against `user-rules.md` (by substance, not title) and against the plugin's
`working-rules.md` (a candidate that duplicates a numbered universal rule is declined with the rule
cited). Partial overlap → the `amend` disposition, naming the rule/clause it would amend.

**Step 3 — verify at source (citation gate, D4).** For every quote a candidate relies on, open the
topic file and confirm the quote and its date. An index row's slug or one-line summary is never
evidence. Classify: **TRANSCRIPTION** (the user can be quoted saying it, dated) vs **DERIVED**
(generalized from incidents — needs explicit approval framing, and its writeup must state a
falsifier the user can evaluate).

**Step 4 — rank + bar (D5).** Instance count across *distinct sessions/arcs* (the load-bearing
axis), quote availability, cost-per-miss (what each recurrence cost). ≥2 distinct instances →
proposed set, labelled `R1..Rn`. Below bar → **watch list**, rendered in the report with its named
revisit trigger. Nothing harvested is silently dropped.

**Step 5 — report (the report IS the approval surface; nothing written yet).** Emit-all fixed
structure, mirroring `/audit style` Step 5's zero-state discipline. Per candidate: rule statement ·
verbatim quotes with dates · instance count · current home(s) · falsifier · what promotion costs
(which rows collapse, which files get stamped) · TRANSCRIPTION/DERIVED tag · recommendation.
Then the watch list, the declined list (each with its reason), and scan health (surfaces read,
quotes verified at source vs unverifiable).

**Step 6 — disposition (single gate, fail-closed).**

```
[approve <labels>|all|all minus <labels>]  Promote the named candidates now (runs Step 7).
[stage]    (default) Write/refresh the ranked candidates into rules-backlog.md WITH their
           R-labels and recurrence evidence, for the normal /audit-knowledge cadence.
           No rule is written.
[cancel]   Write nothing.
```

*(Gate 1 A2 — label persistence:)* the staged backlog block is itself the persistence surface for
re-entry: a later-session `promote <labels>` resolves labels from the **newest staged block** in
`rules-backlog.md`. No separate report file is written; if no staged block exists, `promote` says so
and offers a fresh run.

The default never writes a rule — promotion happens only on an explicit `approve` naming candidates
(Rule 23 embedded structurally, same posture as `/audit style`'s promote path).

**Step 7 — promotion mechanics (only on approve; also the whole body of `promote <labels>` re-entry, D8/D9).**
For each approved candidate, in order:

1. Write the rule into `rules/user-rules.md` (next `U<n>`; or apply the amendment): lead paragraph
   carrying the operative claim, Why with dated quotes, How to apply, **Falsifier**, Origin with the
   Rule 23 approval stamp (who approved, when) and the source rows.
2. **Digest-lead check in BYTES:** the always-on digest builder (`bin/lib-user-rules.sh`) truncates
   each rule's first paragraph at 240 measured in bytes — verify each new/changed lead fits, and
   after regeneration grep the emitted digest for a truncation ellipsis on the new rules (the
   check must be able to fail: see AC4).
3. Collapse each superseded source row (memory index, any always-on index the candidate was
   harvested from) to a **pointer that keeps the recognition trigger** — never delete the cue.
4. Stamp each consumed topic file with a one-line canonical-home banner above the body.
5. Disposition consumed backlog entries: demote heading `###`→`####`, disposition note, body
   preserved (the backlog's own Rule 6 convention).
6. Regenerate `~/.claude/rules/aria-user-rules.md` by invoking `bin/session-start-rules.sh` with
   empty stdin — never by hand-editing (the file's header forbids it; the script's `-nt` guard
   makes the rerun cheap). Verify the emitted rule count and the absence of new truncations.
7. **Check-before-create:** before writing any new artifact (idea file, backlog entry), search for
   a pre-existing one and amend it instead (in the manual run a parallel audit pass had already
   created the artifact this step would have duplicated).
8. Report the per-candidate outcome and the instruction-surface delta (a promotion should net-shrink
   the always-on load: rule + pointer ≤ the rows it replaces).

**Runtime gate (D13):** before Step 0, check Bash availability. If absent: state that this skill
needs Bash (grep across the corpus, digest regeneration) and that no Cowork counterpart exists;
offer to stop (`y` = stop cleanly / `n` = proceed with degraded, read-only analysis and NO Step 7).
Never name or offer a nonexistent namespaced variant.

## 5. Dispatcher wiring (`/audit`)

Following the v2.41.0 `usage` precedent exactly: `rules` added to the Step 0 grammar, the Step 1
menu (entry 5, `all` becomes 6), a fifth leg in `/audit all` (sequence position: after `usage`),
the unknown-verb valid-verbs list, the never-auto rule (opt-in like style/usage), and every "four
sub-audits" prose count → five. Argument-carrying invocations ride the umbrella —
`/audit rules promote R1 R3` — via the dispatcher **argument passthrough** the companion migration
workstream introduces (its M1/M8; see `2026-08-27-audit-verb-migration-design.md`). The direct
hyphen form keeps working as unadvertised compat, per that workstream's retirement posture. *(Gate 1 A3:)* interactive gates inside an `/audit all` leg are sanctioned by
the dispatcher's own Step 3 ("Let it run its full flow **(including any user-review prompts)** to
completion") — no special-casing needed.

**Docs surfaces** *(added by gate 1 A1 — the cited precedent shipped these and the draft omitted
them)*: a `/help` command-table row for `/audit rules`, a README capability mention, and the
CHANGELOG entry — all in the adding commit, mirroring v2.41.0's file list.

## 6. Gate B budget (D12)

Live-measured 2026-08-27 (awk sum, the same instrument Gate B runs): 19,622 of 19,968 bytes —
346 B headroom, which cannot fit a functional description (the sibling `audit-style`'s is ~430 B).
*(Amended by gate 1 A6:)* Write a **real ~400 B description** (what it mines, the recurrence bar,
trigger phrases) and **raise `ARIA_SKILL_BUDGET` deliberately in the adding commit** with a
justification line — `release.sh:69`'s own comment names this as the intended path when adding a
skill, and v2.41.0's release note explicitly predicted the next skill would trip the budget.
Re-measure at execution (parallel sessions move the total). Do NOT trim another skill's description
to make room (a silent capability regression to fund an unrelated feature), and do NOT ship a
crippled description to squeeze under (optimizing the proxy metric over the outcome).

## 7. Acceptance criteria

- **AC1 (harvest + cluster):** a fixture corpus where one behavior is described by three
  cross-linked memory rows yields ONE candidate, not three.
- **AC2 (bar):** a fixture candidate with quotes from two distinct session ids is proposed; an
  identical candidate whose quotes share one session id lands on the watch list. The negative must
  be seen to fail if the ≥2-distinct check is removed (mutation-proven, per the `/audit style`
  Step 3 Rule 36 note).
- **AC3 (dedupe):** a fixture candidate whose substance duplicates an existing `user-rules.md` rule
  is declined with that rule named; a partial overlap yields an `amend` disposition.
- **AC4 (digest byte check):** a fixture rule lead of 250 bytes (chars < 240 via multi-byte
  punctuation) FAILS the Step 7.2 check — proving the check measures bytes, not chars. Removing
  the check must redden this test.
- **AC5 (fail-closed approval):** with no `approve`, no run may modify `user-rules.md` — asserted
  by byte-comparison of the fixture file across a full `stage`-disposition run.
- **AC6 (citation gate):** a fixture where the index row's summary contradicts its topic file must
  surface the contradiction rather than cite the row (the candidate carries the topic file's
  version, flagged).
- **AC7 (dispatcher):** `/audit` grammar, menu, `all`, and unknown-verb list all know `rules`;
  `/audit all` runs five legs.
- **AC8 (no cadence trigger):** grep-assert that no SessionStart/cadence surface names
  `audit-rules` (mirror of the style/usage never-auto invariant).

## 8. Non-goals

Transcript mining (v2, trigger in D15) · automatic/cadence runs · writing `working-rules.md` ·
replacing `/audit-knowledge`'s breadth pass · any write without explicit per-run approval ·
porting in this release (canonical-only; cowork's description cap is already near its limit and
the other ports are tracked-drift by standing convention).

## 9. Open questions (for gate 1)

- OQ1: Should the ranked report persist to a dated file (mirroring `/audit style`'s card) so a
  later-session `promote` can resolve labels without re-harvesting, or is the staged backlog entry
  (Step 6 `stage`) a sufficient persistence surface for re-entry?
- OQ2: Does `/audit all` including a candidate-approval loop mid-sequence break the "each leg runs
  to completion" contract in an unattended run? (Style/usage have the same shape; confirm the
  precedent's behavior rather than assuming.)
- OQ3: The insights-backlog is large (megabytes in mature corpora). Does Step 1 need a bounded
  window (e.g. entries since the last run's boundary) plus a run-log, mirroring `/audit style`
  Step 0's incremental-scope machinery?
