# Rule 23 — Scope, Exemption, and Revocation — Design

**Date:** 2026-08-26
**Status:** GATED — gate 1 (`/prospect`) RUN 2026-08-26, verdict **PROCEED-WITH-CHANGES**.
All four required changes (C1–C4) applied in the same session that ran the gate. Gate report:
`knowledge/logs/prospect/2026-08-26-file-rule-23-scope-exemption-revocation.md`.
**No code yet — awaiting the implementation plan and gate 2.**
**Scope:** `plugin-claude-code` ONLY, by Mike's ruling 2026-08-26 ("B i" — canonical source
only). The other four ports (`plugin-antigravity`, `plugin-openai-codex`,
`plugin-claude-cowork`, `plugin-cursor-template`) keep the current Rule 23. This is the
same single-port precedent as the `session_state_tracked` fix.
**Requested by:** Mike, 2026-08-26 — "A and B" (amend scope + exemption; add the revocation
half), then "A spec prospect plan prospect".
**Measured at:** `aria-knowledge` `main` `db2f655`, **35 ahead of `origin/main`**, 0 behind,
plugin v2.48.0 (source and installed). Working tree **DIRTY with a parallel session's WIP**
— see §9.

---

## 1. Problem

Rule 23 gates the promotion of a captured learning into a saved rule. It has two defects,
both measured, and neither is a wording problem.

**1a — its stated scope is narrower than its own rationale.** The rule text says "learnings
and proposed rules" and never names a persistence surface. Its rationale names three
enforcement surfaces, one of which is *CLAUDE.md context-loading*. In a real deployment the
auto-memory directory loads through exactly that channel, via `@`-imported indexes. So the
memory directory is **in scope by the rationale and out of scope by the text**. A session
writing a memory file receives no signal that Rule 23 applies to it, and behaves accordingly.

**1b — it gates entry and not exit.** The rationale ends *"...until someone detects and
revokes it,"* then governs neither the detection nor the revocation. A gate on entry with no
discipline for staleness addresses half of the propagation the rule names as its own reason
for existing.

Neither defect is theoretical. §2 measures both.

## 2. Evidence

### 2.1 The gate runs on the rules files and nowhere else — measured

Census over the reference deployment's auto-memory directory (1,016 files) and
`user-rules.md`, 2026-08-26:

| Surface | Rule-shaped content | Records the Rule 23 gate |
|---|---|---|
| `user-rules.md` | 19 U-rules | **yes** — explicit `Rule 23 gate satisfied` stamp with the user's quoted ruling |
| auto-memory directory | >=130 of 506 `feedback_*` carry hard prohibitions | **0 of 1,016 files** |

The `user-rules.md` stamp proves the gate is understood and applied where the rule names a
surface. The zero proves it is not reaching the surface the rule does not name.

### 2.2 The derived-vs-transcribed distinction is real and already visible

Of 506 `feedback_*` files, **6 are labelled `META-RULE`** — self-authored generalizations
rather than records of a stated ruling. **3 of those 6 attribute the user nowhere.** Those
three are precisely the population Rule 23 exists to gate, and none of them records approval.

The remaining bulk of `feedback_*` files quote the user directly. Those are **transcription,
not promotion** — the user already ruled, and a second approval round on a decision he
already made spends the decision budget Rule 35 exists to protect. The rule currently draws
no line here, so a conscientious reading of it would gate all 506, which is why in practice
it gates none.

### 2.3 Instrument bounds on 2.1 and 2.2

Stated because the numbers above are load-bearing:

- **">=130 rule-shaped" is a LOWER bound.** Pattern was the union of hard-prohibition
  markers; the control surfaced rule-shaped files carrying none of them. The true count is
  higher and was not derived.
- **"0 of 1,016" is bounded by its pattern** (`Rule 23 gate|gate satisfied|approved by ...
  before saving`). It is a census, not a read of 1,016 files.
- **A file mentioning the user's name is NOT evidence of approval.** 278 files mention him;
  that is a state claim about text, not a meaning claim about consent, and it is deliberately
  not converted into an approval count.

### 2.4 Rule 23 is carried by TWO coupled files in this port

| File | Line | Role |
|---|---|---|
| `plugin-claude-code/template/rules/working-rules.md` | 240 | full rule; read on demand by `/rules` |
| `plugin-claude-code/rules/aria-rules.md` | 67 | digest one-liner; **emitted every session and discarded every session** — see 2.4a |

Editing one without the other half-applies the change. This is the COUPLED class
`tools/check-plugin-drift.sh` reports and that a per-path `diff` structurally cannot see. It is
also enforced here by an existing test — see 2.4b.

### 2.4a ⛔ CORRECTION — the digest line does NOT reach model context

An earlier draft of this section claimed the digest one-liner is *"injected into context every
session."* **That is false, and the gate falsified it before any code was written.** Measured in
the gating session:

| | |
|---|---|
| `additionalContext` payload | 19,818 characters |
| Delivered preview | ~1,929 ch (budget `K5=2000`, cut on a line boundary) |
| Preview ends | mid-`Rule 1`, at char offset 1,783 |
| Rule 23 digest line begins at | **char offset 7,985** (line 64) |

So the line is **emitted** every session and **discarded** every session. This independently
reproduces §2.6 of this repo's own
`docs/superpowers/specs/2026-08-25-always-on-rules-delivery-design.md`, which measured 2 of 38
rules delivered across 42 sessions.

⚑ **The correction strengthens the case for the amendment rather than weakening it.** The
surface that actually steers an unwatched session today is the **auto-memory directory**, which
does reach context — and widening scope to cover it is exactly what §4.1's first block does. The
original framing over-weighted the digest; the problem statement survives intact.

⚠ **Consequence for §4.2:** the digest edit is still necessary, but for a different reason —
see 2.4b. It is not a user-visible change today, and the plan must not claim it is.

### 2.4b The two files are bound by an existing, passing test

`plugin-claude-code/tests/test-aria-rules-digest.sh:29` asserts *"digest covers every working
rule by number"* — comparing rule **number sets**, not counts, with a positive control run
first. Its own header records why: `plugin-antigravity`'s digest once claimed "34 working rules"
against a source of 38, and a count comparison matched a stale total for four rules straight.

That test is the real reason §4.2's edit must land with §4.1's: the number set must stay
consistent. It also means several acceptance criteria need not be hand-written — see §7.

⚑ The same header independently corroborates §2.6 of this spec: it notes the maintainer's copy
*"differs from the template by a personal unpromoted annotation,"* which is the +2/-0 delta
measured there.

**The live copy is the INSTALLED one, proven two-sided:** canonical source's digest carries a
`## Standing Directives` section; the installed digest does not; the current session's
injection does not either — with the Rule 37 digest line as a positive control confirming the
grep can match. Under scope (i) this change therefore ships to future installs and is
**inert on the maintainer's machine until a reinstall**. That is the accepted consequence of
Mike's ruling, not an oversight.

### 2.5 Rule 37 is adjacent, and is a different subject

Rule 37 governs things **meant to die** and requires a removal trigger recorded at
introduction. 1b governs things **meant to last** and requires a falsifier recorded at save
time. Same shape, opposite subject. The amendment must therefore **compose with 37 by
reference and not restate it**, or the two rules will be read as duplicates and one will be
pruned.

### 2.6 Rule 23's own text is identical across source and installed

`diff` of the Rule 23 digest line in both digests: identical. `cmp` of source vs installed
`working-rules.md`: byte-identical, with the cowork port as a positive control that fired.
So the edit target is unambiguous and carries no pre-existing drift of its own.

## 3. Decision

**Amend Rule 23 in place. Do not create a new rule number.**

Rejected alternatives:

- **New Rule 39 for the revocation half.** Rejected: Rule 23's rationale already promises
  revocation, so the clause completes an existing thought rather than introducing one. A new
  number also costs an index entry and a second digest line for what is two clauses, and
  would sit far from the gate it belongs to (document order places 38 after 35).
- **Fold the scope fix into Rule 19 instead.** Rejected: 19 is the capture stage and is
  deliberately ungated. Widening 19 would gate capture, which is the opposite of the
  19/23 split's design.
- **Leave 1a to convention and document it in a skill.** Rejected: the measured result of
  leaving it to convention is 0 of 1,016.

## 4. Design

### 4.1 `template/rules/working-rules.md` — replace the single `Composes with Rule 19` line

The existing heading, opening paragraph, and `**Why this gate exists:**` paragraph are
**unchanged**. Only the final `Composes with Rule 19` line is replaced, by six blocks:

1. **Scope** — names every surface that loads itself into a future session: `working-rules.md`,
   `user-rules.md`, auto-memory files and the indexes that import them, project `CLAUDE.md`
   files, path-scoped rules. States the criterion as *"whether it will steer a session nobody
   is watching,"* not where the text lives.
2. **Exemption** — recording a ruling the user stated is transcription: quote, attribute,
   save, no gate. Names Rule 35's decision budget as the reason.
3. **The test** — one step: *can you quote the user saying it?* Yes -> record with the quote.
   No -> it is yours; surface per Rule 35, save only on approval. Closes with why it matters:
   a derived rule saved silently is indistinguishable to every later session from one the
   user actually ruled.
4. **The exit** — every saved rule states its falsifier at save time, while the reason for
   believing it is still known.
5. **Staleness is a defect, not an age** — do not retire for age or trust for recency;
   re-verify against the system described; correct at source and stamp the correction,
   because a superseded rule standing beside its replacement reads as current.
6. **Composes with** — Rule 19 (capture/gate split, preserved from the replaced line),
   Rule 37 (die/last distinction per 2.5), Rule 6 (retire by correcting and marking, never
   by silent deletion).

Full proposed prose is carried in the implementation plan, not here, so that a single
reviewed string is the thing that lands.

### 4.2 `rules/aria-rules.md:67` — replace the digest line

One line, replaced in place, under `## Meta Rules`. It must carry: the existing prohibition,
the scope widening, the one-step test in both directions, the falsifier-at-save-time clause,
and the existing propagation warning. Length is consistent with the Rule 36 and 37 digest
lines already in the file.

### 4.3 Explicitly NOT changed

- Rule 23's heading, opening paragraph, and rationale paragraph.
- Rule 19, Rule 37, Rule 6 — referenced, not edited.
- `skills/prospect/SKILL.md:577` and `skills/retrospect/SKILL.md:628`, which cite Rule 23
  correctly ("do not persist without user approval per Rule 23") and stay true under the
  amendment.
- The four non-Claude-Code ports.
- The installed plugin and the maintainer's live knowledge folder (scope (i)).

### 4.4 The amendment must not reference user-scoped rules

`user-rules.md` is user-owned, is never rewritten by the plugin, and **does not ship**. The
canonical rule text therefore cannot cite any `U`-numbered rule for presentation shape. An
earlier draft routed presentation through `U18`; this was caught and re-routed through
**Rule 35**, which ships. Any future edit to this rule inherits the same constraint.

## 5. Non-goals

- Building detection tooling for stale rules. Detection machinery already exists downstream
  in the reference deployment; this rule states the discipline, it does not ship a scanner.
- Retro-applying the gate to the 1,016 existing memory files.
- Mirroring to the other four ports.
- Fixing the separate, incidentally-discovered drift where the installed digest is missing
  its whole `## Standing Directives` section (all 38 rule lines are present in both, so no
  rule is absent from context). Recorded here so it is not lost; out of scope.

## 6. Cost

Two files, one port, no code paths. One replaced block in `working-rules.md` and one replaced
line in `aria-rules.md`. No hook, skill, script, or schema is touched. Reversal is a `git
revert` of a single commit.

The real cost is **review attention on the rule text itself**, which is the thing Rule 23
exists to spend deliberately.

## 7. Acceptance criteria

⛔ **C4 — the acceptance boundary, stated rather than implied.** Every criterion below is
**STRUCTURAL**: it verifies that the intended TEXT LANDED. The defect this spec fixes is that a
gate *is not applied*, and **no check here can express that**. Acceptance for §4.1's blocks 4 and
5 (the falsifier and staleness clauses) is therefore **TEXTUAL ONLY** — nothing confirms the
discipline is practiced. This is the `structural-guard-cannot-represent-the-defect` shape, named
here deliberately so a green AC set is not mistaken for a working gate.

**What would falsify the amendment later:** a rule saved to any surface named in §4.1's scope
block, after this date, carrying no stated falsifier and no quoted ruling. That is the real test,
it is retrospective, and it belongs to a future `/retrospect` — not to this plan.

- **AC1** — `working-rules.md` Rule 23 contains all six blocks of 4.1; the heading, opening
  paragraph, and rationale paragraph are byte-identical to their pre-edit form.
- **AC2** — the phrase `Composes with Rule 19` still appears in Rule 23 (the 19/23 split is
  preserved, not dropped in the rewrite). Guards against the Rule 31 failure mode.
- **AC3** *(C3 — delegated)* — `plugin-claude-code/tests/run.sh` passes with **bare exit 0**,
  measured against the recorded pre-edit baseline of **253 passed / 0 failed**. This subsumes the
  hand-written digest checks: `tests/test-aria-rules-digest.sh:29` already asserts the digest
  covers every source rule **by number set**, with its own positive control. ⛔ Run the baseline
  BEFORE editing — this repo has a parallel session writing to it, and an unattributable red is
  worthless.
- **AC4** *(C2 — derivation pinned)* — the rule-number set is unchanged at 38, derived from
  **`^### [0-9]+\.` headings only**. ⛔ NEVER derive it from `Rule N` mentions: the amendment's own
  prose cites Rules 19, 35, 37 and 6, so a mention-based count reads the new text as data — the
  `own-comment-enters-the-text-its-guard-reads` shape.
- **AC5** *(C2 — control required)* — zero `U`-numbered rule references inside Rule 23's text
  (§4.4). ⛔ The check MUST carry a firing positive control: the same pattern reads **52** against
  `knowledge/rules/user-rules.md`. A bare 0 is not evidence — measured, the first attempt at this
  check returned 0 against a control that also returned 0, and proved nothing.
- **AC6** — the four other ports' `working-rules.md` and `aria-rules.md` are byte-identical
  to their pre-edit state.
- **AC7** — `git status --porcelain` shows exactly the two intended files as modified by this
  work; the parallel session's four dirty paths are untouched and unstaged.
- **AC8** — a full-file `diff` of each edited file against its pre-edit backup shows only the
  intended hunks, with the removed-line count matching the prediction stated in the plan.
- **AC9** *(new — expected divergence, not drift)* — record that after this edit
  `plugin-claude-code`'s two files **intentionally differ from their installed twins**, dated
  2026-08-26, as the accepted consequence of scope (i). Both sides will continue to report
  version `2.48.0`, which is precisely the `committed-is-not-installed` trap: **compare content,
  never versions.** This is a recording criterion, not a sync step.

## 8. Open questions — CLOSED 2026-08-26

Mike delegated both ("do what you think is best and validate"). Decided, applied, validated.

- **OQ1 — CLOSED: a ruling from an earlier session counts, and the quote carries its date.**
  Re-gating a decision already made wastes the exact budget the exemption protects, so it must
  count. The date is the handle a later reader needs to apply the staleness clause — within a
  session it is implicit, across sessions it is the only one. Note the scope: the date attaches
  to the CROSS-SESSION case, not as a new tax on every write. That is the same decomposition
  behind the approved exemption wording, applied consistently.
- **OQ2 — CLOSED: state-on-touch; do not sweep.** New-rules-only leaves all 38 existing rules
  permanently exempt, so the requirement never propagates. Sweeping all 38 is a change nobody
  asked for and is out of scope per §5. On-touch propagates gradually and puts the cost where
  someone already has the rule in hand.
- **OQ3 — CLOSED**: exemption wording tightened to *"quote their own words"* + *"a paraphrase is
  not a quote"*, approved by Mike 2026-08-26.

⚠ Both OQ1 and OQ2 land as PROSE and inherit §7's C4 boundary exactly: measured by mutation,
deleting the OQ2 sentence leaves the suite at 253 passed / 0 failed / bare exit 0. Nothing
catches it. That is stated, not implied.

## 9. Constraints — the repo is not clean

`aria-knowledge` `main` is **35 commits ahead of `origin/main`** and the working tree carries a
parallel session's WIP: `.gitignore`, `plugin-claude-code/skills/index/SKILL.md`,
`plugin-claude-cowork/skills/index/SKILL.md` (all modified), and one untracked spec
`docs/superpowers/specs/2026-08-25-handoff-resume-mode-design.md`.

**Collision check, measured:** all three modified files return **0** hits for `Rule 23` /
`### 23.`, against a control (`plugin-claude-code/rules/aria-rules.md`) returning 2. No
overlap with this work.

⛔ Stage named files only. Never `git add -A`, never `git commit -a`, never amend. Predict the
diffstat before committing and reconcile it against the actual, per AC8.
