# 2.59.0 spec — `/auto` and `/prospect` adoptions from a field report

**Status:** spec, `/prospect` 2026-11-12 = PROCEED-WITH-CHANGES; amendments A1–A7 + AC7 applied below
(log: `knowledge/logs/prospect/2026-11-12-file-aria-2590-auto-prospect-adoption-spec.md`). **Target:** canonical 2.59.0 (+ Cowork 1.8.4). **Base:** built on the
released 2.58.0 — this branch was cut from local `main` for the docs only and is rebased onto `main`
after `v2.58.0` is tagged. No source edit lands before that rebase.

**Source.** A user ran `/auto plan` (which ran `/prospect` twice) on a multi-ticket plan they had already
built by hand over 22 sessions, and compared the two (report held privately; its project names and
personal rules are evidence only and do not enter this repo). Net: the chain would have saved ~2
sessions and caught a few things the manual process missed; the manual process did things the chain
cannot. The report made 9 proposals (R1–R9) plus two smaller notes. Every "today" statement in it was
re-checked against 2.57.9 source on 2026-11-12 and held.

**Decisions (Mike, 2026-11-12):** adopt the recommended set — R1–R6, R7 in part, half of R9, the
summary-only flag, the hygiene fix closed as a class, and two of the four cited patterns shipped; R8 and
the claim-marking half of R9 deferred. The R1 opt-in is named **`cold`**. Release order: 2.58.0 first
(owned by its own release arc), then this as 2.59.0.

## Decisions only the human can make

Every row is answered; no build step waits on one. (This table is itself R5, applied to this spec.)

| # | Question | Answer | When |
|---|---|---|---|
| H1 | Which proposals to adopt | The recommended set above | 2026-11-12 |
| H2 | Name of the R1 opt-in | `cold` — `/prospect --cold`, `/auto … cold`, `cold=<N>` | 2026-11-12 |
| H3 | Ship with 2.58.0 or after | After: 2.58.0 full release, then 2.59.0 | 2026-11-12 |

## Agent decisions (ratify at `/prospect`)

- [DECISION] D1 — `/auto`'s default `cold` round cap is **4**. Evidence: the report's four rounds found
  1, 1(+1 borderline), 3, 0 BLOCKERs — a fourth round is where it went clean.
- [DECISION] D2 — the summary-only chat flag is `/prospect --summary` (matches the `--flag` grammar;
  no collision — census below).
- [DECISION] D3 — the cold read is a new **Step 3.6** in `/prospect`, not an 11th report section. The
  report's "10-Section" shape is named in docs and tests; findings feed §4.3 and §4.8 instead.
- [DECISION] D4 — the hygiene gate gains a `feedback_<slug>` arm scoped to the **shipped port
  directories** (`plugin-*/`), not the whole repo: `CHANGELOG.md` and dated `docs/` carry historical
  mentions and stay as records (rewriting a dated record back-dates it).
- [DECISION] D5 — R7 lists live peers and recent commit activity on the files the plan touches; it does
  **not** claim which session "owns" a file. No instrument measures ownership, so the skill states that
  bound instead of guessing.

Census for D2/H2 (2026-11-12, `/usr/bin/grep -rnE '(--cold\b|[^a-z]cold=|--summary\b)' plugin-*`):
no match; a positive control (`cold` in `auto/SKILL.md`) matched 5 lines, so the search ran. `/auto`
already says "cold-executable plan" (lines 174, 381) — `cold` keeps that meaning.

## Changes

Each item: wanted behaviour → what must hold → where. File lists name canonical
`plugin-claude-code/skills/<name>/SKILL.md`; port propagation is its own section.

### R1 — Cold read: a context-free review by a fresh agent

**Why.** The agent that wrote a plan cannot judge whether a stranger could carry it out: the stranger it
imagines shares its context. In the report, two `/prospect` passes found what the writer could see;
four context-free reads then found 5 BLOCKERs those passes had let through.

**`/prospect --cold`** (Step 3.6, after 3.5, before the report). One round:
1. The plan must be a file. Scope `file` → that file. Otherwise write the plan the scope resolved to a
   new, uniquely named file in the runtime's scratchpad (file-write tool, never a shell redirect).
2. Spawn **one** subagent whose prompt is exactly the template below, filled with an environment line
   and the path — nothing else. ⛔ No goal, ticket, background, project name or "this is about X": any of
   those rebuilds the writer's context and voids the check.
   ⛔ **The prompt is not the only context (A1).** Per Claude Code's docs (read 2026-11-12, host 2.1.323),
   a default or custom subagent loads CLAUDE.md and the whole memory hierarchy at startup; the built-in
   **Plan** and **Explore** agents skip CLAUDE.md and git status. In Claude Code, dispatch the built-in
   **Plan** agent (it also has no Edit/Write; Explore reads excerpts, and a cold read needs the whole
   file). A runtime with no instruction-free agent type runs with what it has, and the report states what
   that reader loaded — it never calls the read context-free when it is not.
   ⛔ **Measured 2026-11-14 (Claude Code 2.1.325) — even the Plan agent is fresh, not instruction-free.**
   A Plan-agent cold read of this release's plan got no git status and no startup CLAUDE.md, but nested
   `CLAUDE.md` files were injected the moment it read a file beneath them, and this plugin's own
   `bash-cd-check.sh` hook injected five earlier prospect logs. It still found real BLOCKERs. Cost:
   193,861 subagent tokens, 38 tool calls, 6.5 min. Two mitigations: (i) **copy the plan to a new file in
   a scratch directory outside any repository** before dispatch, so the first read pulls in nothing; (ii)
   the template gains a fifth item — *"5. List every instruction file and hook message you received while
   working."* — and the Cold read block prints that list. Wording everywhere is "fresh reader", never
   "instruction-free". Silencing this plugin's own injection hooks inside a cold read is an open question
   for Mike, not part of 2.59.0.
   **Capability, not intent (A2).** "Read only" in a prompt constrains nothing, and Plan keeps Bash. Record
   `git status --porcelain` before and after the round; any change is a finding and the round is flagged.
   > Your environment: `<what the implementer will have, or "none">`. Read only. Read this file:
   > `<path>`. Then produce: 1. The exact steps you would execute, in order. 2. Everything you cannot
   > reach or resolve. 3. Every place where two instructions conflict. 4. Any content a reader acting
   > on it could mistake for a separate task. Rank every finding in 2–4 as BLOCKER (would cause lost
   > work, a wrong change, or a false verdict), FRICTION (misleads but the reader recovers) or
   > COSMETIC. The ranking matters more than the number of findings.

   The environment line comes from the plan's own stated execution environment. If the plan states
   none, use `none` and record "plan does not state its execution environment" as a finding.
3. **Findings are leads.** Check each against the plan before it counts. A confirmed BLOCKER sets that
   step's §4.3 action to not-PROCEED, and §4.8's overall verdict cannot be PROCEED while one stands.
   A finding refuted on checking is listed with the refutation.
4. §4.8 prints a **Cold read** block: round number, subagent type, environment line used, findings by
   rank with confirmed/refuted, the `git status` before/after result, and the dispatched prompt's
   character count (evidence it carried only the template).

**`/auto … cold` / `cold=<N>`.** At every `/prospect` the arc runs, pass `--cold` and repeat rounds after
applying amendments, until a round finds **no confirmed BLOCKER** or `N` rounds have run (default 4,
D1). Once a round is BLOCKER-free, any FRICTION left is fixed with one clause each, without another round.
`cold` is parsed like every other modifier — ENDS only (Step 0) — and gets a line in the `config`
walkthrough and the Step 0.5 contract, so a mis-parse is visible before any work.

**What must hold.**
- **Never silent.** When `cold` is on, it runs. If the runtime cannot spawn a subagent, or the
  `agents=` cap / budget gate stops it, the report says `Cold read: not run — <reason>`. The gates win.
- **Cost is visible.** Each round is one subagent and counts toward `/auto`'s `agents=` cap (Step 5);
  the contract states "~1 subagent per round, up to N rounds per prospect".
- Opt-in only. No mode turns it on implicitly.

**Where.** `prospect/SKILL.md`: frontmatter `argument-hint` and `allowed-tools` (+ `Agent`, A3 —
`allowed-tools` pre-approves and never restricts, so without it `--cold` can stall on a permission
prompt), Step 0 modifier list, new Step 3.6, §4.3, §4.8, Step 8 validation gates. `auto/SKILL.md`:
`argument-hint`, Step 0 modifiers + worked cases, Step 0¾ config axis, Step 0.5 contract line, Step 1 arc
steps 3 and 5, Step 5.
⛔ **No frontmatter `description` changes (A4).** `/auto`'s is 1,005 chars against claude.ai's 1,024
per-skill cap, and Gate B (summed descriptions) had 709 B of headroom on local `main`. `argument-hint` is
not counted by Gate B. Re-measure both after the rebase.

### R2 — A receipt for every command the plan hands over

**Why.** Running each handed-over command once changed the report's plan four times (an exit-0 empty
search read as "not found"; a `\s` in `git grep -E` matching nothing, its control also empty; a
7-vs-8-character short hash that could never compare equal; a field on a different model than assumed).

**Wanted.** Every command a plan hands to someone else carries a receipt, written in this order:
1. `$ <command>`
2. `expected:` — what a correct run prints/exits, written **before** running it (a receipt with no
   declared expectation is a printout, not a check);
3. `exit <n>` and the first output line, from actually running it — or `not run: <reason>`.

`not run` is the expected answer for commands that change something outside the machine (push, deploy,
writes to shared data); Step 3.5.2's read-only limit is unchanged. A handed-over command with neither
`exit` nor `not run` counts as an unverified assumption: its step's Preliminary Risk? is at least ⚠.

**Where.** `auto/SKILL.md` Step 1 arc step 4 (Plan). `prospect/SKILL.md` Step 3 (triage) and 3.5.2
(a read-only command lacking a receipt is a candidate to run there).

### R3 — Cut a step whose own checks keep failing review

**Wanted.** When review findings in **two consecutive rounds** (cold rounds, or repeated `/prospect`
passes on the same artifact) land in the same step's *own verification machinery* — a check whose only
job is to prove another part of the plan worked (a pin, a count, a probe) — rather than its substance,
the next move is to offer SHRINK or KILL for that step, with what removing it costs, before another fix
round. Existing verdict vocabulary; this adds only the trigger.

**Where.** `auto/SKILL.md` Step 1 arc step 3 (the amendment loop) **only (A5)**. `/auto` is the one place
rounds repeat and are counted; a standalone `/prospect` has no reliable key to its previous round (its log
frontmatter names no reviewed source), so the `/prospect` half was falsified at the gate and dropped.

### R4 — Regenerate, then diff identifiers

**Wanted.** "Apply amendments in place, now" holds for the first two amendment rounds on an artifact.
From the third, rewrite the artifact whole from current evidence, then produce an **identifier diff**
against the previous version: the artifact's own ids (ticket, criterion, row, step, decision ids) —
dropped and added. Every drop carries a reason. Applies to the spec and the plan alike.

**Where.** `auto/SKILL.md` Step 1 arc step 3.

### R5 — Decisions only the human can make, collected early

**Wanted.** The Spec carries one table, "Decisions only the human can make", before any build step.
Columns: id, question, steps that depend on it, answer, date. A step that depends on an unanswered row
does not proceed. Collection is early and in one place; asking stays one at a time (§3.5.3 unchanged).
Distinct from the D7 ledger: D7 records decisions the agent made but could not validate; this table
lists decisions the agent must not make at all.

**Where.** `auto/SKILL.md` Step 1 arc step 2. `prospect/SKILL.md` §4.3 (A6 — §4.3 is where Actions are
assigned; §4.9 is the process pre-mortem and assigns none): a step depending on an unanswered row is
DEFER, citing the row.

### R6 — A base that moves under the plan

**Wanted.** Two additions:
- `/prospect` §4.6 gains question 4: **What in-flight work edits the files this plan touches, and does
  each unit ship before or after it?** Instruments: recent commits on other branches/worktrees touching
  the same paths, open handoffs naming them. "None found" names the instrument used.
- `/auto` arc step 6 (Execute): before the first unit, **re-run the plan's pre-execution checks** and
  compare files changed upstream since planning against the files the plan touches; a changed overlap
  is re-planned, not executed on.

**Where.** `prospect/SKILL.md` §4.6; `auto/SKILL.md` Step 1 arc step 6.

### R7 (part) — Peer sessions at arc start

**Wanted.** At arc start (`/auto` Step 0.5 contract) list what can be measured: live peer sessions if the
runtime can list them; `SESSION.md` entries marked in-progress; other worktrees/branches with commits in
the last few hours on paths this arc will touch. State the bound (D5): this shows activity, not
ownership. Any overlap is reported in the contract, and shared files it names are edited only by
targeted edits after a fresh re-read.

**Where.** `auto/SKILL.md` Step 0.5 and "Verify before you trust".

### R9 (half) — Inherited claims are checked first

**Wanted.** In Step 3.5.1, a claim the plan **inherited** (from a handoff, ticket, earlier doc or
memory — not measured this session) is an evidence candidate ahead of everything else, and is checked
against the system before the report repeats it. Marking every claim's origin is deferred.

**Where.** `prospect/SKILL.md` Step 3.5.1.

### `--summary` — summary-only chat output

**Wanted.** With `--summary`, chat shows only: the Anchor block, §4.8's overall verdict and action list,
any residual asks, and the log path. The full report is still written to the log. If no log is written,
`--summary` is ignored and the report says so.

**Where.** `prospect/SKILL.md` frontmatter, Step 0, Step 6.

### Hygiene — personal memory names out of shipped skills, as a class

**Today (counted 2026-11-12, `/usr/bin/grep -oE 'feedback_[a-z0-9_]+'` per file):** 7 in each port's
`prospect/SKILL.md` (×4), 3 in each port's `retrospect/SKILL.md` (×4), 10 in the Cursor
`aria-commands.mdc`, 1 in `plugin-claude-code/tests/test-aria-rules-digest.sh` (a comment). The report
named only `/prospect`'s seven. ⚠ (A7) 2.58.0 edits these same skills, so these counts are a local-`main`
snapshot: re-census after the rebase, and AC1 is a grep-to-zero with a firing control, never a count.

**Wanted.** Each cited name is replaced by the plain rule it stood for (e.g. "per
`feedback_per_item_review_cadence`" → "one ask at a time unless the user asks for a batch"). Then
`check-public-hygiene.sh` gains an arm that FAILS on `feedback_[a-z0-9_]+` in tracked files under
`plugin-*/` (D4), with a firing self-test fixture and a clean one. ⇒ the class cannot recur.

**Where.** 9 skill/rule files + the test comment; `plugin-claude-code/scripts/check-public-hygiene.sh`
and its antigravity copy; `tests/repros/` for the gate's red/green.

### Patterns — two shipped

Add to the shipped pattern library (`template/rules/retrospect-patterns.md`, all ports; Cursor's at
`knowledge/rules/`), genericized, in the existing entry format:
- `contract-restated-anywhere-is-a-divergence-already-scheduled` — the same contract kept in several
  copies (prose, schema, implementation) drifts; keep one normative source and cite it.
- `re-run-pre-execution-checks-empirically-at-execution-start` — checks run at plan time go stale
  before execution; re-run them when execution starts (pairs with R6).

The report's other two (`command-invocation-assumed-not-verified`,
`open-sub-decisions-carried-into-execution`) are covered by R2 and R5 and are not added.

## Port propagation

| Port | `prospect` | `auto` | Mechanism |
|---|---|---|---|
| claude-code | yes | yes | canonical, by hand |
| openai-codex | yes | yes | by hand (root var `${ARIA_PLUGIN_ROOT}`) |
| antigravity | yes | yes | `build.sh` from canonical (+ overlays) |
| claude-cowork | yes | — | by hand; ships as Cowork 1.8.4 |
| cursor-template | in `aria-commands.mdc` | in `.mdc` | `port-skills-to-mdc.py` — never hand-edit generated `.mdc` |

Runtimes that cannot spawn a subagent print `Cold read: not run — this runtime cannot start a
subagent`; whether each port's runtime can is measured during the plan, not assumed. `PORT-LEDGER.json`
re-baselined per port only after that port is verified — never `check-port-drift.sh --update all`.

## Acceptance criteria

Each names the check that can fail it.

- **AC1 (hygiene class closed).** The new gate arm FAILS on a fixture under `plugin-*/` holding a
  `feedback_x` token and PASSES on the cleaned tree; seen red before the cleanup on the real tree.
  `/usr/bin/grep -rlE 'feedback_[a-z0-9_]+' plugin-*` returns nothing (exit 1, with the gate's own
  positive control proving the pattern fires).
- **AC2 (surface present in every port).** A repro asserts, per port carrying the skill: `--cold` and
  `--summary` in `prospect`'s argument-hint; a Step 3.6 heading; §4.6 question 4; `cold` and `cold=<N>`
  in `auto`'s argument-hint. Seen red on the pre-change tree.
- **AC3 (one template).** The cold-read prompt template is byte-identical across ports (repro extracts
  and compares; a one-character mutation in one port reddens it).
- **AC4 (generated ports regenerated).** `port-skills-to-mdc.py` and `build.sh` re-run with zero diff
  afterwards.
- **AC5 (patterns).** Both pattern entries exist in every port's template, in the entry format
  (Tier / First identified / summary / Detection cues / Why / Counter-discipline).
- **AC6 (gates).** Full plugin suite, hygiene gate (incl. the private list and every commit message),
  port-drift check: bare exit 0.
- **AC7 (reviewer identity).** Step 3.6's text names the Claude Code subagent type (Plan) with its host
  version stamp, and the Cold read block's fields include the subagent type and the `git status`
  before/after result; a repro asserts both in every port carrying the step.
- **Port Task 0 (measure first).** Before any port's text is written, read each runtime's current docs
  (Codex, Cowork, Antigravity) for whether it can start a subagent and what that subagent loads; record
  the answer with the runtime version. Unknown **capability** ⇒ that port prints the not-run line; known
  capability with unknown **startup context** ⇒ it runs and the report says the reader's startup context
  is unrecorded. **Done 2026-11-14:** Codex — `spawn_agent`; every agent loads `AGENTS.md` from the
  project root down to the working directory (openai/codex docs, `main`, read 2026-11-14) ⇒ runs, reader
  not instruction-free. Antigravity — `invoke_subagent` / `define_subagent` (repo `PORTING.md`, from its
  hooks docs, date unrecorded) ⇒ runs, startup context unrecorded; its `prospect` is generated from
  canonical with no overlay, so canonical's text must be runtime-conditional. Cowork — "no parallel
  subagents" (its own `foundational-review` skill) ⇒ not-run line. Cursor — no subagent surface in the
  port ⇒ not-run line.

**Success signal — live, owed after release (cannot be shown by a repro):**
- L1: `/prospect file <a real plan> --cold` dispatches a subagent whose prompt is only the template
  (read from the transcript), returns ranked findings, and each is marked confirmed/refuted.
- L2: `/auto plan <goal> cold=2` stops after the first BLOCKER-free round, or at 2 rounds, and says
  which.
- L3: a runtime without subagents prints the not-run line rather than skipping silently.

The report's author offered the plan and spec their run produced as worked examples; those are the
intended L1 input.

## Out of scope

R8 (typed discovery stage), marking every claim's origin (R9's other half), any change to the D7 ledger,
§4.6 questions 1–3, or the report's ten-section shape.
