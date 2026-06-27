---
description: "Kick off and drive an autonomous execution arc end-to-end: compose the gate chain (brainstorm→spec→/prospect→plan→/prospect→TDD→/retrospect) under the Rule 35 posture, decide validatable forks yourself, and stop only on a load-bearing fork or ungranted approval. Two modes: '/auto [goal] [continue|stop]' (full arc; 'continue' = keep finding new work after the queue for unattended/overnight runs, 'stop' = checkpoint + handoff, the default) '/auto execute <plan|spec|linear-id>' (plan exists — skip ideation), and '/auto config' (alias preflight; guided one-knob-at-a-time picker for this run — you set nothing from memory). An explicit grant of autonomous latitude that overrides the standing `autonomy` config for the arc (never writes it). Use when the user says 'combined go', 'continue autonomously', 'go with your recommendation', 'do as much as you can autonomously', 'run the whole chain', 'just build it', 'take this and run', 'run overnight', or hands off a goal/plan/ticket/SESSION.md with latitude to execute WITHOUT per-step approval. ENTRY POINT for a multi-step arc — NOT a single concrete change (just do that), and distinct from /prospect, /retrospect, /handoff, /wrapup. (Code port — ADR-094.)"
argument-hint: "[execute|config|preflight] [<goal | plan-path | linear-id>] [continue|stop]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, WebFetch, WebSearch
---

# /auto — Drive an autonomous execution arc

Drive a piece of work end-to-end under the autonomous decision-routing posture, stopping only where a human decision is genuinely load-bearing. This is the *entry point* that wires together the process skills you already have — `brainstorming`, `/prospect`, `superpowers:test-driven-development` / `superpowers:subagent-driven-development`, `/retrospect` — into one continuous arc, so a single invocation runs the whole chain instead of you re-approving each step.

It does NOT re-define the decide-vs-ask policy. That policy is **Rule 35** (decision routing) in `template/rules/working-rules.md`, scaled by the **`autonomy`** config posture. `/auto` *applies* Rule 35 to a concrete arc and adds the operational discipline an unattended run needs: what to *never* stop for, how to read the binding budget, how to pick the next unit of work, and how (optionally) to self-perpetuate across usage resets. Distilled from real autonomous runs — the friction points below are ones that actually bit.

## Runtime Gate (per ADR-094)

**Canonical resolution:** This is the Claude Code variant. When both `plugin-claude-code` and `plugin-claude-cowork` are loaded in the same session, bare `/auto` resolves to this skill — aria-knowledge (Code) is the canonical owner per ADR-094 §Part 1. The Cowork variant is namespaced-only: `/aria-cowork:auto`.

**Before Step 0:** Check that the `Bash` tool is available. If `Bash` is NOT available (you are in Claude Cowork or another non-Code runtime), surface this and wait for an explicit reply:

> ⚠️ **Runtime mismatch — you invoked aria-knowledge's `/auto` from a non-Code runtime.**
>
> This variant runs `git` status/commit, the autonomy-config probe, and (optionally) `CronCreate` via Bash, which isn't available here. The runtime-appropriate variant is `/aria-cowork:auto`.
>
> **Use `/aria-cowork:auto` instead?** (`y` / `n`)

- **`y` / `yes`** — Invoke `aria-cowork:auto` with the same arguments via the `Skill` tool; that variant takes over.
- **`n` / `no`** — Proceed with this variant anyway; subsequent Bash failures are expected.
- **No / other reply** — Treat as "do not proceed" and exit cleanly.

This gate is NOT suspended by any mode — `/auto` is inherently autonomous, so confirming the right runtime is the one precondition that still matters. If `Bash` is available, proceed to Step 0.

## When to use

- The user hands off a goal, plan, spec, ticket, or `SESSION.md`/handoff and signals latitude to run without per-step approval ("combined go", "continue autonomously", "go with your recommendation", "do as much as you can", "just build it", "take this and run", "run overnight"). A bare "go" alone is ambiguous — treat it as a `/auto` arc only when the surrounding context is clearly "drive this work autonomously," not when it's conversational ("go ahead and read that", "go with option B").
- After `brainstorming` or `/distill` concludes and the user says "ok, build it."
- At the start of a long or unattended arc the user wants driven to a durable checkpoint with minimal interruption.

**When NOT to use** (route to the right skill instead):
- One plan you want pressure-tested before any code → `/prospect`.
- Work that's already written/shipped and you want it validated → `/retrospect`.
- A session you're trying to pass off to the next session or a coworker → `/handoff`.
- A finished session with nothing pending → `/wrapup`.

`/auto` is the *driver*; those are the *gates and bookends* it calls. It doesn't replace them — it sequences them.

## Step 0: Parse mode, posture, and the queue-complete toggle

`/auto` is an **explicit, in-the-moment grant of autonomous latitude** — invoking it *means* "drive this autonomously, now." It overrides the standing `autonomy` config for the duration of the arc and never changes that config. Two modes plus a toggle:

| Mode | Trigger | What it does |
|---|---|---|
| **arc** (default) | `/auto` or `/auto <goal>` | Full chain: brainstorm → spec → /prospect → plan → /prospect → execute → /retrospect. The default when the first arg isn't a mode keyword. |
| **execute** | `/auto execute <plan-path \| linear-id \| "the plan">` | A plan/spec already exists. Skip ideation; run /prospect → build (TDD/SDD) → /retrospect. |
| **config** | `/auto config [<goal>]` (alias `/auto preflight`) | Guided pre-flight: walk every run setting one at a time as a picker (so nothing has to be remembered), assemble the run-config, then drive the arc with it. Configures THIS run only — never persists (that's `/setup`'s job). See Step 0¾. |

**On-queue-complete toggle** (a trailing `continue` or `stop` keyword, default **stop**): what to do once the *planned* queue is done.
- **`stop`** (default) — checkpoint + `/handoff` when the queue is clear; do NOT pick up new work. The right choice for a scoped "just do X" run. Default to this if unset — don't over-reach the remit.
- **`continue`** — keep finding the next valuable work autonomously (see Step 4); for unattended / overnight runs. Don't stop at the arc boundary.

**Context-self-restart flag** (a trailing `self-restart` keyword, default **off**): only meaningful with `continue`. When set, a context-window wall does NOT terminally stop the arc — instead the skill writes a restart-signal file that the external `bin/auto-runloop.sh` wrapper watches, so the arc resumes in a FRESH process (clean context). See Step 3¾. Requires the wrapper to be running and a permission allowlist (the wrapper spawns `claude -p --dangerously-skip-permissions`, which the auto-mode classifier blocks unless allowlisted). Without the flag, a context wall behaves exactly as today (terminal stop + `/handoff`).

**Parsing:** if the first arg case-insensitively matches `execute`, `config`, or `preflight`, that's the mode; a trailing `continue`/`stop` sets the toggle, and a trailing `self-restart` sets the context-self-restart flag (only honored alongside `continue`); everything else is the **goal** for the default `arc` mode (so `/auto ship the CSV exporter continue self-restart` parses cleanly). If the goal is "continue from SESSION.md / the latest handoff," resolve it in Step 4's work-selection order.

**Two ways to handle unspecified settings — you remember nothing either way:**
- **Default (`/auto [goal]`)** — pick the safe default for everything unspecified and **surface them all in the arc contract** (Step 0.5) before driving. You *react* to the shown list; you never have to *recall* what's configurable. Minimal friction.
- **Guided (`/auto config`)** — when you'd rather set the knobs deliberately, the walkthrough (Step 0¾) **presents each one as options, one at a time**, so the option list lives in the picker, not your memory. You opt into this per run.

**Relation to the `autonomy` config.** The standing `autonomy` config (`default`/`balanced`/`autonomous`, owned by `/setup`) sets how autonomous I am on sessions where you *didn't* invoke `/auto`. `/auto` is the in-the-moment override for *this* arc — it runs at full self-decide latitude regardless of the config value, including at `autonomy: default`. You never need to flip the config to use `/auto`; the invocation is the grant. Don't bother reading the config value — it can't change `/auto`'s behavior, and the arc contract (Step 0.5) already announces the autonomous posture, so a separate "your standing default is X" note would be redundant ceremony. `/auto` never writes the config either — changing the standing posture is `/setup`'s job, exclusively (one writer, no drift).

## Step 0¾: Guided config walkthrough (`config` mode only)

Runs ONLY when invoked as `/auto config` (or `/auto preflight`). Skip entirely for `arc`/`execute`. Purpose: let the user set each run setting deliberately **without having to remember any of them** — present each as a picker, one at a time, with the safe default pre-marked. Use the platform's question/picker affordance (one question per knob); accept a bare-number/keyword reply; "skip" on any knob takes its default.

Walk these in order, **one at a time** (do not dump all six at once — the point is recognition-not-recall, one decision per step):

1. **Goal / source** — this prompt's goal · continue from `SESSION.md`/latest handoff · a plan path · a Linear ID. (If a goal was passed as `/auto config <goal>`, pre-seed it and confirm.)
2. **On-queue-complete** — `stop` (scoped: checkpoint + /handoff when the queue's clear — *default*) · `continue` (keep finding new work; for unattended/overnight).
3. **Push policy** — commit local, no push (*default*) · commit + push per host convention. (Push remains an ungranted-approval stop regardless — this only sets the intent.)
4. **Fan-out / subagents** — inline-only · bounded individual subagents, ~10 cumulative cap (*default*) · raise the cap to N · allow the Workflow swarm (multi-agent orchestration). (Maps to the Step 5 stopgaps.)
5. **Budget ceiling** — default 25%-of-remaining-window per fan-out burst (*default*) · a different fraction · a hard "stop the arc at X% usage." (Maps to the Step 5 budget-fraction gate + a live abort floor.)
6. **Cron / unattended** — off (*default*) · arm a resume cron for a usage-bound self-perpetuating run (fires **+5 min after** each 5-hour reset per Step 6). (Only offered/meaningful when #2 = `continue`.)

After the walkthrough, assemble the picks into the run-config and proceed to Step 0.5 — the **arc contract is then a confirmation of what you just chose**, not a fresh set of defaults. **Nothing persists**: these picks configure THIS arc only; the standing `autonomy` posture and any saved defaults are untouched (changing standing defaults is `/setup`'s job — `/auto` never writes config, in any mode).

## Step 0.5: State the contract before driving

Before the first action, post a short **arc contract** so the autonomy is legible — the user should never be surprised by what you decided alone vs. what you'll stop for:

> **Arc:** <one-line goal> · **Mode:** <arc | execute> · **On-complete:** <continue | stop>
> **I'll decide myself:** objectively-validatable forks (checked against real code/corpus/docs, held to Rules 13/14/18 — simplest/robust/clean, no unneeded abstraction).
> **I'll handle without stopping:** knowledge placement, tool/permission approvals, backlog/deferral, Linear ticket filing, the normal commit cadence (see Pre-answered below).
> **I'll stop and ask on:** product/UX taste with no objective answer · an irreversible/outward-facing action not covered by policy *that blocks the task* · a true no-visibility fact only you have · a genuine costly fork empirical investigation can't decide.
> **Gates that run but don't count as stopping:** /prospect (pre-code), /retrospect (post-build).
> **Push policy:** <commit local, no push | commit + push per host convention>.

This contract is the operative form of Rule 35's routing table for *this* arc. You don't re-derive the table — you instantiate it.

## Verify before you trust (the #1 rule — most friction traces here)

Before acting on **any** assertion — a resume prompt, a handoff, a stale doc, your own memory, a cached metric, a `SESSION.md` "next" line — **verify it empirically against the live source.** Run `git log`/`git status`, read the live state file, grep the real code. A resume prompt may be stale (the work is already shipped — don't redo it); a cached usage % may be stale (window reset → trust the reset *timestamp* vs now, not the number). For backend behavior, API contracts, or field shapes, read the source-of-truth repos FIRST (backend + the shipped client) — never assume, and don't file a "backend gap" until the repos genuinely don't answer it. This is the discipline that earns the right to self-decide: "validated" means checked against ground truth, not asserted.

## Pre-answered — handle and keep going (do NOT stop for these)

Rule 35 says route by question type; these are the recurring autonomous-run cases pre-routed to **act**, so an unattended arc doesn't stall on them:

- **Knowledge placement** — never pause to ask *where* something goes. Make it durable in the best location you can judge (memory · /prospect+/retrospect log · contract doc · CLAUDE.md + PROGRESS). Unsure → drop it to the general intake backlog for a future audit to sort. Placement is never a stop.
- **Tool / MCP / permission approvals** — assume the build/test/lint, sim, git, Cron, MCP, and skill verbs are pre-approved (a companion allowlist in the user's `.claude/settings.local.json` makes this real at the harness level — see Notes). If one tool is genuinely blocked, route to the working alternative and note it. Only OS-level GUI popups need a live human — flag once and route around.
- **Backlog / deferral** — a known follow-on (out-of-scope feature, separate-team backend change, device-gated smoke) → file/note it and DEFER. Don't stop to ask whether to defer.
- **Linear tickets** — create freely: status backlog/Undefined, assigned to the user for post-session review, both intakes present (Technical Intake marked DRAFT), enriched via comments. Never stop to ask whether/how to file.
- **Known-pattern git/scope** — stage named in-scope files, commit, push (per the contract's push policy). Don't ask permission for the normal commit cadence.
- **Self-recommended chain choices** — a spec/prospect/plan fork a recommendation already answers → take the recommendation. "Self-recommended + answerable" is not a stop.

## Step 1: Drive the arc

Run the chain by **invoking the real skills** via the `Skill` tool, not by summarizing them. Composition keeps the gates honest: the quality checks are the actual checks, and improvements to those skills flow through automatically.

**Degrade gracefully when a composed skill or tool is absent.** `brainstorming`, `writing-plans`, `test-driven-development`, and `subagent-driven-development` are Superpowers skills (strongly recommended, optional). If one isn't installed, name what's missing, fall back to doing that phase inline (a plain brainstorm, a hand-written plan, manual red-green-refactor), and say the gate ran in degraded form. The `execute <linear-id>` path needs Linear MCP — if unavailable, ask the user to paste the ticket rather than proceed on a missing plan.

### arc mode — full chain

1. **Brainstorm** (`superpowers:brainstorming`) — only if the *shape* of the solution is a real open question. A concrete plan or tightly-scoped goal skips straight to spec (Rule 35: don't deliberate what's already answered).
2. **Spec** (`superpowers:writing-plans` or `/distill`) — surface every autonomous design decision as an explicit `[DECISION]` line so the next gate can ratify it; that's how self-approval stays auditable.
3. **/prospect** the spec/plan. Apply PROCEED-WITH-CHANGES amendments **in place, now**. A KILL/DEFER verdict on a load-bearing step *is* a stop — surface it.
4. **Plan** — if the spec isn't already a cold-executable plan, write one.
5. **/prospect** the plan only if it materially differs from the spec you already pre-mortemed (re-prospecting an unchanged artifact is ceremony, not a check).
6. **Execute** (`superpowers:test-driven-development`, or `subagent-driven-development` for independent multi-task plans). Per-edit Rule 22 still fires — that's the execution-time scope check, separate from the plan-level gates.
7. **/retrospect** the shipped range. Fix what it surfaces if objectively-validatable; surface what it can't resolve.

**Mechanical / contract-driven change** (no design judgment) → skip brainstorm/spec and just build it — still test + gate.

### execute mode — plan exists

Skip steps 1–2. Resolve the plan source (path → `Read`; Linear ID → MCP fetch if available; quoted string → treat as the plan), then run 3 → 6 → 7.

### Verification reality — verify for real, classify honestly

Use the project's **real working verification path** (e.g. RenderPreview for SwiftUI; a live round-trip vs staging where reachable; the actual app, not just unit tests) to confirm the build does what it should. Be HONEST about what's device-/GUI-gated vs headlessly verifiable — **classify it, never fake or silently skip.** Unit-tested + render-verified with only an OS-delivery slice left unobserved is a *documented residual*, not a pass to claim and not a failure to hide. A live end-to-end check is the only thing that proves model == backend; fixtures only prove fixture == model.

### Commit discipline (per task)

Each task = **one atomic commit**. Gate BEFORE committing: run the FULL suite + build + lint as the **bare exit code**, READ green, THEN commit — never chain `&& commit` after a non-test command (a `| grep`/typecheck between the suite and the commit swallows the test exit and commits red). Run ALL relevant gates; they cover disjoint surfaces (app build ≠ test-target compile). Commit only in-scope **named** files (`git add <paths>`, never `-A`); verify `git status` first (parallel sessions may have dirtied the tree). Push only per the contract's push policy; **never force-push**, and verify the ahead-count returns to 0 after pushing.

**Throughout:** apply Rule 35 at every fork — investigate the resolvable parts first, then surface only the residual that's genuinely about the user. When you surface one, present concrete options + a recommendation (label A/B for a terse reply), then continue from the pick without restarting the chain.

## Step 2: The stop-rule and checkpoints

**Run to a durable checkpoint, not to exhaustion.** A durable checkpoint is committed/persisted work that survives a fresh session — not a mid-edit pause. You don't need permission to *continue past* a checkpoint under an autonomous grant; you report at it.

**Legitimate stops — the ONLY reasons to ask** (everything else has a pre-answered default above):
- **Product / UX taste with no objective answer** (e.g. "should threads nest or flatten?") — design direction is the user's.
- **An action needing approval not already granted** — an irreversible or outward-facing op not covered by policy (a **push** beyond the contract's push policy, a **prod deploy**, external comms, a **destructive op** / deleting non-recoverable data, a **shared-DB migration**), a **scope change** beyond the stated goal, or **credentials / prod-data access**. BUT only HALT if it *blocks* the current task — if it's non-blocking, NOTE it and CONTINUE other work; never idle the whole run on a side-question. (Surface all noted items at `/handoff`.)
- **A true no-visibility fact only the user has** (a constraint not in any repo/doc; a teammate conversation).
- **A genuine fork where both branches are plausible AND the wrong one is costly AND empirical investigation can't decide it.**

A safety-classifier block is never routed around — pivot to a safe local path and report.

## Step 3: Budget — check the LIVE statusline between every task

Know **which budget binds**, because it decides the right resume tool:
- **Context** → at 90%, AUTO-run `/extract` (no judgment — its dedup handles "nothing new"), then keep going. Context-bound work CAN'T be saved by a cron (a cron re-enters the same full session) → `/handoff` to a durable on-disk opener for a fresh session.
- **5-hour / 7-day usage** → keep working toward the limit. Usage-bound work CAN be continued by a session-only cron at the reset boundary (it re-fires *this* session with local work intact).
- Don't gate, defer, or shrink an action on a number you haven't re-read **live this turn** — read the statusline state file, not a stale hook-alert figure (a window may have reset). If you're not gating on budget, don't mention it.

## Step 3¾ (optional): Context-self-restart across a fresh process

Default OFF. Active **only** when this is a `continue` run **AND** the `self-restart` flag was set. Without both, a context wall behaves exactly as the Step 3 Context bullet describes (extract → `/handoff` → terminal stop) — unchanged.

The problem this solves: an unattended `continue` arc that hits the context wall would otherwise halt until a human restarts it. A cron can't fix this (a cron re-enters the *same* full session). The skill itself **cannot** reset its own context either — `/clear` is a REPL built-in that **neither a skill nor a hook can issue** (both verified). The only autonomous path to clean context is a **fresh `claude` process**, which an external wrapper provides.

So when active, at 90% context — instead of terminally stopping — do this and then **stop cleanly**. The skill never issues `/clear` (it cannot — and even if it could, the wrapper's fresh process is the cleaner reset); you do NOT self-resume; you hand the restart to the wrapper:

1. **AUTO-run `/extract`** (same as the default Context path).
2. **Run `/handoff`** to produce a full, self-sufficient, **prose-first** next-session opener at `SESSION.md`. Prose-first is mandatory — the opener must NOT start with a slash command (a leading `/auto` is parsed as an unknown command and the whole mandate is silently discarded); `/handoff`'s opener already leads with prose.
3. **Write the restart-signal file** `<cwd>/.claude/auto-restart-requested` containing **one line: the absolute path to that opener**. Presence of the file = "restart requested"; its content = the opener the wrapper relaunches with. (Mark the write site `[SELFRESTART-PRE]` so a later `/retrospect` can confirm it fired.)
4. **Stop cleanly.** The arc is now a durable on-disk checkpoint; the in-process work is done.

`bin/auto-runloop.sh` (shipped with the plugin) is the external piece: it launched this run, watches for the signal file on exit, consumes it (so a crash can't loop forever), and relaunches a **fresh** `claude -p` headless process with the opener. **The wrapper must already be running** for this to do anything — if `/auto` was invoked directly in an interactive REPL (no wrapper), `self-restart` still writes the signal and stops, but nothing restarts it; note that in the handoff. **Permission caveat:** the wrapper spawns `claude -p --dangerously-skip-permissions`, which the auto-mode classifier blocks unless the user has added a Bash permission allowlist rule for it — surface this when recommending an unattended run.

## Step 4: Work selection (and the On-queue-complete toggle)

**Always validate before executing** (hard gate, every queued item): re-validate the plan + the live state + staleness before starting. `git log` to confirm the item is still un-done (don't redo shipped work); re-read the spec against current code; re-/prospect if the plan is old or the code moved under it. Only execute once validated current.

**Work the existing queue in its intended order:** `SESSION.md` "Next session prompt" / handoff opener → the project's prospected plan/spec → PROGRESS "NEXT" → an existing TODO/ROADMAP/backlog — each through the validate-before-executing gate.

**When the planned queue is complete, obey the toggle:**
- **`stop`** (default) → do NOT pick up new work. Leave a verified-clean checkpoint + `/handoff`.
- **`continue`** → find the next valuable work autonomously, in order: (1) explicit "NEXT/deferred" in CLAUDE.md/PROGRESS; (2) a follow-on the just-finished retrospect surfaced; (3) the next roadmap/backlog item; (4) a `/readiness-audit` or `/retrospect` to surface the next thing; (5) cheap durable prep (contract traces, specs for queued features) that advances a future arc without a taste call. **Never invent a feature** — if nothing explicit is ready, do high-certainty objectively-valuable work that needs no taste call (strengthen the green baseline; `/codemap` or doc-sync if stale; trace + spec the next likely feature, left prospected; a `/readiness-audit`; close now-doable residuals). If even that is exhausted → `/handoff` with "no queued work — awaiting direction" rather than spinning.

If the next unit needs more context headroom than remains → STOP at a clean checkpoint and `/handoff` rather than fragment it. (Exception: on a `continue` + `self-restart` run, take the Step 3¾ path instead — checkpoint, write the restart-signal, and let the wrapper resume in a fresh process.)

## Step 5: Subagents & fan-out — budgeted, with hard stopgaps

DEFAULT to doing the work **inline**. A single agent (you) with inline tools is the efficient baseline; subagents are a deliberate, budgeted escalation. **NEED-IT gate before spawning any subagent:** legit reasons = (a) a broad fan-out read whose raw output would bloat your context but you only need the conclusion (delegate the search, keep the answer); (b) genuinely independent parallel work with no shared state; (c) an adversarial/second-opinion check. NOT legit = "be thorough," a single-file lookup you can do yourself, or work with sequential dependencies. Every subagent costs *your* context (dispatch + returned summary) even though its own tool output stays in its context — so delegate to SAVE context, never to spend it; require a tight structured result. Escalate, don't pre-commit: start inline/single-agent, widen to parallel only if the first pass proves it needs the breadth.

The NEED-IT gate is a *per-spawn quality check* — it is NOT a cumulative budget ceiling. 90 individually-justified spawns still drain the window. So THREE HARD stopgaps sit ON TOP of the NEED-IT gate, each covering a distinct runaway axis (count-in-one-burst · spend-in-one-burst · count-over-time). They are about *aggregate spend and blast radius*, not per-spawn merit. All thresholds below are built-in defaults; the user may override any of them in the invocation (e.g. `/auto … workflow`, `… fanout=40%`, `… agents=20`). There is no standing config key for these today — they are invocation-scoped (a persistent default would belong in `/setup`, not invented here).

- **Workflow is opt-in only — hard OFF by default** (caps one-shot *count*). The Workflow tool (multi-agent orchestration; fans out dozens at once) does NOT fire unless the user's invocation explicitly opted into it (`/auto … workflow`, or a clear "use a workflow / fan out agents / orchestrate this with subagents" in the request). A bare `/auto` — even an unattended `continue` run — runs inline + bounded individual subagents ONLY. The 90-agent sweep cannot happen unbidden. Non-negotiable invariant, not a judgment call.
- **Budget-fraction pre-flight gate** (caps one-shot *spend*). Before launching ANY fan-out (a `parallel()`/`pipeline()` over many items, an N-way audit/research sweep, or an opted-in Workflow), read the **live** remaining usage (the statusline state file — never a stale number, per Step 3) and *estimate* the fan-out's cost. If one shot would spend more than **~25% of the remaining usage window** (default; overridable via `fanout=<pct>`), STOP and surface it: the planned fan-out width, the estimated spend, the remaining window, and options (proceed · shrink to a smaller batch · serialize · skip). This is the direct fix for the "a single wide task drains the budget *between* the between-task checks" hole — the gate fires *before* the spend, sized to what's actually left, so it tightens as the window depletes. A fresh window may permit a wide sweep; the same sweep at 70%-used is refused.
- **Cumulative per-arc subagent cap** (caps *count-over-time* — the drip case). Maintain a running count of total subagents spawned this arc. After **~10 total** (default; overridable via `agents=<N>`), STOP and re-confirm before delegating more — report the count, what they accomplished, and the remaining work, then let the user raise the cap or switch to inline. This catches the slow drip the budget-fraction gate misses: many small individually-justified spawns over a long `continue` run, none of which trips the per-burst gate but which sum to a real drain. The counter is per-arc and resets only on a new `/auto` invocation.

These three are orthogonal — Workflow-opt-in bounds a single huge swarm, the budget gate bounds one expensive burst, the cumulative cap bounds slow accumulation. A run can pass any two and still be caught by the third.

## Step 6 (optional): Self-perpetuating run via resume cron

Only for an unattended, away-from-keyboard run **whose binding budget is usage, not context** (context-bound can't be resumed by a cron — see Step 3). Arm it EARLY and re-arm at or before 90% usage — never wait until the end (the session can die first and break the chain): `CronCreate`, `recurring:false`, `durable:true`, fire **5 minutes AFTER the next 5-hour reset boundary** (NOT at the exact reset minute — firing at the boundary risks landing before the window has actually reset/propagated, re-firing into a still-exhausted window and breaking the chain; the +5-min guard band ensures the new window is live). The prompt = a compressed mandate + "VERIFY STATE FIRST, this prompt may be stale" + "re-create this same cron for the next cycle before stopping (again +5 min after the following reset)." Arming a cron is part of the autonomous remit when the user asked for a self-perpetuating run; it is NOT something to do silently on an ordinary scoped arc.

## Step 7: Knowledge capture (as you go — durable, best-guess location, never blocking)

Write memories / `/prospect`+`/retrospect` logs / contract docs **at the moment of learning**. Update CLAUDE.md Status + PROGRESS each milestone (lead with the new state, demote prior detail under a pointer, never delete). Save a stated design/process decision as a memory immediately, with the WHY. Unsure where it goes → general backlog, keep moving (placement is pre-answered above).

## Step 8: Close the arc

Leave a **verified-clean checkpoint** (tests green, tree clean, pushed if policy allows). Report what landed, the `[DECISION]` trail, and every noted-but-not-blocking item you surfaced. Then `/handoff (auto)` with a next-session opener that itself says "VERIFY STATE FIRST — this prompt may be stale." Offer `/wrapup` instead if the work is fully done and nothing carries forward. Don't auto-run a push/deploy inside the close — that's the ungranted-approval case unless the contract's push policy already granted it.

## Notes

- **`/auto` applies policy, it doesn't redefine it.** The decide-vs-ask *logic* is Rule 35; this skill adds *operational* discipline (never-stop list, budget-binding, work-selection, subagent gate, resume-cron). If you want to change *when to ask*, edit Rule 35 — keep the single source of truth.
- **`/auto` never writes config.** It runs autonomously for the arc on the strength of the invocation; the standing `autonomy` posture changes only via `/setup` (one writer, no drift).
- **Tool allowlist companion.** For unattended runs, a pre-authorized `permissions.allow` list in the user's `.claude/settings.local.json` makes "tools are preset" real: the skill tells the model not to ask, the settings tell the harness not to gate. Keep them in sync — when a new tool causes a mid-run stop, add it there.
- **Self-restart wrapper — permission setup (example, follow only when you actually run one).** The `self-restart` flag needs `bin/auto-runloop.sh`, which spawns `claude -p --dangerously-skip-permissions`. That tripwires TWO independent gates, and you must clear BOTH:
  1. **The permissions system** — allowlist the wrapper in `.claude/settings.local.json`. Match how you invoke it (`sh <path>` vs `<path>` directly):
     ```json
     {
       "permissions": {
         "allow": [
           "Bash(sh */plugin-claude-code/bin/auto-runloop.sh:*)"
         ]
       }
     }
     ```
     (Use the absolute path on your machine; `:*` is the trailing-args shorthand. Verified vs the current settings schema, 2026-06-27.)
  2. **The auto-mode classifier** (a SECOND gate, only when auto mode is ON) — it independently hard-denies spawning an unattended `--dangerously-skip-permissions` agent, and **`permissions.allow` does NOT override it** (docs: "the classifier is a second gate that runs after permissions"). So either: run the wrapper from a **normal interactive session with auto mode OFF** (the allowlist alone suffices there), OR have your org's `autoMode` config trust it. Do NOT expect the allowlist rule alone to clear an auto-mode run.

  This is intentionally an example to copy when needed, not a setting this plugin writes — enabling `--dangerously-skip-permissions` is a standing security relaxation you should opt into deliberately, at the moment of a real unattended run, never by default.
