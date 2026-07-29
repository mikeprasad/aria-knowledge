# `/auto` modifiers + standing directives — design

**Date:** 2026-07-30
**Skill:** `plugin-claude-code/skills/auto/SKILL.md` (Claude-Code-canonical; no ports)
**Target version:** 2.42.0 → 2.43.0 (minor — new capability surface every user inherits)

## Problem

`/auto` shipped in v2.37.0 with three modes (`arc`/`execute`/`config`) and two toggles
(`continue|stop`, `self-restart`). Real use shows the invocation surface is wrong in two
distinct ways.

**Evidence — 75 distinct `/auto` invocations mined from 328 local session transcripts
(2026-06-29 → 2026-07-29).** The same clauses are retyped nearly every run:

| Retyped clause | Count | Already the skill's behavior? |
|---|---|---|
| "local only" / "commit local only" / "do not push" | ~20 | Yes — it is the default |
| "use MCP / plugins as needed", "full mcp use approved" | ~8 | Yes — Pre-answered §Tool approvals |
| "set a croncreate for \<time\> to continue" | ~10 | Yes — Step 6 |
| "spec prospect plan prospect execute retrospect" (longhand) | ~6 | Yes — arc mode |
| "foundational fixes always" / "long term architecture" | ~5 | No — not stated in the skill |
| "do all" / "everything possible" / "until you can't" | ~15 | Yes — `continue` |
| "I'll be sleeping" / "run continuous" / "afk" / overnight | ~6 | Partly — needs 3 knobs set together |
| "update tickets when you commit" | ~5 | Partly — Pre-answered says *file*, not *update* |
| "do not start the prompt with a /" | 2 | **Yes — shipped v2.37.3 and still failed twice** |

Two failure classes:

1. **Invisible defaults.** A default the user cannot see is a default the user retypes.
   The fix is surfacing, not new behavior.
2. **Multi-knob intents with no name.** "Run this overnight" requires setting three
   knobs (`continue` + `self-restart` + cron) that have no collective name, so it is
   spelled out prose-style every time and set inconsistently.

A third, sharper failure: **the no-slash cron rule was already documented and still
broke twice.** It lives mid-paragraph in Step 6, a step that only executes on unattended
runs. Prose in a rarely-read step is not enforcement.

## Design

Two mechanisms for two problems.

- **Standing directives** — always on, never typed. A new block above Step 0.
- **Modifiers** — one word that pre-sets several existing run knobs.

### Standing directives (new block, above Step 0)

| ID | Directive |
|---|---|
| **D1** | **Usage: the 5-hour figure binds; the 7-day figure is ignored.** When a statusline is visible, gate only on 5h. The 7d number is never a reason to slow, shrink, defer, or stop. **90% 5h → arm/re-arm the resume cron** (existing Step 6 threshold). **95% 5h → pause**: checkpoint, commit, then wait for reset if a cron is armed, else `/handoff`. When no statusline is visible (desktop runtime), do not infer a number and do not gate on one — ask. |
| **D2** | **A scheduled prompt never starts with `/`** — mechanism-agnostic: `CronCreate`, `create_scheduled_task`, or any future scheduler. Hoisted out of Step 6. Enforced by a **hook**, not prose (see Deliverable B) — the prose form shipped in v2.37.3 and failed twice afterward. The prompt must instruct the *next* scheduled run to also start prose-first. |
| **D3** | **Foundational is always the answer** — *"unless it would impact the `/auto` arc itself."* Never take the patching branch to protect schedule. Every firing of the carve-out is a D7 ledger entry. |
| **D4** | **Local-only, and push is never grantable.** Stated in the arc contract every run. **No modifier — including `full` — can pre-authorize a push.** Push remains a legitimate stop in every mode. |
| **D5** | **Report the live model name at every checkpoint**, so a silent model swap is visible. |
| **D6** | **A non-blocking stop never idles the run.** Note it, keep working, surface at handoff. |
| **D7** | **The judgment ledger** — see below. |

D1's "if visible" qualifier is load-bearing: under the desktop runtime the usage
percentage is unreliable, so the correct behavior is to ask rather than infer.

### D7 — the judgment ledger

**Rule.** Any decision that could not be *objectively and deterministically validated,
traced, and confirmed after* is logged, presented at arc close, and reviewed by the user.

**The four-part test.** A decision is *deterministically validated* only if all four hold:

1. **Validated** — checked against ground truth (live code, real data, an actual run), not asserted.
2. **Deterministic** — same inputs produce the same verdict for anyone re-running it.
3. **Traced** — the check is nameable and re-runnable (a command, a `file:symbol`, a test).
4. **Confirmed after** — what was predicted actually held once built.

All four hold → it is an ordinary `[DECISION]` line, not a ledger entry.
**Any one fails → ledger entry.**

**Relationship to the existing `[DECISION]` trail.** The ledger is a *filter over* the
`[DECISION]` trail, not a parallel system. Arc mode already emits `[DECISION]` lines for
every autonomous design decision (Step 1.2); D7 promotes the non-deterministic subset
into a reviewable artifact. Compose, do not duplicate.

**Location.** `<knowledge_folder>/logs/auto/<YYYY-MM-DD>-<slug>-judgments.md`, a sibling
of the existing `logs/prospect/` and `logs/retrospect/` trees. `knowledge_folder` resolves
from `~/.claude/aria-knowledge.local.md` — **never a literal `~/knowledge/`** (the v2.40.2
phantom-path defect). On-disk, not in-context, because a `full loop` run crosses context
walls, cron re-entries, and fresh processes.

**Entry schema.**

```markdown
### J<N> — <one-line statement of the decision>
- **Chose:** <what was done>
- **Alternative not taken:** <what was rejected>
- **Why not deterministic:** <which of the 4 tests failed, and how>
- **Would be falsified by:** <the concrete check that would prove it wrong>
- **Blast radius / reversal:** <files · commit sha · how to undo>
- **Type:** judgment | D3-carve-out
- **Disposition:** pending → accepted | revisit | reverted
```

**Close protocol (amends Step 8).**

1. The ledger is the **first** item in the close report, ahead of the landed-work summary.
2. Every entry is listed with its disposition pending.
3. The user is **explicitly prompted** to review: accept / revisit / revert, per entry.
4. Dispositions are written back into the ledger file.
5. If the arc ends via a context wall, cron handoff, or self-restart rather than a clean
   close, the ledger path is carried in the `/handoff` opener **and** `SESSION.md`, so the
   resuming session surfaces it before doing new work.
6. **An empty ledger is stated, not omitted:** "0 judgment calls — every decision was
   deterministically validated." Silence and zero must be distinguishable.

**Scope — deliberately widened, flag for correction.** The user scoped D7 to `full`.
It ships **always-on across all modes** because D3 is itself always-on: a ledger that
exists only under `full` cannot receive D3 carve-out entries from a `loop` or `execute`
run, silently losing the trail on exactly the unattended runs that most need it. The
widening costs nothing when there is nothing to log (see point 6). Pull back to
`full`-only if unwanted.

### Modes (mutually exclusive, first arg)

| Mode | Status | Behavior |
|---|---|---|
| `arc` | **now an explicit keyword** | The default. Today `/auto arc fix X` mis-parses "arc fix X" as the goal; accepting `arc` as a mode keyword fixes that. |
| `execute <plan\|spec\|linear-id>` | unchanged | Plan exists — skip ideation. |
| `plan [goal]` | **new** | brainstorm → spec → /prospect → plan → /prospect, then **stop at a prospected cold-executable plan. No code.** The mirror of `execute`. |
| `config` / `preflight` | unchanged | Guided per-run knob picker. |

`plan` is not a new capability — it is a name for a shape already run repeatedly
(2026-07-18: *"write a full plan for everything possible for an opus session to execute
then prospect it"*; 2026-07-01: *"for any you cannot execute on your own do a full spec
plan prospect"*).

### Modifiers (stackable, any position)

| Modifier | Sets | Retires the phrase |
|---|---|---|
| **`full`** | Maximum authority on every axis **except push**: tools/MCP/plugins pre-approved · Workflow fan-out ON (default is hard-OFF) · cumulative subagent cap 10 → 30 · fan-out budget-fraction gate 25% → 40% · resume cron armed automatically when usage-bound · self-decide every objectively-validatable fork | "full mcp use approved", "make your own decisions objectively" |
| **`loop`** | Unattended preset: `continue` + `self-restart` + cron armed at 90% + non-blocking stops never idle + checkpoint-commit each milestone | "I'll be sleeping", "run continuous", "afk", "until you can't do anything else" |
| **`tickets`** | Tracker-bound (whatever tracker the user has connected — see below): work selection from the tracker by priority · comment on the ticket at every commit · no ticket claim without verified validation | "update tickets when you commit", "review the tracker for anything you can fix" |

**`full` is defined by its boundary:** every grant except the one that leaves the machine.
That makes the modifier memorable and makes D4 unambiguous.

**Authority is orthogonal to duration.** `full` sets *how much latitude*; `loop` /
`continue` / `stop` set *how long*. Keeping them separate makes all four combinations
expressible — `/auto full` (max authority, scoped) and `/auto full loop` (max authority,
overnight) are both real shapes from the corpus.

**`full` raises the three fan-out stopgaps; it does not remove them.** An unattended
max-authority run is the case most exposed to unbounded spend, and the budget-fraction
gate is what protects D1's 95% pause. Raised, finite, still live.

**Rejected: a `wide` modifier** (fan-out grant without `full`'s other grants). A strict
subset of `full` with one supporting instance in the corpus; cut for Rule 13.

**Rejected: a `ship` modifier** (push pre-authorized for the arc). Push stays a
per-instance ask in every mode — D4.

### `tickets` must be tracker-agnostic — and `/auto` currently is not

This plugin ships publicly. `tickets` therefore resolves **whatever tracker the installing
user has configured**, never a hardcoded vendor. Three existing plugin conventions supply
the whole mechanism — none of it is new machinery:

1. **Category probe.** Probe at runtime for a connected project-tracker MCP and adapt,
   mirroring `/digest` §3c. Known members: Linear · Asana · Atlassian/Jira · Monday ·
   ClickUp · Notion-as-tracker · GitHub Issues. **Prose-only, no helper API** — ADR-015
   verified no `probe_mcps()` helper exists in any shipped plugin and rejected building one.
   **Spelling:** the plugin is internally inconsistent — `~~project tracker` (spaced, 4
   occurrences, in prose) vs `~~project-tracker` (hyphenated, 2, in frontmatter). **Mirror
   that split exactly; do not normalize it** — normalizing is a separate change.
2. **`ticketing_plugins` config key.** *(Corrected post-prospect.)* It is **not** parsed by
   `bin/config.sh` — verified 0 matches. It is declared by `/setup` and read **directly from
   `~/.claude/aria-knowledge.local.md`** by `/audit-knowledge` (SKILL.md:171), format
   `tag:plugin-command` pairs. `/auto` reads it the same way. When set, it wins over the bare
   category probe — it is the user's explicit declaration.
   **Inherit `/audit-knowledge`:173's "No installed-plugin probe" rule verbatim:** never
   verify the mapped command is actually installed. Enumerating installed plugins from
   inside a skill couples ARIA to Claude Code internals that could change; a loud failure at
   invocation is preferred over a silently-absent hint.
3. **Tracker-agnostic ticket-ID regex.** Reuse `/retrospect` Step 2's `\b([A-Z]{2,}-\d+)\b`
   as-is. It already matches `DEV-123`, `PROJ-45`, `JIRA-9` — no vendor assumption.

**Degradation.** No tracker connected and no `ticketing_plugins` mapping → say so once,
then fall back to the standard Step 4 work-selection order (SESSION.md → plan/spec →
PROGRESS NEXT → TODO/ROADMAP/backlog). `tickets` never hard-fails an arc.

**In-scope defect — `/auto` hardcodes Linear at 7 sites.** Introducing a generic `tickets`
modifier beside vendor-locked prose would leave the class open (Rule 38). All seven are
genericized in this change:

| Line | Site | Fix |
|---|---|---|
| 2 | frontmatter `description` — `<plan\|spec\|linear-id>` | `<plan\|spec\|ticket-id>` |
| 3 | `argument-hint` — `linear-id` | `ticket-id` |
| 52 | mode table, `execute` row | `ticket-id` |
| 75 | Step 0¾ knob 1 — "a Linear ID" | "a ticket ID from your connected tracker" |
| 102 | Step 0.5 contract — "Linear ticket filing" | "ticket filing" |
| 120 | Pre-answered — "**Linear tickets** — create freely…" | "**Tickets** — create freely in the connected tracker…" |
| 128, 144 | `execute` source resolution — "needs Linear MCP" | "needs a connected `~~project-tracker` MCP" |

Sites 2 and 3 are the load-bearing ones: they are frontmatter, loaded into **every user's
session** whether or not they ever invoke `/auto`.

**Out of scope, flagged.** `/prospect` and `/retrospect` carry the same vendor-lock
(`--linear-post` flag, `/prospect linear <id>` scope, "Linear MCP" prose). That is a
separate class touching two skills' frontmatter and their backward-compat flag contracts;
it needs its own change so this one stays reviewable. Recorded here so it is not lost.

### Parsing

Extends the existing Step 0 grammar; no new machinery.

- **First arg** case-insensitively matching `arc` | `execute` | `plan` | `config` | `preflight` → the mode. Otherwise the mode is `arc` and the arg begins the goal.
- **Any position**, case-insensitive: `full`, `loop`, `tickets` → modifiers (set-valued, stackable).
- **Trailing**: `continue` | `stop` → on-queue-complete toggle; `self-restart` → context-restart flag.
- Everything else is the goal.

`loop` implies `continue` + `self-restart`; an explicit trailing `stop` after `loop` is
contradictory — resolve to the explicit token and say so in the arc contract.

Worked example: `/auto full loop tickets clear the payments queue` → mode `arc`,
modifiers `{full, loop, tickets}`, goal "clear the payments queue".

### Arc contract (Step 0.5) additions

The contract already exists; it gains lines so the retyped clauses become visible:

```
**Modifiers:** full · loop · tickets   (or: none — defaults)
**Push:** local commits only — push is never pre-authorized (D4)
**Tools:** MCP / plugins / skills pre-approved
**Usage:** gating on 5h only; 7d ignored · cron at 90% · pause at 95% (D1)
**Foundational:** always preferred; any carve-out is logged (D3 → D7)
**Judgment ledger:** <path> — presented for your review at close (D7)
**Model:** <live model name> — re-reported at each checkpoint (D5)
```

### Step 6 rewrite — scheduling gated on availability; `CronCreate` stays the default

*(Added post-prospect, then corrected. Step 6 today instructs `durable: true`, which the live
tool schema documents as a **no-op**: "durable persistence is not available. All jobs are
session-only." Removing that dead parameter and naming the real alternatives is the fix —
**not** changing the default mechanism.)*

**Mechanisms are gated on AVAILABILITY first, capability second.** An earlier draft of this
spec ranked them by capability and promoted `create_scheduled_task` to the default. That was
**falsified**: it is a Claude Desktop surface, not a universal one. Three independent
signals — `config.sh:18` already classifies the runtime as `{cli, desktop, desktop-unknown}`;
the plugin's own durable scheduler `pm-morning-run.sh:10` uses **launchd + `command -v
claude`** rather than scheduled tasks; and the plugin contains **zero** references to the
scheduled-tasks surface anywhere. Its own docs say "runs while **this app** is open" and
"runs on **next launch**" — app-lifecycle language. In a public plugin, defaulting CLI users
to a mechanism that silently is not there would dead-end `/auto`'s resume chain.

**`CronCreate` is the baseline and stays the default.** It is the only mechanism present in
every runtime, and its session-only nature is an accepted constraint, not a defect — an
unattended `/auto` run keeps its session open by design.

| Mechanism | Available | Survives session death | Fresh context | Use for |
|---|---|---|---|---|
| **`CronCreate`** — the default | **Always, every runtime** | No — session-only, in-memory; recurring auto-expires at 7 days; fires only while the REPL is idle | No — re-enters this session | Usage-bound resume with the session left open. The normal unattended run. |
| **`create_scheduled_task`** | **Desktop runtime only** — probe, never assume | Yes — stored on disk; runs at next app launch if missed | Yes | A resume that must survive the session ending, when the runtime offers it |
| **launchd** (the `pm-schedule.sh` pattern) | macOS only; user opts in | Yes — OS-level | Yes — a fresh `claude` invocation | Truly session-independent recurring work on the CLI |
| **`bin/auto-runloop.sh`** (`self-restart`) | Wrapper must already be running | Wrapper-dependent | Yes — fresh `claude -p` | A context wall mid-arc |

**Selection rule.** Default to `CronCreate`. Reach past it only when the resume genuinely
must survive the session ending — and then **probe what this runtime actually offers** (per
ADR-015, prose-only) rather than naming a mechanism the user may not have. State which one
was chosen and why. Never promise durability the runtime cannot deliver.

**Do not pass `durable: true`** to `CronCreate` — the tool documents it as having no effect.

**D2 applies to every tier.** A stored task prompt has not been proven safe against a leading
`/`, and prose-first costs nothing — so the rule and its hook cover both scheduling verbs.

## Deliverable B — the D2 guard (mechanical)

Prose failed twice after shipping. This escalates the enforcement tier.

- **B1** — `bin/pre-cron-check.sh`: a `PreToolUse` hook that reads `tool_input.prompt` and
  hard-denies a `/`-leading value. Feasibility is verified, not assumed: `plugin.json`
  already registers `PreToolUse` with `matcher: "Bash"`, so arbitrary tool names are
  matchable; the deny idiom exists verbatim at `pre-edit-check.sh:362`; and the live
  `CronCreate` schema confirms a required `prompt` string field.
- **B2** — register in `.claude-plugin/plugin.json` under `hooks.PreToolUse`, matcher
  `CronCreate|mcp__scheduled-tasks__create_scheduled_task` (additive — a 4th entry).
- **B3** — a repro that **observes the guard go RED** on a `/`-leading prompt. A guard never
  seen to fail is not a guard.

## Deliverable C — recurring-lapse guards

Two failure modes reported as recurring (predominantly on Opus 5). Same pattern as D2: a
correct rule that prose does not hold.

- **C1 — hook-bypass via shell writes.** Structural edits performed with `python write_text`,
  `sed -i`, `tee`, or a heredoc redirect route *around* the `Edit|Write` `PreToolUse` gate,
  defeating Rule 22 enforcement by construction. Extend the existing Bash `PreToolUse` hook
  to detect a **narrow, high-confidence** idiom set targeting tracked source files.
  **Ships as `additionalContext` (warn), not deny, until the false-positive rate is
  measured** — over-denying would block legitimate shell work in every session, which is
  worse than the disease. The ~328 local session transcripts are a ready measurement corpus;
  run it during implementation and report the count.
- **C2 — assertions that cannot fail.** A tautological assertion (`x == x`, `assert True`,
  `expect(x).toBe(x)`) is a false green — the exact class Rule 36 exists to prevent. Detect
  the **syntactic subset only**, on `PostToolUse` over `Edit|Write` to test-shaped paths,
  **warn-only**. The hook message must state what it cannot detect (semantic tautologies are
  out of reach for any static rule) — otherwise a clean run reads as "no tautologies present"
  and the guard becomes its own false green.

**These three deliverables commit separately.** Bundling makes the riskiest piece (C) gate
the safest (A) and turns a revert into all-or-nothing.

## Constraints

**Gate B — skill-discovery budget.** Measured live this session: **18,938 / 18,944 bytes —
6 bytes of headroom.** `/auto` owns the largest description in the plugin (**1,232 B**,
measured — an earlier 1,214 estimate was wrong). Two trimmable blocks inside it:
**185 B** of near-synonym triggers ("combined go" / "just build it" / "take this and run" /
"run the whole chain" / "do as much as you can autonomously") and **356 B** restating the
mode table the body already documents. New vocabulary needs ~150 B.
**The change is net-POSITIVE — it frees budget rather than consuming it.** No raise, no
other skill touched. Verify with `./release.sh` Gate B before commit.

**`argument-hint` is free.** Gate B's awk captures the `description:` block only and stops
at the next top-level key — verified by running it. So the `linear-id` → `ticket-id` fix in
`argument-hint` costs zero bytes.

**Ports: none.** `/auto` is Claude-Code-canonical only. Cowork's 9,000-char summed
description cap was already exceeded before `/auto` existed; codex / cursor / antigravity
are tracked-drift. The hooks in Deliverables B and C are Bash + Claude-Code-only by nature,
matching. **Files touched:** `skills/auto/SKILL.md`, `.claude-plugin/plugin.json`,
two new `bin/*.sh`, one extended `bin/bash-cd-check.sh` sibling, and the repro suites.

**Tests.** Extend `tests/repros/auto-modes.sh` (**68 assertions — verified by running it,
not inherited from a doc**), and add one repro per new hook:

- Mode keywords `plan` and `arc` parse as modes, not as goal text.
- Each modifier (`full`, `loop`, `tickets`) parses in any position; stacking works.
- `loop` + explicit trailing `stop` resolves to the explicit token and says so.
- D1 thresholds present and distinct (90% arm ≠ 95% pause); 7d explicitly excluded.
- **D2 leading-slash assert goes RED on a `/`-leading cron prompt** — a guard that has
  never been seen to fail is not a guard (this rule shipped as prose in v2.37.3 and broke
  twice afterward, which is exactly the evidence that prose alone does not hold).
- D7: entry emitted when a decision fails any of the four tests; the empty-ledger
  statement emitted when none do; ledger path resolves from `knowledge_folder`, and a
  literal `~/knowledge/` **fails** the assertion.
- **Vendor-lock guard:** zero case-insensitive `linear` matches remain in
  `skills/auto/SKILL.md`. This assertion is what keeps the class closed against
  regression, not the one-time edit.

## Non-goals

- Persisting any modifier as a standing default. `/auto` never writes config; that is
  `/setup`'s sole job (one writer, no drift).
- Changing Rule 35. The decide-vs-ask logic stays in `working-rules.md`; this skill
  instantiates it.
- Porting to cowork / codex / cursor / antigravity.
- Any change to push authorization.
- **Declassing the Linear hardcoding in `/prospect` and `/retrospect`** (`--linear-post`,
  `/prospect linear <id>`, "Linear MCP" prose). Same defect class, but it touches two more
  frontmatter descriptions and a documented backward-compat flag contract. Separate change.
- Adding a tracker MCP, a `probe_mcps()` helper, or any new config key. `tickets` composes
  the `~~project-tracker` probe and the existing `ticketing_plugins` key as they are.
