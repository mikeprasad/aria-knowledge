---
description: "Mine your distilled knowledge corpus — memory feedback rows, rules backlogs, always-on indexes — for recurring corrections that deserve promotion to numbered standing rules. Clusters by theme, verifies every quote at its source file, ranks by cross-session recurrence (>=2 distinct sessions), and writes a rule ONLY on explicit approval. Opt-in. Trigger: '/audit rules', 'mine my corrections', 'promote my rules', 'audit my rules'."
argument-hint: "[promote <labels>]"
allowed-tools: Read, Glob, Grep, Bash, Write, Edit
---

# /audit rules — User-Rule Mining Sub-Audit

Canonical invocation: **`/audit rules`** (argument forms ride the umbrella too: `/audit rules
promote R1 R3`). The direct `/audit-rules` form is retained for compatibility and is not advertised.

Mine the corpus your corrections have already accumulated in — memory `feedback_*` rows and their
indexes, the rules backlog, staged `/audit style` output — for candidates that have earned promotion
to numbered rules in `rules/user-rules.md`. This is a DEPTH pass on one shape (recurring user
corrections → standing-rule candidates); `/audit knowledge` remains the breadth pass that
dispositions everything. Evidence-gated end to end: a candidate that cannot show dated, at-source
verified receipts across ≥2 distinct sessions does not get proposed, and nothing writes a rule
except an explicit per-run approval naming the candidates.

## Runtime Gate — Bash capability precondition

**Before Step 0:** check that the `Bash` tool is available. This skill needs it (corpus greps, the
digest regeneration in Step 7). **No Cowork counterpart of this skill exists** — do not offer one.
If Bash is NOT available, say so and ask: **"Stop here?"** (`y` / `n`)

- **`y` / no response** — exit cleanly; nothing scanned, nothing written.
- **`n`** — proceed in DEGRADED read-only mode: Steps 0–5 (analysis + report) using Read/Grep only,
  and Step 7 (promotion mechanics) is unavailable — state that plainly in the report rather than
  reporting any promotion as done.

**Opt-in only, never cadence-fired:** like `/audit style` and `/audit usage`, this sub-audit runs
only on explicit invocation. No SessionStart nudge, activity threshold, or cadence may fire it.

## Step 0: Config + Harvest Surfaces

Read `~/.claude/aria-knowledge.local.md`; resolve `knowledge_folder`. If unconfigured, stop:
"aria-knowledge is not configured. Run /setup to get started."

**If invoked as `promote <labels>`** (e.g. `/audit rules promote R1 R3`): skip harvest entirely.
Resolve the labels from the **newest staged block** this skill previously wrote in
`{knowledge_folder}/intake/rules-backlog.md` (Step 6's `stage` disposition persists candidates WITH
their R-labels exactly so a later session can approve without re-harvesting). If no staged block
exists, say so and offer a fresh run. On resolution, jump to Step 7 for the named candidates only.

Harvest surfaces, in priority order:

1. `{knowledge_folder}/rules/user-rules.md` — the existing rule set (dedupe + amendment target).
2. `{knowledge_folder}/intake/rules-backlog.md` — staged candidates, including `/audit style`'s
   receipt-gated output (that skill is this one's transcript-mining FEEDER; this skill never mines
   transcripts itself).
3. The user-memory directory for the current project (`~/.claude/projects/<cwd-encoded>/memory/`):
   `MEMORY.md` and the `feedback_*.md` topic files.
4. Any additional always-on index files that carry feedback rows — discovered by following the
   `@`-import chain from the project's CLAUDE.md lineage plus `[[link]]`/markdown-link references
   from `MEMORY.md` rows, **depth-bounded to 2 hops**. Anything deeper is out of harvest scope and
   the Step 5 scan-health section says so. Never a hardcoded path list — index layouts are
   user-specific.
5. `{knowledge_folder}/intake/insights-backlog.md` — **corroboration only, never a primary
   candidate source** (an insight alone is below the Step 4 bar until a second instance
   corroborates), and read only for entries newer than the boundary stamped in
   `{knowledge_folder}/logs/rule-audit-log.md` (created lazily; the boundary advances only on a
   stage/promote disposition, never on cancel).

## Step 1: Harvest Correction Candidates

Scan the surfaces for the correction signature: a dated verbatim user quote attached to a
behavioral instruction; a hard-prohibition clause ("NEVER…", "ALWAYS…") paired with an incident; a
row naming two or more instances; a backlog entry typed as a rule candidate.

**Cluster by THEME, not by row.** Rows that cross-link each other or describe one behavior from
different angles form ONE candidate (measured origin: the strongest candidate in this skill's
reference run spanned three memory rows describing one turn-close behavior).

## Step 2: Dedupe

Against `rules/user-rules.md` **by substance, not title** — a candidate duplicating an existing
rule is DECLINED with that rule cited. Against the plugin-managed `working-rules.md` — duplicating
a numbered universal rule is likewise a decline-with-citation. **Partial overlap yields the `amend`
disposition**, naming the exact rule (or memory row) and clause it would amend.

## Step 3: Verify at Source (the citation gate)

For every quote a candidate relies on, **open the topic file and confirm the quote and its date.**
An index row's slug or one-line summary is never evidence — a slug is an address, not an assertion,
and index rows go stale against their topic files. If a row and its topic file disagree, the
candidate carries the topic file's version, flagged, and the disagreement itself is surfaced in the
report.

Classify each candidate:
- **TRANSCRIPTION** — the user can be quoted saying it, verbatim and dated. Recordable with
  attribution on approval.
- **DERIVED** — generalized from incidents rather than stated by the user. Its writeup MUST state a
  falsifier the user can evaluate, and its approval framing says plainly that it is derived.

## Step 4: Rank + the Recurrence Bar

Rank by: instance count across **distinct sessions/arcs** (the load-bearing axis) · quote
availability · cost-per-miss (what each recurrence cost). Candidates with **≥2 distinct instances**
form the proposed set, labelled `R1..Rn`. Below the bar → the **watch list**, rendered in the
report with a named revisit trigger. Nothing harvested is silently dropped: proposed, watch,
declined-with-reason, or folded — every item lands in exactly one.

## Step 5: Report (the report IS the approval surface — nothing written yet)

Emit-all fixed structure; a zero state is a distinct signal, never an omitted section.

Per proposed candidate: rule statement · verbatim quotes with dates · instance count · current
home(s) · **falsifier** · what promotion costs (which rows collapse, which files get stamped) ·
TRANSCRIPTION/DERIVED tag · recommendation. Then: the watch list (each with its revisit trigger) ·
the declined list (each with its reason and the duplicated rule where applicable) · scan health
(surfaces read · quotes verified at source vs unverifiable · hop-bound exclusions).

## Step 6: Disposition (single gate, fail-closed)

```
[approve <labels> | all | all minus <labels>]  Promote the named candidates now (runs Step 7).
[stage]    (default) Write/refresh the ranked candidates into rules-backlog.md WITH their
           R-labels and recurrence evidence, for the normal /audit knowledge cadence.
           No rule is written.
[cancel]   Write nothing; the boundary does not advance.
```

The default never writes a rule. Promotion happens only on an explicit `approve` naming candidates
— Rule 23 embedded structurally. The staged block is the persistence surface for a later-session
`promote <labels>` re-entry. Advance the `rule-audit-log.md` boundary on stage/promote only.

## Step 7: Promotion Mechanics (only on approve, or via `promote <labels>` re-entry)

For each approved candidate, in order:

1. **Write the rule** into `rules/user-rules.md` (next `U<n>`, or apply the named amendment): a
   lead paragraph carrying the operative claim, Why with the dated quotes, How to apply,
   **Falsifier**, Origin with the approval stamp (who approved, when) and the source rows.
2. **Byte-check the lead:** run `bash ${CLAUDE_PLUGIN_ROOT}/bin/check-rule-lead-bytes.sh
   {knowledge_folder}/rules/user-rules.md`. The always-on digest builder truncates each rule's
   first paragraph at **240 BYTES** (multi-byte punctuation counts ×2–3) — a failing lead is
   reworded before proceeding, never shipped to truncate.
3. **Collapse each superseded source row** (memory index rows, any always-on index the candidate
   was harvested from) to a pointer that **keeps the recognition trigger** — never delete the cue;
   trigger fidelity outranks byte savings.
4. **Stamp each consumed topic file** with a one-line canonical-home banner above the body.
5. **Disposition consumed backlog entries**: demote the heading `###`→`####` with a disposition
   note; bodies preserved.
6. **Regenerate the always-on digest** by invoking `bash
   ${CLAUDE_PLUGIN_ROOT}/bin/session-start-rules.sh` with empty stdin — never by hand-editing
   `~/.claude/rules/aria-user-rules.md` (its header forbids it; the generator's newer-than guard
   makes the rerun cheap). Then verify: the emitted rule count includes the new rules, and **none
   of the NEW rules' digest lines carry a truncation ellipsis** (scope the check to the new rules —
   older rules may legitimately carry one).
7. **Check-before-create:** before writing any new artifact (an idea file, a backlog entry), search
   for a pre-existing one and amend it instead — parallel audit passes create these too.
8. **Report per-candidate outcomes and the instruction-surface delta.** A promotion should
   net-shrink the always-on load (rule + pointer ≤ the rows it replaces); report the delta either way.

## Invariants

- Never writes `working-rules.md` (plugin-managed). Promotion targets are user-owned surfaces only.
- Never runs on cadence; never fires from a hook.
- The default disposition writes no rule; approval is per-run and names its candidates.
- Transcript mining is out of scope by design — `/audit style` owns it and stages here. If a
  promoted rule's census ever shows a correction that existed only in transcripts, that is the
  named trigger to revisit this bound (and a capture-pipeline defect to fix at source meanwhile).
