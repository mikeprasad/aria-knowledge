# Plan — Rule 23 gains a scope, an exemption, and a revocation half

STATUS: GATED — gate 2 (`/prospect`) RUN 2026-08-26, verdict **PROCEED-WITH-CHANGES**. Both
changes (C5, C6) applied below in the same session that ran the gate. Gate 2 report:
`knowledge/logs/prospect/2026-08-26-file-rule-23-plan-gate2.md`.
**Post-gate amendment, Mike 2026-08-26:** clause 2 tightened — *"quote their own words"* plus
*"a paraphrase is not a quote"*. Narrows the exemption; does not widen scope, so no gate re-run.
Grounded in a corpus census: 37 of 506 feedback files already use "verbatim", while only 6 carry
the dated+verbatim shape — so verbatim codifies practice and a date requirement would not.
**GO GIVEN 2026-08-26 — executing T1-T4.**
Spec: `docs/superpowers/specs/2026-08-26-rule-23-scope-exemption-revocation-design.md` (GATED,
gate 1 verdict PROCEED-WITH-CHANGES, C1–C4 applied).
Gate 1 report: `knowledge/logs/prospect/2026-08-26-file-rule-23-scope-exemption-revocation.md`.
Requested by: Mike, 2026-08-26 — "A and B", then "A spec prospect plan prospect", scope "B i".
Repo: `aria-knowledge`. Baseline: `main` `db2f655`, **35 commits ahead of `origin/main`**, 0
behind, **working tree DIRTY with a parallel session's WIP** (see §6).
Scope: **`plugin-claude-code` ONLY.** Two files. No code paths.

## 1. What lands

| File | Change |
|---|---|
| `plugin-claude-code/template/rules/working-rules.md` | replace the single `Composes with Rule 19` line inside Rule 23 (currently line 247) with the six blocks in §2.1 |
| `plugin-claude-code/rules/aria-rules.md` | replace the `- **Rule 23` digest line (currently line 67) with §2.2 |

Rule 23's heading, opening paragraph, and `**Why this gate exists:**` paragraph are **not
touched**. No new rule number is created; the rule-number set stays at 38 on both sides.

⚠ **The digest edit is not a user-visible change today.** Per spec §2.4a, the digest line sits at
char offset 7,985 of a payload whose delivered prefix ends at ~1,929 — it is emitted every
session and discarded every session. It is edited because it is the canonical artifact and is
bound to the source by a passing test (spec §2.4b), **not** because sessions will read it.

## 2. The exact text

### 2.1 `working-rules.md` — replaces the `Composes with Rule 19` line

```markdown
**Scope — every surface that loads itself into a future session.** Not only `working-rules.md` and `user-rules.md`, but auto-memory files and the indexes that import them, project `CLAUDE.md` files, and path-scoped rules. The test is not where the text lives; it is whether it will steer a session nobody is watching.

**Exemption — recording a ruling is not proposing a rule.** When the user has stated the guidance, writing it down is transcription: quote their own words, attribute it, save it. A paraphrase is not a quote — if you are rendering what they meant rather than what they said, you are deriving. Re-asking approval for a decision they already made spends the decision budget Rule 35 exists to protect. This gate is for rules *you* derived — a generalization from measurement, a meta-rule, a class conclusion drawn from a single instance.

**The test is one step: can you quote the user saying it?** Yes — record it with the quote. No — it is yours; surface it per Rule 35 and save only on approval. A derived rule saved silently is indistinguishable, to every later session, from one the user actually ruled, and that is exactly the propagation this gate exists to stop.

**The gate has an exit as well as an entry.** A saved rule is a claim, and claims expire. State the condition under which it stops being true — what would falsify it, or what change in the system retires it — at save time, while the reason for believing it is still known. A rule with no stated falsifier cannot be audited later; it can only be argued about.

**A stale rule is a defect, not an age.** Do not retire a rule for being old or trust one for being recent — re-verify it against the system it describes. A rule whose subject has moved is wrong *now* and is steering sessions wrongly *now*. Correct it at source and stamp the correction: a superseded rule left standing beside its replacement reads exactly like a current one.

**Composes with Rule 19**, which captures candidates while this rule gates which candidates become persistent; with **Rule 37**, which makes things meant to die name their removal trigger, where this rule makes things meant to last name their falsifier; and with **Rule 6** — retire a rule by correcting and marking it, never by silent deletion.
```

⚑ The literal phrase `Composes with Rule 19` is preserved in the final block **on purpose** —
AC2 asserts it, guarding the Rule 31 failure mode where a rewrite silently drops content.

⚑ Straight apostrophes, matching the file's majority convention (70 straight vs 21 curly).

### 2.2 `aria-rules.md` — replaces the `- **Rule 23` line under `## Meta Rules`

```markdown
- **Rule 23 — Review captured learnings before saving them as rules** — never auto-add a rule; discuss first, save only on approval. **Scope is every surface that loads itself into a future session** — memory files and their indexes, CLAUDE.md, path-scoped rules — not just the rules files. **One-step test: can you quote the user saying it?** Yes — transcription, record it attributed, no gate. No — you derived it, so gate it. **Every saved rule states its own falsifier at save time**; a stale rule is a defect, not an age, so correct it at source and stamp it. A wrong rule, once saved, poisons every later session until someone catches it.
```

⚑ Begins `- **Rule 23` so `tests/test-aria-rules-digest.sh`'s number-set extraction still sees it.
⚑ Carries **no rule total** — `test-aria-rules-digest.sh:37` asserts the digest hardcodes none.

## 3. Tasks

- **T0 — Baseline, before any edit.**
  1. `git -C aria-knowledge status --porcelain` — record the parallel session's four dirty paths.
  2. Byte backups of both target files to the session scratchpad (NOT to the repo).
  3. **(C5) Pin the baseline by CONTENT, not by timestamp.** `shasum` and record: the two source
     targets, the four other ports' `working-rules.md` + `aria-rules.md`, and the installed twins
     of both targets. AC6 and AC9 compare against THESE recorded hashes — never against the live
     installed state.
     ⛔ **Measured this session: the installed digest's CONTENT changed mid-session while its
     MTIME did not move** (`standing=0` and DIFFER-from-source on one read; `standing=1` and
     byte-identical on a later read; mtime `18:25:59` predates both). A baseline keyed on mtime,
     or on a live re-read at check time, is blind here.
  4. `(cd plugin-claude-code && bash tests/run.sh)` — record bare exit and the pass/fail counts.
     Expected from the gate-1 run: **253 passed, 0 failed, bare exit 0.**
  ⛔ A red here is the parallel session's, not ours. Stop and report; do not proceed.
- **T1 — Edit `working-rules.md`.** Replace exactly the one line with §2.1. Predict the diffstat
  before running: **1 line removed, 11 added** (6 blocks + 5 blank separators).
- **T2 — Edit `aria-rules.md`.** Replace exactly the one line with §2.2. Predict: **1 removed,
  1 added.**
- **T3 — Gates.** Run AC1–AC9 (§4) and the mutations (§5).
- **T4 — Commit.** Stage the **two named files only**. Message via `git commit -F -` with a
  heredoc. ⛔ Never `-m` with backticks in the message — zsh runs them as command substitution
  and silently deletes the content, leaving a message that still reads as a sentence.
  ⛔ No push. Mike pushes.

## 4. Acceptance

Inherits spec §7 verbatim, including its **C4 boundary statement**: every criterion here is
structural and verifies that TEXT LANDED. Nothing here confirms the discipline is practiced.

| AC | Check | Derivation (pinned) |
|---|---|---|
| AC1 | six blocks present; heading + opening + rationale byte-identical | `diff` against the T0 backup |
| AC2 | `Composes with Rule 19` still present | `grep -c` == 1 |
| AC3 | full suite green | `(cd plugin-claude-code && bash tests/run.sh)`, **bare exit 0**, vs the T0 baseline |
| AC4 | rule-number set unchanged at 38 | **`^### [0-9]+\.` headings ONLY** — never `Rule N` mentions |
| AC5 | zero U-refs inside Rule 23 | `\bU[0-9]+\b`, **with the firing control**: same pattern reads **52** against `knowledge/rules/user-rules.md` |
| AC6 | other four ports untouched | `cmp` each against its T0 state |
| AC7 | only the two intended files modified by us | `git status --porcelain`; the parallel session's four paths unchanged and unstaged |
| AC8 | only intended hunks | full-file `diff` vs T0 backup; removed-line count matches T1/T2 predictions |
| AC9 | expected divergence recorded | note that source now intentionally differs from installed, dated 2026-08-26; both still report `2.48.0` — **compare content, never versions** |

## 5. Mutations — each must go red for its own named reason

| # | Mutation | Must redden | Proves |
|---|---|---|---|
| M1 | delete the phrase `Composes with Rule 19` from the new text | AC2 | the Rule 31 guard is live, not decorative |
| M2 | add a `### 39.` heading | AC4 | the heading-derived count can actually move |
| M3 | derive AC4 from `Rule N` **mentions** instead of headings | AC4 reads **> 38** | C2 was necessary — the amendment's own prose cites Rules 19/35/37/6 and would be counted as data |
| M4 | insert `U18` into Rule 23's body | AC5 | AC5 can fail, **and** its control still reads 52 (a dead instrument is excluded) |
| M5 | change one rule number in `aria-rules.md` only | `tests/run.sh` | AC3's delegation is real — the existing test genuinely binds the two files |

⛔ M3 is the load-bearing one. It does not test the code; it tests **the acceptance criterion
itself**, and it is the only mutation that would have caught the defect gate 1 found in AC4.

⛔ Restore from the **T0 byte backups**, then `cmp`. Never `git checkout --` — the tree is shared
and that reverts to HEAD, discarding the parallel session's uncommitted edits.

## 6. ⛔ Constraints — a LIVE concurrent session is writing to this repo

**(C6) Not stale WIP — an active writer.** `CHANGELOG.md` was clean in this session's first
`git status` and is modified now. Treat every observation of the tree as valid only at the
instant it was taken.

`main` is **35 ahead of `origin/main`**. Dirty paths held by the other session:
`.gitignore`, `CHANGELOG.md`, `plugin-claude-code/skills/index/SKILL.md`,
`plugin-claude-cowork/skills/index/SKILL.md`, plus untracked
`docs/superpowers/specs/2026-08-25-handoff-resume-mode-design.md`.

**Collision check, measured and re-run after the tree changed:** `.gitignore` and both
`index/SKILL.md` return **0** hits for `Rule 23` / `### 23.` against a control returning **2**.
`CHANGELOG.md` returns **5** — historical entries only; `git diff` confirms **no overlap with
this arc**. Both of this plan's target files are **CLEAN**.

⛔ **This plan adds NO changelog entry.** That is a deliberate decision, not an omission:
`CHANGELOG.md` is held dirty by the live writer, and editing it would collide. If a changelog
line is wanted, it is a separate change made after that session lands.

⛔ **Re-run the collision check at commit time**, not only now — it goes stale under a live
writer.
⛔ Stage named files only — never `git add -A`, never `git commit -a`, never `--amend`.
⛔ Do not push; do not touch the other session's files, including to "tidy" them.

## 7. Out of scope

- The four non-Claude-Code ports.
- Syncing the installed plugin or the maintainer's live `knowledge/rules/working-rules.md`
  (scope (i) — Mike's explicit ruling).
- The separate installed-digest gap where `## Standing Directives` is missing from the installed
  copy (all 38 rule lines ARE present in both; no rule is absent from the file).
- The `additionalContext` truncation defect itself — owned by
  `docs/superpowers/plans/2026-08-25-always-on-rules-delivery.md`.
- Retro-applying the gate to existing memory files.
- Building any stale-rule detector.

## 8. Open questions — ALL CLOSED 2026-08-26

- **OQ1 CLOSED** — a prior-session ruling counts; carry the quote's date. Cross-session only.
- **OQ2 CLOSED** — the falsifier requirement applies ON TOUCH; do not sweep the existing 38.
- **OQ3 CLOSED** — exemption tightened to "quote their own words"; "a paraphrase is not a quote".

All three are prose and inherit the C4 boundary: mutation-measured, deleting the OQ2 sentence
leaves the suite green. Landed in the rule body, not the digest — the digest is a summary and
does not contradict; adding refinements to a line that never reaches model context (spec 2.4a)
buys nothing.
