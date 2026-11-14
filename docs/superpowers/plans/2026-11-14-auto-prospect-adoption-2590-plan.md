# 2.59.0 plan — `/auto` and `/prospect` adoptions

**Spec:** `docs/superpowers/specs/2026-11-12-auto-prospect-adoption-2590-spec.md` (prospected
PROCEED-WITH-CHANGES, amendments applied). **Branch:** `release/2.59.0`, worktree
`aria/.wt-2.59.0-aria-knowledge`, upstream `origin/main` (so gate D reads commit messages).
**Status:** written 2026-11-14 against `release/2.58.0` at `fbe7c8e` (2.58.0 Task 6 landed; Tasks 7–10 not).
⛔ **No source edit before Task 0 passes.**

## Ground rules (every task)

- Every directory-dependent command is one parenthesised absolute cd: `(cd "$WT" && <cmd>)`, `$WT` =
  the worktree. Never a bare `cd`.
- Each test is seen **red on the pre-change tree** before the change, for the reason it names. A test that
  passes before the change is dead: fix the test first.
- Commit with `git commit -F -` + heredoc; stage named paths only; message ends with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. No session URL (public repo).
- After every commit: `(cd "$WT" && sh plugin-claude-code/scripts/check-public-hygiene.sh "$WT")` → exit 0
  and the summary line says `commit messages: origin/main..HEAD (N commits)`. Exit 2 = the gate's own
  self-test failed, not a clean result.
- Read bare exit codes. Never cite an exit code read through a pipe.
- Generated ports are regenerated, never hand-edited: Antigravity via `./plugin-antigravity/build.sh`, Cursor
  `.mdc` via `python3 plugin-cursor-template/scripts/port-skills-to-mdc.py`. Run each generator on the
  clean tree FIRST; a non-empty diff there is pre-existing drift — stop and report, do not absorb it.
- Never `check-port-drift.sh --update all`.
- No frontmatter `description` edits in any skill (claude.ai 1,024 cap; Gate B).
- No push, no tag, no release. The plan stops after Task 9.

## Task 0 — Rebase and re-measure (gate for everything below)

1. Wait until `git ls-remote --tags origin v2.58.0` returns a line. Then
   `(cd "$WT" && git fetch origin && git rebase origin/main)`. Expected: the 3 docs commits replay cleanly
   (they touch only `docs/superpowers/{specs,plans}/`). Verify
   `git merge-base --is-ancestor <v2.58.0 commit> HEAD` → exit 0.
2. Re-run these measurements and compare to the expected values recorded at `fbe7c8e`:

   | Measurement | Command | Expected |
   |---|---|---|
   | Memory-name census | per tracked file under `plugin-*/`: `git show HEAD:<f> \| /usr/bin/grep -oE 'feedback_[a-z0-9_]+' \| wc -l` | prospect 7 ×4 ports, retrospect 3 ×4, cursor `aria-commands.mdc` 10, `plugin-claude-code/tests/test-aria-rules-digest.sh` 1; nothing else |
   | Gate B total | the `awk` in `release.sh` Gate B, summed over `plugin-claude-code/skills/*/SKILL.md` | 19,259 of 19,968 (headroom 709) |
   | `/auto` description | chars inside `description: "…"` | 1,005 |
   | `/prospect` headings | `grep -nE '^#{2,3} '` | Step 0 · 0.5 · 1 · 2 · 3 · 3.5 (3.5.1–3.5.4) · 4 (4.1–4.10) · 5 · 6 · 7 · Over-build lens · 8 |
   | `/auto` arc steps | `### arc mode — full chain` items 1–7 | Brainstorm, Spec, /prospect, Plan, /prospect, Execute, /retrospect; item 3 contains "in place, now" |
   | Generators on a clean tree | run both; `git status --short` | empty |

   Any difference ⇒ stop, record it, amend this plan before Task 1.
3. Record the host versions in the commit message of Task 2: `claude --version` (expected ≥ 2.1.323).

## Task 1 — Hygiene class: memory names out, gate arm in

**Test first:** new `tests/repros/public-hygiene-memory-names.sh`:
- (a) copy the gate into a scratch repo with one tracked file `plugin-x/skills/s/SKILL.md` containing
  `per feedback_example_rule` → gate exits **1** and names that file;
- (b) the same scratch repo with `docs/notes.md` containing the token and no `plugin-*` hit → exit **0**
  (scope is `plugin-*/` only, spec D4);
- (c) on the real tree at HEAD → exit **0**.
Red before the change: (a) exits 0 (no arm exists) and (c) is not yet meaningful; after the arm alone,
(c) exits 1 listing the 9 files + the test comment. Both reds are recorded.

**Change:**
1. `plugin-claude-code/scripts/check-public-hygiene.sh`: add the arm — fail on `feedback_[a-z0-9_]+` in
   tracked files whose path starts `plugin-`, report each file + count, join the existing `any=` verdict.
   Extend the inline self-test with a firing and a silent case (the file already excludes itself by name).
2. Replace each citation with the plain rule it named, in canonical `prospect/SKILL.md` and
   `retrospect/SKILL.md`, then by hand in `plugin-openai-codex/` and `plugin-claude-cowork/` (same
   sentences). Wording: drop the `(per \`feedback_…\`)` parenthetical where the sentence already states the
   rule; where it does not, state it (e.g. "one ask at a time unless the user asks for a batch"). Rewrite the
   comment in `plugin-claude-code/tests/test-aria-rules-digest.sh` without the name.
3. Regenerate Antigravity and Cursor.

**Verify:** `/usr/bin/grep -rlE 'feedback_[a-z0-9_]+' plugin-*` → exit **1** with a positive control in the
same invocation (`/usr/bin/grep -c 'check-public-hygiene' release.sh` ≥ 1); repro 3/3; plugin suite
green. **Commit** `fix(hygiene): shipped skills cite rules in plain words; gate fails on memory-file names under plugin-*/`.

## Task 2 — `/prospect`: cold read, receipts, inherited-first, frame Q4, human-row DEFER, `--summary`

**Test first:** new `tests/repros/prospect-adoptions.sh`, run against **every port carrying
`prospect/SKILL.md`** (claude-code, openai-codex, antigravity, claude-cowork) plus Cursor's
`aria-commands.mdc` section. Arms, each red on the pre-change tree:
- P1 `argument-hint` contains `--cold` and `--summary` (ports whose frontmatter has `argument-hint`;
  Antigravity's schema ignores it — assert the body's Step 0 modifier list instead);
- P2 a `Step 3.6` heading naming the cold read;
- P3 the cold-read prompt template, extracted between two fixed markers, is **byte-identical** across all
  carrying ports (AC3) — and a one-character mutation in one port reddens it (run once, then revert from a
  byte backup, `cmp`);
- P4 Step 3.6 names Claude Code's built-in **Plan** agent with the host-version stamp, and the Cold read
  block lists subagent type + `git status` before/after (AC7);
- P5 `§4.6` reads "Four questions" and question 4 is the in-flight-work question;
- P6 `--summary` appears in Step 6;
- P7 canonical frontmatter `allowed-tools` contains `Agent`;
- P8 Cowork's Step 3.6 states the not-run line (`Cold read: not run — this runtime cannot start a subagent`).

**Change (canonical `plugin-claude-code/skills/prospect/SKILL.md`):**
1. Frontmatter: `argument-hint` gains `[--cold] [--summary]`; `allowed-tools` gains `Agent`. Description untouched.
2. Step 0 modifier list: `--cold` (one cold-read round, Step 3.6; opt-in; ~1 subagent) and `--summary`.
3. Step 3: R2 receipt rule — a command the plan hands over carries `$ cmd` / `expected:` (written first) /
   `exit <n>` + first line, or `not run: <reason>`; neither ⇒ that step's Preliminary Risk? is at least ⚠.
4. Step 3.5.1: inherited claims (handoff, ticket, earlier doc, memory — not measured this session) are
   evidence candidates first (R9 half). Step 3.5.2: a read-only command lacking a receipt is a candidate to run.
5. New `### Step 3.6: Cold read (opt-in: \`--cold\`)` after 3.5.4, per spec R1 steps 1–4 and A1/A2:
   plan-as-file; fixed template between markers `<!-- cold-read-template:begin -->` /
   `<!-- cold-read-template:end -->`; environment line from the plan, else `none` + a finding; dispatch rule
   (Claude Code 2.1.323: built-in Plan agent, which skips CLAUDE.md and git status and has no Edit/Write;
   another runtime: its own subagent tool, and the report states what that reader loads — Codex loads
   `AGENTS.md` from the project root down; unknown ⇒ say unknown; no subagent ⇒ the not-run line);
   `git status --porcelain` before/after; findings are leads, checked before they count.
6. §4.3: a confirmed cold-read BLOCKER on a step ⇒ that step is not PROCEED; a step depending on an
   unanswered "Decisions only the human can make" row ⇒ DEFER citing the row (A6).
7. §4.6: "Three questions" → "Four questions"; add Q4 (spec R6), "none found" names its instrument.
8. §4.8: overall verdict cannot be PROCEED while a confirmed BLOCKER stands; print the Cold read block
   (round, subagent type, environment line, findings by rank confirmed/refuted, git status result, prompt
   char count).
9. Step 6: `--summary` ⇒ chat shows Anchor, §4.8 verdict + action list, residual asks, log path; full report
   still written; if no log is written, `--summary` is ignored and the report says so.
10. Step 8: gate 12 — with `--cold`, Step 3.6 ran or printed its not-run reason; never silent.

**Ports:** Codex by hand (strip ADR-094 gates, root var `${ARIA_PLUGIN_ROOT}`); Cowork by hand with the
not-run line in place of the dispatch rule and **no** `allowed-tools` change (Cowork frontmatter); regenerate
Antigravity and Cursor. **Verify:** repro all arms green; plugin suite, codex `tests/run.sh`, idempotence,
upload-limits green. **Commit** `feat(prospect): --cold reads the plan with a fresh, instruction-free reviewer; command receipts; --summary`.

## Task 3 — `/auto`: `cold` rounds, R3, R4, R5, R2, R6, R7

**Test first:** extend `tests/repros/auto-modes.sh` (canonical + the Codex and Antigravity `auto` copies),
each arm red first:
- A1 `argument-hint` contains `[cold|cold=<N>]`; Step 0 lists `cold` as a modifier with a worked ENDS case;
- A2 Step 0¾ config walkthrough has a cold-read item; Step 0.5 contract states "~1 subagent per round, up to N";
- A3 arc step 3: rounds repeat until no confirmed BLOCKER or N (default 4); R3 trigger (two consecutive
  rounds landing in one step's own verification machinery ⇒ offer SHRINK/KILL with cost); R4 (from the third
  amendment round: regenerate whole + identifier diff, every drop has a reason);
- A4 arc step 2 carries the "Decisions only the human can make" table rule; arc step 4 the receipt rule;
- A5 arc step 6 re-runs the plan's pre-execution checks and compares upstream-changed files to the plan's files;
- A6 Step 0.5 lists peer activity (runtime session list if available, in-progress `SESSION.md`, recent commits on
  touched paths) and states it is activity, not ownership;
- A7 Step 5 says cold-read rounds count toward `agents=`;
- A8 the description is byte-unchanged from the pre-change tree (guards A4/claude.ai cap).

**Change:** canonical `plugin-claude-code/skills/auto/SKILL.md` at those sections; Codex by hand;
Antigravity + Cursor regenerated. Cowork has no `/auto`. **Commit**
`feat(auto): cold review rounds, cut-the-check trigger, regenerate after two amendments, human-only decisions table`.

## Task 4 — Two shipped patterns

**Test first:** new `tests/repros/shipped-patterns-2590.sh`: both `## <name>` entries exist with all five
fields (Tier, First identified, One-line summary, Detection cues, Counter-discipline) in
`plugin-claude-code/template/rules/retrospect-patterns.md`, `plugin-openai-codex/template/rules/…`,
`plugin-claude-cowork/template/rules/…`, `plugin-antigravity/template/rules/…` (generated) and
`plugin-cursor-template/knowledge/rules/…`. Red first.

**Change:** add `contract-restated-anywhere-is-a-divergence-already-scheduled` and
`re-run-pre-execution-checks-empirically-at-execution-start` in the template's entry format, generic
wording, no project or person names; hand-copy to Codex, Cowork and Cursor; regenerate Antigravity.
**Commit** `feat(patterns): ship two forward patterns (single normative contract; re-run checks at execution start)`.

## Task 5 — Port records

`plugin-openai-codex/PORTING.md`, `plugin-antigravity/PORTING.md`, `plugin-claude-cowork/CLAUDE.md`
(or its porting note): one line each on cold-read behaviour and the subagent fact it rests on, with the date
read and the runtime version (Codex: `spawn_agent`, loads `AGENTS.md`, docs `main` read 2026-11-14;
Antigravity: `invoke_subagent`, startup context unrecorded; Cowork: no subagents). Then re-baseline
`PORT-LEDGER.json` **per port**, only for ports whose `prospect`/`auto` were verified in Tasks 2–3.
**Commit** `docs(ports): record cold-read behaviour per runtime; re-baseline verified ports`.

## Task 6 — Versions and changelog

Bump canonical `plugin.json` → 2.59.0; hand-bump `plugin-antigravity/plugin.json`, re-run `build.sh`
(`version.txt` syncs); `plugin-openai-codex/.codex-plugin/plugin.json` → `2.59.0-codex.0`;
`plugin-cursor-template/scripts/aria/VERSION` → `2.59.0-cursor.0`; Cowork → 1.8.4.
`CHANGELOG.md`: 2.59.0 section listing each adoption, the hygiene class fix, the two patterns, and
**Known limits**: live checks L1–L3 owed; Antigravity reader's startup context unknown; the cold read in
Codex is not instruction-free; descriptions deliberately unchanged, so `/auto`'s discovery text does not
mention `cold`. Read the merged changelog before trusting any auto-merge (2.57.7 lesson).
**Commit** `chore(release): 2.59.0 versions and changelog (Cowork 1.8.4)`.

## Task 7 — Full gates

From the real checkout path (not `/tmp`), nothing else running: `sh tests/run.sh` · plugin suite ·
`plugin-openai-codex/tests/run.sh` · `./release.sh` (Gates B and D) · `./release-codex.sh` ·
`./release-cursor.sh` · `./release-antigravity.sh` · Cowork `release.sh` (9,000-char description cap).
All bare exit 0. Record each zip's size. ⚠ If the plugin suite's real-rules guard trips, check
`~/.claude/rules` mtimes for a concurrent session before reading it as a defect.

## Task 8 — `/preflight` then `/retrospect`

Invoke `/preflight` (READY required) and `/retrospect range origin/main..HEAD`; fix what they surface if
objectively checkable; record the rest.

## Task 9 — Stop and report

Report commits, gate results, zips, findings not fixed, and the owed live checks. **Stop.** Push, tag and
GitHub release need Mike's explicit go for this release.

## Live checks owed after install (cannot be shown by a repro)

- L1 `/prospect file <real plan> --cold`: transcript shows a Plan-type dispatch whose prompt is only the
  template; findings ranked and each marked confirmed/refuted; git status unchanged.
- L2 `/auto plan <goal> cold=2`: stops after the first BLOCKER-free round or at 2, and says which.
- L3 a runtime without subagents (Cowork) prints the not-run line.
- Intended L1 input: the field-report author's plan and spec, if sent.

## Spec coverage

| Spec item | Task |
|---|---|
| R1 `/prospect --cold` (A1 Plan agent, A2 git status, A3 `Agent`) | 2 |
| R1 `/auto cold` / `cold=<N>`, D1 cap 4 | 3 |
| R2 receipts | 2 (Step 3), 3 (arc step 4) |
| R3 (`/auto` only, A5) | 3 |
| R4 | 3 |
| R5 table + §4.3 DEFER (A6) | 3 (arc step 2), 2 (§4.3) |
| R6 §4.6 Q4 + re-run at execution start | 2, 3 |
| R7 part (D5) | 3 |
| R9 half | 2 |
| `--summary` (D2) | 2 |
| Hygiene class (D4, A7) | 1 |
| Two patterns | 4 |
| Port propagation + Task 0 facts | 2, 3, 4, 5 |
| No description edits (A4) | ground rules; Task 3 A8 |
| AC1–AC7 | 1, 2, 3, 4, 7 |
