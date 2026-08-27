# Plan — /audit rules sub-audit + audit verb migration (one shipping unit)

**Date:** 2026-08-27 · **Status:** ⛔ **SPENT — EXECUTED 2026-08-27 (same day), do NOT re-execute.**
Gate 2 was /prospect PROCEED-WITH-CHANGES with PA1–PA4 applied before execution (gate log:
`knowledge/logs/prospect/2026-08-27-file-audit-rules-and-verb-migration-plan.md`); the user's go
("A yes but only after everything is SPPP and validated") arrived after a delta-gate confirmation
that every artifact and post-gate change was covered.

**Execution record (T0–T8, all green):** T0 all four trip-wires passed (tree clean under
plugin-claude-code; census 134 within tolerance; Gate B baseline 19,622; ZERO functional matchers on
hyphen forms — the nudges were prose-only as predicted). T1–T3 as specced. T4: 111 lines / 34 files
swept under the reviewed dry-run diff with count assertion; two self-referential leftovers cleaned
(help alias parentheticals, nudge fallback). T5a: suite **280 passed / 0 failed, bare exit 0**;
three mutations each caught by their NAMED assertion (budget→9999 reddened AR2/AR2b/AR3; an
injected bare hyphen line reddened AR14; a cadence mention reddened AR13), all restores
cmp-byte-identical, residue sweep 0. T5b dogfood on a fixture corpus: AC1 (3 cross-linked rows →
ONE candidate), AC2 (2-session proposed / 1-session watch), AC3 (duplicate declined citing the
fixture U1), AC6 (contradicting index row surfaced, topic file's version carried), AC5 live
(fixture rules file byte-untouched). T6 done — incl. a pre-existing gap found and fixed: `/help`
had never gained a `/audit usage` row (v2.41.0 omission). T7: Gate B settled **19,653 of 19,968 —
no raise needed** (the four demotions freed ~1,150 B, funding the umbrella absorption and the new
451 B description; net +31 B vs baseline). T8: hygiene gate clean (exit 0, self-test passed),
drift --quiet silent, MC6 cowork untouched (0 changes).

**Deviations from the letter, all recorded:** MC2 refined at execution — the compat documentation
must itself name the hyphen forms, so the ratchet's rule is "a hyphen command form is legal only on
a line carrying 'compat'" (the AC as drafted was unsatisfiable-by-design); T3 also retitled the two
hyphen-form H1s (a T4 item executed in place, named in the scope checks); the `.gitignore` root
file was dirty from a parallel session and was excluded from staging.
**Specs (both GATED):** `../specs/2026-08-27-audit-rules-sub-audit-design.md` (W1) ·
`../specs/2026-08-27-audit-verb-migration-design.md` (W2). The specs are authoritative on design;
this plan is authoritative on order and acceptance.
**Target:** plugin-claude-code only. Ports: antigravity/cursor inherit at next build-script run,
codex hand-sync, cowork explicitly untouched (W2 M7). No release ceremony in this plan — version
bump + release is its own decision after execution.

## T0 — Preconditions (trip-wires; a failed T0 item HALTS, it does not degrade)

1. Working tree: confirm which files under `plugin-claude-code/` are dirty from parallel sessions
   (`git status --porcelain -- plugin-claude-code/`); stage THIS plan's files by exact path only,
   never `-A`. Expect the repo many commits ahead of origin — do NOT push.
2. Re-census the hyphen forms **from the repo root** (W2 MA1): expect ≈136+1 slash-leading
   occurrences; if the shape differs wildly (±30%), re-derive the sweep list before editing.
   ⚠ Compare like units — the census counts slash-leading occurrences only.
3. Gate B baseline: run the awk sum (release.sh:78 idiom) and record it (expected ≈19,622 of
   19,968; parallel sessions move it — record, don't assume).
4. M4 matcher census: grep `bin/` for any CONDITIONAL keyed on a typed hyphen form (not prose).
   Expected zero; a hit converts that edit from prose-sweep to logic-change and needs its own care.

## Tasks (execution order)

**T1 — Write `skills/audit-rules/SKILL.md`** per W1 spec §4 (Steps 0–7 verbatim from the spec:
config+surfaces with the A5 discovery algorithm and A4 insights bound · harvest/cluster · dedupe ·
citation-gate classify · rank with the ≥2-distinct bar + watch list · emit-all report ·
fail-closed disposition with R-labels persisted in the staged backlog block (A2) · promotion
mechanics checklist incl. the ≤240-BYTE lead check and `bin/session-start-rules.sh` regeneration).
Frontmatter: real ~400 B description (mining triggers: "mine my corrections", "promote my rules",
"audit my rules"), `argument-hint: "[promote <labels>]"`, `allowed-tools: Read, Glob, Grep, Bash,
Write, Edit`. Runtime gate = Bash capability precondition per D13 (stop-or-degraded; never a
Cowork redirect). Acceptance: file exists; every spec step number appears; description ≤ the byte
count recorded for T7's budget arithmetic.

**T2 — Rewrite `skills/audit/SKILL.md`**: (a) Step 0 grammar gains `rules` AND argument
passthrough — `/audit <verb> [args…]` delegates WITH trailing args (W2 M1); *(PA1)* **args are
legal only AFTER a recognized verb** — an unrecognized first token still hits the unknown-verb
branch exactly as today; passthrough never weakens the never-silently-guess rule; (b) Step 1 menu entry 5
= rules, `all` = 6; (c) Step 3 `/audit all` gains the fifth leg after `usage`; (d) unknown-verb
list + never-auto rule include `rules`; (e) Back-Compat section REWRITTEN: space forms canonical,
hyphen forms unadvertised compat, cadence nudges name space forms; (f) description absorbs the four
sub-audits' trigger vocabularies + W1's. Acceptance: MC1's grammar assertion (args named
explicitly); MC5 (every absorbed phrase greps in the description); "four sub-audits" → five
everywhere in the file.

**T3 — Demote four sub-skill descriptions** (`audit-knowledge`, `audit-config`, `audit-style`,
`audit-usage`): one-line internal description + "invoke via `/audit <verb>`"; body top gains the
canonical-invocation line (W2 §4.2). *(PA2 — precise form:)* the per-file diff shows ONLY the
description change plus that ONE added body line; any other hunk is a scope failure.
Legacy aliases (e.g. `/config-audit`) leave the descriptions (W2 M6).

**T4 — Prose sweep** under the M3 slash discriminator: 20 remaining live skill bodies, 7 template
files, `rules/aria-rules.md:106` (MA1), and the 4 bin scripts' prose strings — `session-start-check.sh`
cadence nudge included (post-T0.4, prose-only). `skills/.archived/*` untouched (M5). *(PA3:)* **no
blind tree-wide sed** — per-file reviewed edits, each file's diff read before moving on; the M3
discriminator makes the class unambiguous, not the context. Acceptance:
MC2 (zero slash-hyphen forms in live tree, positive control on archived copies) + MC3 (slashless
delegation-name count before == after).

**T5 — Tests** *(rewritten by gate 2 PA4 — a SKILL.md is instructions a MODEL executes, so the
shell suite can only assert TEXT invariants and bin-script behavior; promising fixture tests for
judgment steps is a green that cannot exist).* Two halves:

**T5a — shell-assertable suite** (`tests/test-audit-rules.sh` + migration assertions):
- **New bin helper `bin/check-rule-lead-bytes.sh`** — extracts each `### U<n>` rule's first
  paragraph from a given user-rules file and fails if any exceeds 240 BYTES (the digest builder's
  own measure). This makes W1's AC4 a real, mutation-provable shell test: the 250-byte/<240-char
  fixture lead must FAIL it, and removing the byte measure must redden the test. The SKILL.md's
  Step 7.2 invokes this helper rather than describing arithmetic in prose.
- Text invariants: AC5 (disposition block's fail-closed wording), AC7 (dispatcher grammar knows
  `rules` + MC1's explicit-args clause), AC8 (no cadence surface names `audit-rules`), MC2 as a
  **permanent ratchet** (zero slash-hyphen forms in the live tree, positive control on the
  archived copies), MC3, MC5, MC6.
- Every negative observed RED first via its named mutation; restores by byte-backup + `cmp` +
  derived-artifact invalidation where applicable (U2's third condition). Full suite `0 failed`,
  bare exit 0.

**T5b — dogfood validation** (the behavioral half — AC1, AC2, AC3, AC6): run `/audit rules` live
against a scratch knowledge folder seeded with the fixture corpus (3-row cluster → ONE candidate ·
2-session candidate proposed · 1-session candidate on the watch list · duplicate declined naming
the rule · contradicting index row surfaced). This is how `/audit style` was validated (v2.40.0,
"dogfood-validated live"). Record the run's report in the execution notes; these ACs are dogfood
acceptance, NOT suite assertions, and no green is claimed for them from the shell suite.

**T6 — Docs.** `/help` table: add `/audit rules`, convert the four hyphen rows to `/audit <verb>`
forms; README capability prose; QUICKSTART if it names hyphen forms (census will say); CHANGELOG
entry covering BOTH workstreams — the new sub-audit, the retirement + compat posture, and the
Gate B before/after numbers (MC4).

**T7 — Gate B settlement.** Re-run the awk sum. Expected: W2's demotions free more than W1's
description costs (net decrease). If the total still exceeds 19,968, raise `ARIA_SKILL_BUDGET`
deliberately in the same commit with a justification line (release.sh:69's own instruction; W1
spec D12-as-amended). Record both numbers in the CHANGELOG (MC4).

**T8 — Close.** Full plugin suite + repro suites green (bare exit codes); `bin/check-public-hygiene.sh`
clean (public repo — fixtures must use placeholder names, never real project identifiers);
`check-port-drift.sh --quiet` run report-only; commits staged by exact path, one commit per
workstream (W1 skill+tests, W2 migration+tests, docs may ride the second). MC6 (cowork untouched)
asserted by diff scope. ⛔ NO push, NO version bump, NO release — those are post-execution
decisions for Mike.

## Validation footer (U11 — named symbols verified against source this session)

`audit/SKILL.md` Step 0/1/3 + Back-Compat (read in full) · `audit-style/SKILL.md` (read in full —
the structural template) · `bin/session-start-rules.sh` + `bin/lib-user-rules.sh` (read; generator
exercised live twice) · `release.sh:69-92` Gate B (read; awk idiom reproduced live, 19,622 measured)
· `bin/session-start-check.sh` (named in census; M4 census at T0.4 before edit) ·
`bin/check-public-hygiene.sh` + `check-port-drift.sh` (named by repo docs; invoked report-only at T8)
· `tests/` conventions (suite runner + repros per repo docs). The manual U20–U25 promotion run
(2026-08-27, this workspace) is the reference implementation for T1's Step 7 mechanics.
