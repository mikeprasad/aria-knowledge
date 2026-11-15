# 2.59.0 plan — `/auto` and `/prospect` adoptions (v3)

**Spec:** `docs/superpowers/specs/2026-11-12-auto-prospect-adoption-2590-spec.md` (prospected 2026-11-12,
corrected 2026-11-14, revised and re-prospected 2026-11-15). **Branch:** `release/2.59.0`, worktree
`aria/.wt-2.59.0-aria-knowledge`, upstream `origin/main` so gate D reads commit messages. The branch sits on
local `main` `448e2d7`; its own commits are docs only.

**v3 (2026-11-15)** rewrites v2 whole after the spec's cold-reader revision (H4: the reader matches the
implementer's environment, not an empty context). New Task 2 ships the reader agent; later tasks renumber.
Identifier diffs v1→v2 and v2→v3 at the end.

**Where the expected values come from.** Measured with `git show release/2.58.0:<path>` at `fbe7c8e`
(2.58.0's own Task 6 done; its Tasks 7–10 not yet). `fbe7c8e` is not an ancestor of this branch, so Task 0
re-measures everything after the rebase.

**Execution environment (for the cold read and for whoever runs this).** A Claude Code session on the
maintainer's machine with this plugin installed, started in the worktree; the checkout is present.

⛔ **No source edit before Task 0 passes.**

## Ground rules (every task)

- One parenthesised absolute cd per directory-dependent command: `(cd "$WT" && <cmd>)`, `$WT` = the
  worktree path, set again in every call (shell state does not persist).
- **Red first, two kinds.** A *positive* arm (asserts new content exists) is seen failing on the pre-change
  tree, for the reason it names. A *guard* arm (asserts something stays silent or unchanged) cannot fail
  before the change by definition — prove it instead by one forced mutation: change the guarded thing, see
  the arm fail, restore from a byte backup, `cmp`.
- Commit with `git commit -F -` + heredoc, named paths only, ending
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. **No session-URL line** — this is a public repo
  and its CLAUDE.md forbids internal URLs; that rule outranks a harness attribution reminder.
- After every commit: `(cd "$WT" && sh plugin-claude-code/scripts/check-public-hygiene.sh "$WT")` → exit 0
  with `commit messages: origin/main..HEAD (N commits)`. Exit 2 = the gate's own self-test failed.
- Read bare exit codes; never one read through a pipe.
- Generated ports are regenerated, never hand-edited: Antigravity `./plugin-antigravity/build.sh`; Cursor
  `.mdc` `python3 plugin-cursor-template/scripts/port-skills-to-mdc.py`.
- No frontmatter `description` edits to any skill (claude.ai 1,024 per-skill cap; Gate B).
- Never `check-port-drift.sh --update all`.
- ⛔ **Never load a build of this plugin, with its hooks, into a real Claude Code session before release.**
  Measured 2026-11-15 (Claude Code 2.1.325): `claude --plugin-dir <dir>` with a plugin named
  `aria-knowledge` replaces the installed plugin for that run, skills and hooks both. The build's
  SessionStart then stamps `~/.claude/rules/*` with 2.59.0, and the installed older writer never replaces a
  newer stamp, so the live rules stay at a pre-release build. Every `--plugin-dir` probe in this plan uses
  a copy with the `hooks` key removed (Task 8).
- Suites by path: `tests/run.sh` (repo repros) · `plugin-claude-code/tests/run.sh` (plugin suite) ·
  `plugin-openai-codex/tests/run.sh` · `tests/repros/port-generation-idempotence.sh` ·
  `tests/repros/claude-ai-upload-limits.sh`.
- No push, tag or release. The plan ends at Task 10.

## Port facts (measured — the spec's measure-first port task)

| Port | Can start a subagent? | What the reader loads | Cold read behaviour |
|---|---|---|---|
| claude-code | yes — the plugin's own `aria-knowledge:cold-reader` (Task 2; tools Read, Grep, Glob, Bash) | startup CLAUDE.md and `~/.claude/rules/*.md`, like the implementer (a plugin-shipped agent, measured 2026-11-15, host 2.1.325); nested CLAUDE.md on read and plugin hooks (docs); no main auto memory, own system prompt (docs) | runs; fallback `general-purpose` if the type is absent |
| openai-codex | yes — `spawn_agent` | `AGENTS.md` from project root to cwd (openai/codex docs, `main`, read 2026-11-14) | runs; says the reader loaded `AGENTS.md` |
| antigravity | yes — `invoke_subagent` (repo `PORTING.md`; source date unrecorded) | unrecorded | runs; says startup context is unrecorded. Its `prospect` is generated from canonical with no overlay, so canonical's text is runtime-conditional. `build.sh` copies `skills/` and `template/` only, so `agents/` does not reach this port (correct) |
| claude-cowork | no ("no parallel subagents", its `foundational-review` skill) | — | prints `Cold read: not run — this runtime cannot start a subagent` |
| cursor-template | no subagent surface in the port | — | same not-run line (from canonical's conditional text) |

## Task 0 — Rebase and re-measure (gate for everything below)

1. `git ls-remote --tags origin v2.58.0`. **No line ⇒ stop and report "2.58.0 not tagged"** — do not poll.
   Also confirm `cowork-v1.8.3` exists (`git ls-remote --tags origin 'cowork-v1.8.3'`); absent ⇒ Cowork's
   bump in Task 6 becomes 1.8.3 and the plan is amended.
2. `(cd "$WT" && git fetch origin && git rebase --onto origin/main 448e2d7)`. ⛔ Not a plain
   `git rebase origin/main`: that would replay every local-`main` commit missing from `origin/main` too.
   Expected: exactly this branch's own docs commits replay (count them first:
   `git rev-list --count 448e2d7..HEAD`), with no conflicts. Then
   `git merge-base --is-ancestor "$(git rev-parse 'v2.58.0^{commit}')" HEAD` → exit 0.
3. Re-measure and compare:

   | Measurement | How | Expected (fbe7c8e, or 2026-11-15 for the last three rows) |
   |---|---|---|
   | Memory-name census | per tracked file under `plugin-*/`: `/usr/bin/grep -oE 'feedback_[a-z0-9_]+' <f> \| wc -l` | prospect 7 in each of 4 ports; retrospect 3 in each of 4; cursor `aria-commands.mdc` 10; `plugin-claude-code/tests/test-aria-rules-digest.sh` 1; nothing else |
   | Gate B total | `release.sh`'s Gate B `awk`, summed over `plugin-claude-code/skills/*/SKILL.md` | 19,259 of 19,968 |
   | `/auto` description | chars inside `description: "…"` | 1,005 |
   | `/prospect` structure | `grep -nE '^## Step \|^### 3\.5\.\|^### 4\.'` | Steps 0, 0.5, 1, 2, 3, 3.5 (3.5.1–3.5.4), 4 (4.1–4.10), 5, 6, 7, 8; no `Step 3.6`; §4.6 says "Three questions"; Step 8 lists gates 1–11 |
   | `/auto` arc steps | items under `### arc mode — full chain` | 7 items; item 3 contains "in place, now" |
   | Generators on a clean tree | run both, then `git status --short` | empty |
   | `plugin-claude-code/agents/` | `ls` | absent |
   | Self-report default | `grep -n 'SELFREPORT_TYPES:-' plugin-claude-code/scripts/config.sh` | `Explore` |
   | Host version | `claude --version` | record it; 2.1.325 was the measured host |

   After the generator row, restore only generated paths:
   `git restore --source=HEAD --worktree -- plugin-antigravity plugin-cursor-template` (the index equals
   HEAD here, nothing is staged). **Any difference in any row ⇒ stop, record it, amend this plan.**

## Task 1 — Hygiene class: memory names out, gate arm in

**Test** `tests/repros/public-hygiene-memory-names.sh`, scratch git repo, copied gate:
- (a) positive: tracked `plugin-x/skills/s/SKILL.md` holding a memory-file name → gate exit **1**, names the file.
  Red first: today's gate exits 0.
- (b) guard: the same name only in `docs/notes.md` → exit **0** (scope is `plugin-*/`). Prove by mutating
  the arm's scope to the whole tree → (b) fails → restore → `cmp`.
- (c) the real tree at HEAD → exit **0** (fails until step 2 lands; record that red).

⛔ The repro, the gate's self-test and every fixture **build the token at runtime**
(`t="feedback""_example_rule"`), never write it literally, or the plain grep in Verify finds the gate and
the repro themselves.

**Change.**
1. `plugin-claude-code/scripts/check-public-hygiene.sh`: arm fails on `feedback_[a-z0-9_]+` in tracked files
   whose path starts `plugin-`, reports file + count, joins the `any=` verdict; inline self-test gains a
   firing and a silent case (runtime-built token).
2. Replace each citation with the plain rule, canonical `prospect/SKILL.md` + `retrospect/SKILL.md`, then the
   identical sentences in `plugin-openai-codex/` and `plugin-claude-cowork/`. Drop `(per \`…\`)` where the
   sentence already states the rule; otherwise state it ("one ask at a time unless the user asks for a
   batch"). Reword the comment in `plugin-claude-code/tests/test-aria-rules-digest.sh`.
3. Regenerate Antigravity (copies the gate into `bin/` too) and Cursor.

**Verify.** `/usr/bin/grep -rlE 'feedback_[a-z0-9_]+' plugin-*` → exit **1**, run in the same invocation as a
positive control that applies the same pattern to a scratch file holding the runtime-built token → exit 0.
Repro 3/3 · plugin suite · idempotence. **Commit**
`fix(hygiene): shipped skills cite rules in plain words; gate fails on memory-file names under plugin-*/`.

## Task 2 — The reader agent (spec D6, AC8)

**Test** `tests/repros/cold-reader-agent.sh` over `plugin-claude-code/agents/cold-reader.md`:
- G1 positive: the file exists. Red first: it does not.
- G2 positive: the frontmatter keys are exactly `name`, `description`, `tools`, in any order, and nothing else.
- G3 positive: `name` is `cold-reader`; `tools` is exactly `Read, Grep, Glob, Bash`.
- G4 positive: `description` is under 200 chars and contains no `<`, `>`, `[`, `]`.
- G5 positive: the body (everything after the closing `---`, trimmed) equals exactly
  `Follow the prompt you are given. Do not create, edit or delete any file.`
- Guards, each proven by one mutation on a byte backup → red → restore → `cmp`: add `Edit` to `tools` (G3);
  add `model: haiku` (G2); append "This plan is about X." to the body (G5).

**Change.** Create `plugin-claude-code/agents/cold-reader.md`:

```
---
name: cold-reader
description: Read-only reviewer that /prospect --cold dispatches. It reads one file and answers the questions in its prompt.
tools: Read, Grep, Glob, Bash
---
Follow the prompt you are given. Do not create, edit or delete any file.
```

Extend `tests/repros/claude-ai-upload-limits.sh` to apply its description rules to `agents/*.md` of each
port it scans, with a planted control (an agent description holding `<`) that must be reported. `release.sh`
needs no change: it copies the whole plugin directory (`rsync -a`), so `agents/` ships.

**Verify.** Repro all arms; upload-limits; plugin suite; idempotence (antigravity unaffected: `build.sh`
does not copy `agents/`). **Commit** `feat(agents): a read-only cold-reader agent for /prospect --cold`.

## Task 3 — `/prospect`

**Test** `tests/repros/prospect-adoptions.sh` over every carrying port — `plugin-claude-code`,
`plugin-openai-codex`, `plugin-antigravity`, `plugin-claude-cowork` `skills/prospect/SKILL.md`, and the
prospect section of `plugin-cursor-template/.cursor/rules/aria-commands.mdc`:
⛔ **Cursor scoping (prospect gate C2).** `aria-commands.mdc` bundles `/prospect` (from its `## /prospect`
header) and `/retrospect` (from `## /retrospect`), and `/retrospect` also says "Three questions" and has a
Step 3.5. Every Cursor arm first extracts the `/prospect` section — from `## /prospect` to the next line
starting `## /` — and asserts only inside it. Every Step 3.6 arm likewise extracts Step 3.6 first (from
`## Step 3.6` to the next `## Step`) and asserts case-insensitively inside it.
- P1 positive: `--cold` and `--summary` in Step 0's modifier list (all ports) and in `argument-hint`
  (claude-code, codex **and cowork**, whose frontmatter carries one — prospect gate C1; `build.sh` strips
  `argument-hint` from Antigravity; Cursor's `.mdc` has no frontmatter per skill).
- P2 positive: a `## Step 3.6` heading naming the cold read.
- P3 positive: the template between `<!-- cold-read-template:begin -->` / `<!-- cold-read-template:end -->`
  is byte-identical across all carrying ports and holds five numbered items. Guard half: mutate one
  character in one port → red → restore from byte backup → `cmp`. ⛔ The template text must avoid what the
  generators rewrite: no `~/.claude/` (Antigravity rewrites it), no run of 3+ newlines (Cursor collapses
  them), no "(Claude Code variant" text.
- P4 positive (AC7): Step 3.6 names `aria-knowledge:cold-reader`, its `general-purpose` fallback, the stamp
  "Claude Code docs read 2026-11-15; measured on 2.1.325", the words "fresh reader", the in-place reading
  rule (D7), and the four known gaps (auto memory · own system prompt · SubagentStart hooks · startup files
  follow the session's working directory); the Cold read block lists subagent type, where the plan was
  read, `git status` before/after, and the item-5 comparison.
- P5 positive: §4.6 says "Four questions"; Q4 is the in-flight-work question.
- P6 positive: Step 6 carries the `--summary` rule.
- P7 positive: claude-code frontmatter `allowed-tools` contains `Agent`.
- P8 positive: canonical Step 3.6 holds the not-run line for a runtime that cannot start a subagent.
- P9 guard: inside Step 3.6, no port contains "instruction-free", "context-free" or "Plan agent"
  (case-insensitive; spec S3). Prove by inserting "the built-in Plan agent" into one port's Step 3.6 → red →
  restore.
- P10 guard: every port's `description` is byte-unchanged from the pre-change tree. Prove by mutation.

**Change (canonical `plugin-claude-code/skills/prospect/SKILL.md`).**
1. Frontmatter: `argument-hint` gains `[--cold] [--summary]`; `allowed-tools` gains `Agent`.
2. Step 0 modifier list: `--cold` (one fresh-reader round, Step 3.6; ~1 subagent; the reader loads your own
   startup instruction files, so a round costs at least their size plus the plan — no number, spec S6) and
   `--summary`.
3. Step 3: the receipt rule (spec R2).
4. Step 3.5.1: inherited claims first (spec R9 half). Step 3.5.2: a read-only command without a receipt is a
   candidate to run.
5. New `## Step 3.6: Cold read (opt-in: \`--cold\`)` after 3.5.4, runtime-conditional, following spec R1
   steps 1–6: read the plan in place (scratch copy only when the environment line excludes the checkout or no
   file exists); fill the five-item template; environment line from the plan, else `none` + a finding;
   dispatch — Claude Code: `aria-knowledge:cold-reader`, else `general-purpose` and say so; another runtime
   with a subagent tool: that tool, and the block says what the reader loads (Codex: `AGENTS.md`; unrecorded
   ⇒ say so); no subagent ⇒ the not-run line; the four known gaps; `git status --porcelain` before/after (it
   cannot see writes outside the repo — say so); findings are leads, checked against the plan before they
   count. ⛔ Never name the Plan agent in this step (S3).
6. §4.3: a confirmed cold-read BLOCKER ⇒ that step is not PROCEED; a step depending on an unanswered
   "Decisions only the human can make" row ⇒ DEFER citing the row.
7. §4.6: "Four questions"; Q4 per spec R6; "none found" names its instrument.
8. §4.8: overall cannot be PROCEED while a confirmed BLOCKER stands; Cold read block (round, subagent type
   and fallback reason, where read, environment line, findings by rank confirmed/refuted, git status result,
   item-5 list compared with the implementer's expected set, the four known gaps, prompt char count).
9. Step 6: `--summary` rule (spec).
10. Step 8: gate 12 — with `--cold`, Step 3.6 ran or printed its not-run reason.

**Ports.** Codex by hand (no ADR-094 gate; root var `${ARIA_PLUGIN_ROOT}`; same conditional text — its
runtime takes the subagent-tool branch). Cowork by hand: same text (it resolves to the not-run branch), no
`allowed-tools` change. Regenerate Antigravity and Cursor. **Verify.** Repro all arms; plugin suite; codex
suite; idempotence; upload-limits. **Commit**
`feat(prospect): --cold adds a fresh-reader review round; command receipts; --summary` — body records
`claude --version`.

## Task 4 — `/auto`

**Test** extend `tests/repros/auto-modes.sh` for canonical + Codex + Antigravity `auto/SKILL.md`:
- A1 positive: Step 0 lists `cold` / `cold=<N>` with a worked ENDS case (all three); `argument-hint` contains
  `[cold|cold=<N>]` (canonical + Codex only — stripped in Antigravity).
- A2 positive: Step 0¾ has a cold-read item; Step 0.5's contract states "~1 subagent per round, up to N".
- A3 positive: arc steps 3 **and 5** pass `--cold` when `cold` is on; rounds repeat until no confirmed BLOCKER
  or N (default 4); R3 trigger; R4 rule (from the third amendment round: regenerate whole + identifier diff,
  every drop with a reason).
- A4 positive: arc step 2 carries the "Decisions only the human can make" table rule; arc step 4 the receipt rule.
- A5 positive: arc step 6 re-runs the plan's pre-execution checks and compares upstream-changed files to the plan's files.
- A6 positive: Step 0.5 lists peer activity and says "activity, not ownership".
- A7 positive: Step 5 says cold-read rounds count toward `agents=`.
- A8 guard: `description` byte-unchanged. Prove by mutation.

**Change** canonical `plugin-claude-code/skills/auto/SKILL.md` at those sections; Codex by hand; regenerate
Antigravity and Cursor. Cowork has no `/auto`. **Verify** repro all arms; plugin + codex suites;
idempotence; upload-limits. **Commit**
`feat(auto): cold review rounds, cut-the-check trigger, regenerate after two amendments, human-only decisions table`.

## Task 5 — Two shipped patterns

**Test** `tests/repros/shipped-patterns-2590.sh`: both `## <name>` entries carry all seven fields of the
template's format — Tier · First identified · One-line summary · Detection cues · Why it's a problem ·
Counter-discipline · References — in `plugin-claude-code/template/rules/retrospect-patterns.md`,
`plugin-openai-codex/template/rules/…`, `plugin-claude-cowork/template/rules/…`,
`plugin-antigravity/template/rules/…` (generated) and `plugin-cursor-template/knowledge/rules/…`. Red first.

**Change** add `contract-restated-anywhere-is-a-divergence-already-scheduled` and
`re-run-pre-execution-checks-empirically-at-execution-start`, generic wording, no project or person names;
hand-copy to Codex, Cowork, Cursor; regenerate Antigravity. **Verify** repro; idempotence. **Commit**
`feat(patterns): ship two forward patterns (one normative contract; re-run checks at execution start)`.

## Task 6 — Versions and changelog

Canonical `plugin.json` → 2.59.0; hand-bump `plugin-antigravity/plugin.json`, run `build.sh`
(`version.txt` syncs); `plugin-openai-codex/.codex-plugin/plugin.json` → `2.59.0-codex.0`;
`plugin-cursor-template/scripts/aria/VERSION` → `2.59.0-cursor.0`; Cowork → 1.8.4 (per Task 0 step 1).
`CHANGELOG.md` 2.59.0: each adoption, the new `aria-knowledge:cold-reader` agent, the hygiene class fix, the
two patterns, and **Known limits**: the reader is fresh, never instruction-free, in every runtime (Claude
Code: it loads your startup CLAUDE.md, rules and hooks like the implementer, but not the main session's
auto memory, it has its own system prompt, and its startup files follow the session's working directory;
Codex: `AGENTS.md`; Antigravity: unrecorded); why the built-in Plan agent is not used (it skips startup
CLAUDE.md and rules, measured 2026-11-15 on 2.1.325); the agent has no `model` key, so it runs on the
default subagent model, and a small one can fail under a large instruction load; the per-round cost figure
from Task 8; `git status` cannot see writes outside the repo; a plugin with an `agents/` directory has not
yet been installed on claude.ai (L4); descriptions deliberately unchanged, so `/auto`'s discovery text does
not mention `cold`; live checks owed. **Commit** `chore(release): 2.59.0 versions and changelog (Cowork 1.8.4)`.

## Task 7 — Port records and ledger (after the version bump, so the ledger stamps 2.59.0)

1. Add the Port facts table's row to `plugin-openai-codex/PORTING.md`, `plugin-antigravity/PORTING.md` and
   `plugin-claude-cowork/CLAUDE.md`, each with its source and date.
2. `PORT-LEDGER.json`: `check-port-drift.sh --update <port>` re-hashes **every** surface of that port, so
   re-baseline only a port verified in full: **antigravity** (fully regenerated; idempotence proves it).
   **Do not** re-baseline codex, cowork or cursor this release — their hand-synced surfaces beyond
   `prospect`/`auto`/the pattern template were not verified; record that in the CHANGELOG known limits.
   claude-code is the baseline (version only).
**Commit** `docs(ports): record cold-read behaviour per runtime; re-baseline antigravity`.

## Task 8 — Full gates and the startup-context probe (AC9)

1. From the real checkout path (not `/tmp`), nothing else running: the five suites under Ground rules ·
   `plugin-claude-code/scripts/check-port-drift.sh` (report mode) · both generators → zero diff (AC4) ·
   `./release.sh` (Gates B and D) · `./release-codex.sh` · `./release-cursor.sh` · `./release-antigravity.sh` ·
   `plugin-claude-cowork/release.sh` (9,000-char description cap). All bare exit 0. Record each zip's size.
   If the plugin suite's real-rules guard trips, check `~/.claude/rules` mtimes for a concurrent session first.
2. **AC9 probe** (all paths under the session scratchpad, `$SP`):
   - `cp -R "$WT/plugin-claude-code" "$SP/ak-probe"`, then delete the `hooks` key from
     `$SP/ak-probe/.claude-plugin/plugin.json` with `python3 -I`. Expected: `grep -c '"hooks"'` on that file
     → `0`. ⛔ Never pass the real `plugin-claude-code/` to `--plugin-dir` (Ground rules).
   - `$SP/ak-proj/CLAUDE.md` holding one line `SENTINEL-AC9-<8 random hex>`.
   - Record line 1 and `cksum` of each `~/.claude/rules/*.md`.
   - `(cd "$SP/ak-proj" && claude -p --plugin-dir "$SP/ak-probe" --allowedTools Agent --output-format json "<dispatch aria-knowledge:cold-reader and Plan, each told: do not use any tool; quote any token beginning SENTINEL- from your startup text, or say NONE>")`.
     Expected: exit 0.
   - From `~/.claude/projects/<slug of ak-proj>/<session>/subagents/`: map each `agent-*.meta.json`
     `agentType`; count the sentinel in each `agent-*.jsonl`. Expected: `aria-knowledge:cold-reader` ≥ 1,
     `Plan` = 0. Plan = 0 with the reader ≥ 1 is the two-sided control; both 0 voids the check.
   - Re-read line 1 of each `~/.claude/rules/*.md`. Expected: no file stamped `2.59.0`. A changed checksum
     without that stamp is another session's ordinary SessionStart write — record it, do not fail on it.
3. **Cost of one real round (spec S6).** Same hook-stripped copy; cwd = the maintainer's projects root (the
   directory sessions normally start in); dispatch `aria-knowledge:cold-reader` once with the five-item
   template on this plan file. Read the reader's input tokens from its transcript. Record it, with the host
   version and "hooks stripped, so a floor", for the CHANGELOG.
4. Update the CHANGELOG known-limits cost line with the figure from 3 (amend Task 6's commit only by a new
   commit). **Commit** `docs(changelog): measured cold-read cost per round`.

## Task 9 — `/preflight`, then `/retrospect`

Invoke `/preflight` (READY required) and `/retrospect range origin/main..HEAD`; fix what they surface when
objectively checkable; record the rest.

## Task 10 — Stop and report

Report commits, gate results, zip sizes, the AC9 counts, the per-round cost figure, findings not fixed.
**Stop.** Push, tag and GitHub release need Mike's explicit go for this release.

---

## After release — NOT tasks in this plan

Live checks (cannot be shown by a repro): L1 `/prospect file <real plan> --cold` — transcript shows an
`aria-knowledge:cold-reader` dispatch whose prompt is only the template, findings ranked and each marked
confirmed/refuted, `git status` unchanged, and the item-5 list printed and compared; L2 `/auto plan <goal>
cold=2` stops after the first BLOCKER-free round or at 2 and says which; L3 Cowork prints the not-run line;
L4 the 2.59.0 plugin zip (now with `agents/`) installs on claude.ai — Mike uploads it. (Note, not an action:
the field-report author offered his plan and spec; if Mike forwards them, they are the intended L1 input.
Do not go and fetch them.)

## Spec coverage (a reference table, not tasks)

| Spec item | Task |
|---|---|
| R1 `/prospect --cold` (A1–A3, H4, D6–D8, S2–S6) | 2, 3 |
| R1 `/auto cold` / `cold=<N>`, cap 4, arc steps 3 + 5 | 4 |
| R2 receipts | 3, 4 |
| R3 (`/auto` only) | 4 |
| R4 | 4 |
| R5 table + §4.3 DEFER | 4, 3 |
| R6 §4.6 Q4 + re-run at execution start | 3, 4 |
| R7 part | 4 |
| R9 half | 3 |
| `--summary` | 3 |
| Hygiene class | 1 |
| Two patterns | 5 |
| Port facts (measure first) | done above; recorded in 7 |
| No description edits | ground rules; P10, A8 |
| AC1–AC6 | 1, 3, 4, 5, 8 |
| AC7 | 3 (P4, P9) |
| AC8 | 2 |
| AC9 + cost figure | 8 |
| L1–L4 | after release |

## Identifier diff — v1 → v2

| Identifier | v1 | v2 | Reason |
|---|---|---|---|
| Task 0 rebase | `git rebase origin/main` | `git rebase --onto origin/main 448e2d7` | v1 would replay local-`main`-only commits |
| Task 0 wait | "Wait until" | stop and report | no in-session polling |
| Task 0 checks | — | + `cowork-v1.8.3` check, generator restore step, structure grep that matches its own command | cold read F-items |
| Task 1 (c) / Verify | literal token | runtime-built token + same-pattern control | B2: v1's verify could never pass |
| Task 2 P1 | argument-hint in every port | modifier list everywhere; argument-hint in claude-code + codex | Antigravity strips it |
| Task 2 P2 | `### Step 3.6` | `## Step 3.6` | heading level |
| Task 2 P3 | byte-identity | + generator-safe text rule | generators rewrite text |
| Task 2 P4 | "instruction-free" | "fresh reader", two-version stamp, received-instructions list | B1 |
| Task 2 P9, P10 | — | added (guards) | B1 wording; description guard per port |
| Task 3 A1 | argument-hint in all three | carve-out for Antigravity | stripped by `build.sh` |
| Task 3 A3 | arc step 3 | arc steps 3 and 5 | spec says every `/prospect` the arc runs |
| Task 4 fields | five | seven | template format has seven |
| Task 5 (v1) Port records | before versions | becomes Task 6, after versions | B6: ledger would stamp the old version |
| Task 6 (v1) Versions | after records | becomes Task 5 | B6 |
| Task 6 ledger | `--update` every verified port | antigravity only | B5: `--update` re-hashes the whole port |
| Port Task 0 | credited to Tasks 2–5, not done | done; Port facts table | B4 |
| Antigravity behaviour | contradictory | runs; startup context unrecorded | B3 |
| Ground rules red-first | every test red first | positive red first; guards proven by mutation | B7 |
| Live checks | after Task 9, read like a task | "After release — NOT tasks" | cold-read §4 |
| Task 6 (v1) changelog-merge note | present | dropped | no merge happens, only a rebase |
| Dropped: none of R1–R9, `--summary`, hygiene, patterns, AC1–AC7 | | | |

## Identifier diff — v2 → v3

| Identifier | v2 | v3 | Reason |
|---|---|---|---|
| Header / Execution environment | — | states the implementer's environment | the cold read's environment line reads it |
| Ground rule: no hooked `--plugin-dir` build | — | added | measured 2026-11-15: same-name plugin replaces the installed one, hooks included |
| Ground rule: description edits | none anywhere | none to any **skill** | the new agent file needs a description; it is not counted by Gate B and is held to the skill precautions (Task 2 G4) |
| Port facts, claude-code row | built-in Plan agent; skips startup CLAUDE.md | `aria-knowledge:cold-reader`; loads startup CLAUDE.md + rules; fallback `general-purpose` | spec H4, D6 |
| Port facts, antigravity row | — | + `build.sh` does not copy `agents/` | spec port note |
| Task 0 table | 6 rows | + `agents/` absent, self-report default `Explore`, host version | D6, D8 |
| Task 2 (new) | — | the reader agent + AC8 repro + upload-limits on `agents/*.md` | spec D6, AC8 |
| Task 2 `/prospect` | Task 2 | Task 3 | renumbered after the new Task 2 |
| Task 3 `/auto` | Task 3 | Task 4 | renumbered |
| Task 4 patterns | Task 4 | Task 5 | renumbered |
| Task 5 versions | Task 5 | Task 6 (+ agent, Plan-not-used reason, model limit, cost line, L4 in known limits) | renumbered; spec S6, L4 |
| Task 6 port records | Task 6 | Task 7 | renumbered |
| Task 7 gates | Task 7 | Task 8 (+ AC9 probe, real-round cost measurement) | spec AC9, S5, S6 |
| Task 8 preflight/retrospect | Task 8 | Task 9 | renumbered |
| Task 9 stop | Task 9 | Task 10 (+ AC9 counts, cost figure in report) | renumbered |
| Task 3 step 5 (Step 3.6) | copy to scratch always; dispatch Plan | read in place unless the environment excludes the checkout; dispatch `aria-knowledge:cold-reader`; never name Plan | D7, D6, S3 |
| Task 3 step 2 (Step 0 line) | "measured ~190k subagent tokens" | names the cost driver, no number | S6: a workspace-specific number is wrong elsewhere |
| P3 | byte-identity | + five numbered items | template now holds item 5 |
| P4 | Plan agent + two-version stamp | `aria-knowledge:cold-reader`, fallback, 2026-11-15 / 2.1.325 stamp, four gaps, D7 | AC7 |
| P9 | instruction-free / context-free | + "Plan agent", section-scoped, case-insensitive | S3 |
| L1 | Plan-type dispatch | `aria-knowledge:cold-reader` dispatch + item-5 comparison | H4 |
| L4 | — | added | spec L4 |
| Dropped: none of v2's tasks, arms or rules | | | |
