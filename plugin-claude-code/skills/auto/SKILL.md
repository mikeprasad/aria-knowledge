---
description: "Drive an autonomous execution arc end-to-end — compose brainstorm→spec→/prospect→plan→/prospect→TDD→/retrospect under the Rule 35 posture, decide objectively-validatable forks yourself, and stop only on a load-bearing fork or an ungranted approval. Modes: `arc` (default), `execute <plan|spec|ticket-id>` (skip ideation), `plan` (stop at a prospected plan, no code), `config` (guided per-run knob picker). Stackable, one word per axis: `full` (authority — all except push) · `attended`|`unattended` (presence) · `continue`|`stop` (duration) · plus `tickets` and `self-restart`. A bare invocation opens the `config` picker instead of guessing a goal. An explicit grant of autonomous latitude that overrides the standing `autonomy` config for the arc and never writes it. Use when the user hands off a goal, plan, ticket, or SESSION.md with latitude to execute WITHOUT per-step approval — 'combined go', 'run overnight', 'just build it', 'do as much as you can'. ENTRY POINT for a multi-step arc, NOT a single concrete change; distinct from /prospect, /retrospect, /handoff, /wrapup. (Code port — ADR-094.)"
argument-hint: "[arc|execute|plan|config] [<goal | plan-path | ticket-id>] [full] [attended|unattended] [tickets] [continue|stop] [self-restart]"
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

## Standing Directives — always on, never need asking for

These bind every `/auto` run in every mode. They are not modifiers and cannot be turned off.

- **D1 — Usage: the 5-hour figure binds; the 7-day figure is ignored.** When a statusline is
  visible, gate only on the 5-hour number. The 7-day number is never a reason to slow,
  shrink, defer, or stop. At **90%** 5h, arm or re-arm the resume schedule (Step 6). At
  **95%** 5h, PAUSE: checkpoint, commit, then wait for the reset if a resume is armed, else
  `/handoff`. When no statusline is visible (the desktop runtime reports an unreliable
  figure), do not infer a number and do not gate on one — ask.
- **D2 — A scheduled prompt never starts with `/`.** Applies to every scheduling mechanism.
  A leading `/token` is parsed as an unknown command and the whole mandate is silently
  discarded. Lead with prose; name a skill mid-sentence if you must reference one. The
  prompt must instruct the next scheduled run to start prose-first too. Enforced by
  `bin/pre-cron-check.sh`, not by this paragraph — the prose form of this rule shipped once
  and was violated twice afterward.
- **D3 — Foundational is always the answer**, unless the foundational fix would itself
  derail the arc. Never take the patching branch to protect schedule (Rules 18 and 38).
  Every firing of that carve-out is a D7 ledger entry.
- **D4 — Local commits only; push is never grantable.** No modifier — including `full` —
  pre-authorizes a push. Push stays a legitimate stop in every mode.
- **D5 — Report the live model name at every checkpoint**, so a silent model swap is visible.
- **D6 — A non-blocking stop never idles the run.** Note it, keep working, surface it at
  handoff.
- **D7 — The judgment ledger.** Any decision that could not be **Validated** (checked
  against ground truth, not asserted), **Deterministic** (same inputs, same verdict for
  anyone re-running it), **Traced** (the check is nameable and re-runnable), and
  **Confirmed after** (what was predicted actually held once built) is logged. All four
  hold → an ordinary `[DECISION]` line. **Any one fails → a ledger entry.** The ledger is a
  filter over the `[DECISION]` trail, not a parallel system.

  Write to `<knowledge_folder>/logs/auto/<YYYY-MM-DD>-<slug>-judgments.md`, resolving
  `knowledge_folder` from `~/.claude/aria-knowledge.local.md`. Create `logs/auto/` lazily.
  Entry shape:

      ### J<N> — <the decision, one line>
      - **Chose:** <what was done>
      - **Alternative not taken:** <what was rejected>
      - **Why not deterministic:** <which of the four tests failed, and how>
      - **Would be falsified by:** <the concrete check that would prove it wrong>
      - **Blast radius / reversal:** <files · commit · how to undo>
      - **Type:** judgment | D3-carve-out
      - **Disposition:** pending → accepted | revisit | reverted

  At arc close the ledger is reported **first**, ahead of the landed-work summary, and the
  user is explicitly prompted to review each entry (accept / revisit / revert); dispositions
  are written back into the file. **Stamp a disposition the moment the answer arrives, not
  at close** — an entry still reading "pending" after it has been answered misreports what
  needs the user's attention, which is the exact cost this ledger exists to remove. An
  answer can arrive obliquely: an instruction that keeps or widens the thing under review
  resolves it as surely as an explicit accept. If the arc ends via a context wall, a scheduled handoff,
  or a restart rather than a clean close, carry the ledger path in the `/handoff` opener and
  `SESSION.md` so the resuming session surfaces it before starting new work. **An empty
  ledger is stated, never omitted:** "0 judgment calls — every decision was deterministically
  validated." Silence and zero must stay distinguishable.

## Step 0: Parse mode, posture, and the queue-complete toggle

`/auto` is an **explicit, in-the-moment grant of autonomous latitude** — invoking it *means* "drive this autonomously, now." It overrides the standing `autonomy` config for the duration of the arc and never changes that config. Four modes, three stackable modifiers, and a toggle:

| Mode | Trigger | What it does |
|---|---|---|
| **arc** (default) | `/auto <goal>` or `/auto arc <goal>` | Full chain: brainstorm → spec → /prospect → plan → /prospect → execute → /retrospect. The default whenever a goal is given without a mode keyword. (A **bare** `/auto` with no goal opens `config` instead — see Parsing.) |
| **execute** | `/auto execute <plan-path \| ticket-id \| "the plan">` | A plan/spec already exists. Skip ideation; run /prospect → build (TDD/SDD) → /retrospect. |
| **plan** | `/auto plan [<goal>]` | Produce a prospected, cold-executable plan and STOP. Runs brainstorm → spec → /prospect → plan → /prospect. **No code.** The mirror of `execute`. |
| **config** | `/auto config [<goal>]` (alias `/auto preflight`) | Guided pre-flight: walk every run setting one at a time as a picker (so nothing has to be remembered), assemble the run-config, then drive the arc with it. Configures THIS run only — never persists (that's `/setup`'s job). See Step 0¾. |

**Modifiers** (stackable, any position, case-insensitive):

- **`full`** — maximum authority on every axis **except push**: tools/MCP/plugins
  pre-approved · Workflow fan-out ON (default is hard-OFF) · cumulative subagent cap
  10 → 30 · fan-out budget-fraction gate 25% → 40% · self-decide every
  objectively-validatable fork. (**Arming a resume is NOT an authority grant** — it belongs
  to the presence axis below, and `full` deliberately says nothing about it.) `full` is defined by its
  boundary: **every grant except the one that leaves the machine** (D4). It **raises the
  three Step 5 fan-out stopgaps but does not remove them** — raised, finite, still live,
  because an unattended max-authority run is the case most exposed to unbounded spend, and
  the budget-fraction gate is what protects D1's 95% pause.
*(There is deliberately no `loop` modifier. An earlier draft had one meaning
"unattended + continue + self-restart", but once arming moved to the presence axis where it
belongs, `loop` reduced to a strict alias for `unattended continue` — adding a word and no
capability. It had already produced the drift a redundant word invites, claiming
resume-arming that `full` also claimed, and it was the worst of the mid-prose collisions:
`/auto fix the render loop bug`. The overnight run is `/auto full unattended continue` —
one word per axis, no special cases.)*
- **`attended` / `unattended`** — the **presence** axis: is a human reachable right now?
  Two values, and **the arc contract always states which is in force**, because it changes
  what happens to every question the run produces. Neither is inferred silently: if the
  invocation does not say, `config` asks (Step 0¾ knob 7), and a bare run defaults to
  `attended` — assuming someone is there is the safe error, since the cost is one surfaced
  question rather than an hour of unreviewed autonomy.
  - **`attended`** — a **non-blocking** residual is surfaced **immediately** rather than
    noted and batched to the handoff. D6 ("a non-blocking stop never idles the run") is
    thrift when you are asleep and waste when you are at the desk: an answer worth ten
    seconds of yours can otherwise cost an hour of second-best work. `attended` narrows D6,
    it does not repeal it — the run still never *idles* waiting, it asks and keeps working
    and takes the answer when it arrives. Blocking residuals halt as always.
  - **`unattended`** — nobody is reachable. Non-blocking residuals are noted and carried to
    the handoff (D6 unchanged), and a resume that fires does so **silently, without**
    expecting anyone to see it. Presence does **not** decide *whether* a resume is armed —
    unfinished work at the usage wall does (Step 6). Under `attended`, the same resume is
    armed and simply **announces itself** when it fires.

  **Two different walls need two different mechanisms — do not conflate them:**

  | Wall | Mechanism | Effect |
  |---|---|---|
  | **Usage** — the 5h window is exhausted | the **resume schedule** (Step 6) | Re-fires *this* session after the reset, local work intact |
  | **Context** — the window hits 90% | **`self-restart`** + `bin/auto-runloop.sh` | Relaunches a **fresh process** with a clean window |

  A resume schedule cannot rescue a context wall (it re-enters the same full session), and a
  fresh process does not help when the limit is usage. `unattended` arms the resume for the
  usage wall; the context wall needs `self-restart` **explicitly**, because it cannot be
  made to work implicitly. **`self-restart` is inert unless the external
  wrapper is already running** — invoked directly in a normal session it writes the restart
  signal and stops with nothing to consume it, so say so rather than implying the run is
  self-healing.
- **`tickets`** — tracker-bound. Work selection comes from the connected tracker by
  priority; comment on the ticket at every commit; never claim a ticket without verified
  validation.

  **Resolving the tracker — never hardcode a vendor.** Probe at runtime for a connected
  `~~project-tracker` MCP and adapt, as `/digest` does: Linear · Asana · Atlassian/Jira ·
  Monday · ClickUp · Notion-as-tracker · GitHub Issues. Probing is prose-only; there is no
  helper API (ADR-015). If `ticketing_plugins` is set in `~/.claude/aria-knowledge.local.md`
  (comma-separated `tag:plugin-command` pairs, read directly from the file the way
  `/audit-knowledge` reads it), it wins — that is the user's explicit declaration.
  **Never verify that a mapped command is actually installed:** enumerating installed
  plugins couples this skill to runtime internals that can change, and a loud failure at
  invocation beats a silently-absent hint. Detect ticket IDs with the vendor-neutral `\b([A-Z]{2,}-\d+)\b`. With
  no tracker connected and no mapping, say so once and fall back to the Step 4
  work-selection order — `tickets` never hard-fails an arc.

**Three orthogonal axes — set each independently.** `full` sets *how much latitude*;
`continue`/`stop` set *how long*; `attended`/`unattended` set *whether a human is reachable*.
Keeping them separate is what makes every combination expressible:

- `/auto full` — max authority, scoped: stops when the queue clears
- `/auto full unattended continue` — max authority, overnight: never idles, nothing is asked,
  resume armed for the usage wall (add `self-restart` only if the wrapper is actually running)
- `/auto full attended` — max authority and you are at the desk: everything pre-approved
  except what genuinely cannot be determined, and *that* reaches you the moment it arises
- `/auto attended` — default authority, but residuals come to you live rather than at handoff

**On-queue-complete toggle** (a trailing `continue` or `stop` keyword, default **stop**): what to do once the *planned* queue is done.
- **`stop`** (default) — checkpoint + `/handoff` when the queue is clear; do NOT pick up new work. The right choice for a scoped "just do X" run. Default to this if unset — don't over-reach the remit.
- **`continue`** — keep finding the next valuable work autonomously (see Step 4); for unattended / overnight runs. Don't stop at the arc boundary.

**Context-self-restart flag** (a trailing `self-restart` keyword, default **off**): only meaningful with `continue`. When set, a context-window wall does NOT terminally stop the arc — instead the skill writes a restart-signal file that the external `bin/auto-runloop.sh` wrapper watches, so the arc resumes in a FRESH process (clean context). See Step 3¾. Requires the wrapper to be running and a permission allowlist (the wrapper spawns `claude -p --dangerously-skip-permissions`, which the auto-mode classifier blocks unless allowlisted). Without the flag, a context wall behaves exactly as today (terminal stop + `/handoff`).

**Parsing.** If the first arg case-insensitively matches `arc`, `execute`, `plan`, `config`, or `preflight`, that's the mode; otherwise the mode is `arc`.

**Modifiers are recognised only at the ENDS — never mid-prose.** Scan the contiguous run of modifier tokens at the start (after any mode keyword) and the contiguous run at the end; **once goal prose begins, every remaining token is goal.** This matters because the modifier names are ordinary English words: an anywhere-in-args scan turns `/auto fix the **render loop** bug` into an unattended self-restarting run, and "do a full review" or "close the tickets" the same way. Worked cases:

- `/auto full unattended tickets clear the payments queue` → mode `arc`, modifiers `{full, unattended, tickets}`, goal "clear the payments queue"
- `/auto fix the render loop bug` → mode `arc`, **no modifiers**, goal "fix the render loop bug"
- `/auto ship the CSV exporter continue self-restart` → goal "ship the CSV exporter", toggle `continue`, flag `self-restart`

A trailing `continue`/`stop` sets the on-queue-complete toggle; a trailing `self-restart` sets the context-restart flag (honored only alongside `continue`).

**A bare invocation falls through to `config`.** When there is **no mode keyword and no goal text**, open the guided picker (Step 0¾) rather than inferring a goal. **Modifiers and toggles do not count as goal context** — they say *how* to run, never *what* to run — so `/auto`, `/auto full`, `/auto unattended` and `/auto full continue` all open the picker, **pre-seeded** with whatever was typed so nothing is re-asked. The alternative is guessing a goal from `SESSION.md`, which is precisely the stale-resume hazard "Verify before you trust" warns about: a saved prompt may describe work already shipped. When a goal *is* named as "continue from SESSION.md / the latest handoff," resolve it through Step 4's work-selection order as before.

**Two ways to handle unspecified settings — you remember nothing either way:**
- **Default (`/auto [goal]`)** — pick the safe default for everything unspecified and **surface them all in the arc contract** (Step 0.5) before driving. You *react* to the shown list; you never have to *recall* what's configurable. Minimal friction.
- **Guided (`/auto config`)** — when you'd rather set the knobs deliberately, the walkthrough (Step 0¾) **presents each one as options, one at a time**, so the option list lives in the picker, not your memory. You opt into this per run.

**Relation to the `autonomy` config.** The standing `autonomy` config (`default`/`balanced`/`autonomous`, owned by `/setup`) sets how autonomous I am on sessions where you *didn't* invoke `/auto`. `/auto` is the in-the-moment override for *this* arc — it runs at full self-decide latitude regardless of the config value, including at `autonomy: default`. You never need to flip the config to use `/auto`; the invocation is the grant. Don't bother reading the config value — it can't change `/auto`'s behavior, and the arc contract (Step 0.5) already announces the autonomous posture, so a separate "your standing default is X" note would be redundant ceremony. `/auto` never writes the config either — changing the standing posture is `/setup`'s job, exclusively (one writer, no drift).

## Step 0¾: Guided config walkthrough (`config` mode only)

Runs ONLY when invoked as `/auto config` (or `/auto preflight`). Skip entirely for `arc`/`execute`. Purpose: let the user set each run setting deliberately **without having to remember any of them** — present each as a picker, one at a time, with the safe default pre-marked. Use the platform's question/picker affordance (one question per knob); accept a bare-number/keyword reply; "skip" on any knob takes its default.

Walk these in order, **one at a time** (do not dump all seven at once — the point is recognition-not-recall, one decision per step):

1. **Goal / source** — this prompt's goal · continue from `SESSION.md`/latest handoff · a plan path · a ticket ID from your connected tracker. (If a goal was passed as `/auto config <goal>`, pre-seed it and confirm.)
2. **On-queue-complete** — `stop` (scoped: checkpoint + /handoff when the queue's clear — *default*) · `continue` (keep finding new work; for unattended/overnight).
3. **Push policy** — commit local, no push (*default*) · commit + push per host convention. (Push remains an ungranted-approval stop regardless — this only sets the intent.)
4. **Fan-out / subagents** — inline-only · bounded individual subagents, ~10 cumulative cap (*default*) · raise the cap to N · allow the Workflow swarm (multi-agent orchestration). (Maps to the Step 5 stopgaps.)
5. **Budget ceiling** — default 25%-of-remaining-window per fan-out burst (*default*) · a different fraction · a hard "stop the arc at X% usage." (Maps to the Step 5 budget-fraction gate + a live abort floor.)
6. **Resume at the usage wall** — arm (*default when the goal is non-trivial*) · off. If the 5-hour window runs out with the goal unfinished, a resume fires **+5 min after** the reset and picks the work back up (Step 6). **Not gated on #2 or #7** — an unfinished goal warrants a resume whether or not you asked for new work afterwards, and whether or not anyone is watching; presence only decides if it announces itself.
7. **Presence** — `attended` (*default*: you are reachable, so a non-blocking residual is surfaced immediately rather than batched to the handoff) · `unattended` (nobody is reachable; residuals are carried to the handoff and the run arms its own resume). **Always ask this one** — it is cheap to answer and it changes what happens to every question the arc produces, so a run should never proceed without knowing it. Pre-seeded from the invocation when `attended` or `unattended` was passed.

After the walkthrough, assemble the picks into the run-config and proceed to Step 0.5 — the **arc contract is then a confirmation of what you just chose**, not a fresh set of defaults. **Nothing persists**: these picks configure THIS arc only; the standing `autonomy` posture and any saved defaults are untouched (changing standing defaults is `/setup`'s job — `/auto` never writes config, in any mode).

## Step 0.4: Load the standing user rules

Before stating the contract, load the user's own standing rules so the whole arc runs aware of them — `/auto` must never drive an autonomous arc blind to the rules the user has already written down. This is separate from Rule 35: Rule 35 (in the plugin-managed `working-rules.md`) is the decide-vs-ask *routing* policy; `user-rules.md` is the user's own *substantive* rules (how they want work done — commit/push discipline, design taste, rejection criteria, ARIA-behavior preferences). `/auto` applies both.

1. **Resolve + read.** Read `~/.claude/aria-knowledge.local.md` and extract `knowledge_folder` (same resolution the `/rules` skill uses). Read `{knowledge_folder}/rules/user-rules.md` if it exists. It is **optional and user-owned** — it may be absent (pre-v2.8.1 setups) or present with no `### U` rules yet. If absent, or present but empty of rules, treat it as **no standing user rules** and continue — a missing file is never a stop.
2. **Hold as active constraints for the arc.** When real user rules are present, treat each as a **binding constraint applied wherever it is contextually relevant** across the whole arc — not just consulted once. A user rule about pushing gates the push step; one about design taste informs execution and review; one about rejection criteria shapes what you accept as done. This is stronger than "be aware": where a user rule speaks to the situation at hand, it **governs**.
3. **The one carve-out — validated proof with critical impact wins.** A user rule does NOT govern in the narrow case where applying it would be **actively detrimental** or would **contradict validated empirical proof whose violation carries critical impact** (a safety, correctness, or data-loss consequence you have actually verified against ground truth — not a hunch, and not mere inconvenience). This mirrors the skill's "verify before you trust" discipline: ground truth you have confirmed outranks a standing assumption. When this carve-out fires, do NOT silently override — treat the conflict as a **legitimate stop** (Step 2): surface the specific user rule, the validated proof that opposes it, and the critical impact, and let the user resolve it. The carve-out is an escalation trigger, not a license to ignore a rule.
4. **Compose, don't duplicate.** `/auto` *loads and applies* user-rules.md; it does not restate the rules' content in the report, re-implement `/rules`, or fork the file. If the user asks *what* their rules are mid-arc, defer to `/rules`. This step is purely: make the arc operate under them.

Loading is one read at arc start; the rules then travel with the arc the same way Rule 35 does.

## Step 0.5: State the contract before driving

Before the first action, post a short **arc contract** so the autonomy is legible — the user should never be surprised by what you decided alone vs. what you'll stop for:

> **Arc:** <one-line goal> · **Mode:** <arc | execute> · **On-complete:** <continue | stop>
> **Standing rules loaded:** user-rules.md — <U1…UN applied where contextually relevant | none (absent or no rules yet)> (from Step 0.4).
> **I'll decide myself:** objectively-validatable forks (checked against real code/corpus/docs, held to Rules 13/14/18 — simplest/robust/clean, no unneeded abstraction).
> **I'll handle without stopping:** knowledge placement, tool/permission approvals, backlog/deferral, ticket filing, the normal commit cadence (see Pre-answered below).
> **I'll stop and ask on:** product/UX taste with no objective answer · an irreversible/outward-facing action not covered by policy *that blocks the task* · a true no-visibility fact only you have · a genuine costly fork empirical investigation can't decide.
> **Gates that run but don't count as stopping:** /prospect (pre-code), /retrospect (post-build).
> **Presence:** <attended — non-blocking residuals come to you as they arise | unattended — residuals batched to the handoff, resume armed>. Always stated; never inferred silently.
> **Usage:** gating on 5h only; 7d ignored · arm at 90% · pause at 95% (D1).
> **Push:** local commits only — never pre-authorized by any modifier, including `full` (D4).
> **Tools:** MCP / plugins / skills pre-approved.
> **Foundational:** always preferred; any carve-out is logged (D3 → D7).
> **Judgment ledger:** `<resolved path>` — reported first at close, for your review (D7).
> **Model:** <live model name> — re-reported at each checkpoint (D5).

This contract is the operative form of Rule 35's routing table for *this* arc. You don't re-derive the table — you instantiate it.

## Verify before you trust (the #1 rule — most friction traces here)

Before acting on **any** assertion — a resume prompt, a handoff, a stale doc, your own memory, a cached metric, a `SESSION.md` "next" line — **verify it empirically against the live source.** Run `git log`/`git status`, read the live state file, grep the real code. A resume prompt may be stale (the work is already shipped — don't redo it); a cached usage % may be stale (window reset → trust the reset *timestamp* vs now, not the number). For backend behavior, API contracts, or field shapes, read the source-of-truth repos FIRST (backend + the shipped client) — never assume, and don't file a "backend gap" until the repos genuinely don't answer it. This is the discipline that earns the right to self-decide: "validated" means checked against ground truth, not asserted.

## Pre-answered — handle and keep going (do NOT stop for these)

Rule 35 says route by question type; these are the recurring autonomous-run cases pre-routed to **act**, so an unattended arc doesn't stall on them:

- **Knowledge placement** — never pause to ask *where* something goes. Make it durable in the best location you can judge (memory · /prospect+/retrospect log · contract doc · CLAUDE.md + PROGRESS). Unsure → drop it to the general intake backlog for a future audit to sort. Placement is never a stop.
- **Tool / MCP / permission approvals** — assume the build/test/lint, sim, git, Cron, MCP, and skill verbs are pre-approved (a companion allowlist in the user's `.claude/settings.local.json` makes this real at the harness level — see Notes). If one tool is genuinely blocked, route to the working alternative and note it. Only OS-level GUI popups need a live human — flag once and route around.
- **Backlog / deferral** — a known follow-on (out-of-scope feature, separate-team backend change, device-gated smoke) → file/note it and DEFER. Don't stop to ask whether to defer.
- **Tickets** — create freely in the connected tracker: status backlog/Undefined, assigned to the user for post-session review, both intakes present (Technical Intake marked DRAFT), enriched via comments. Never stop to ask whether/how to file.
- **Known-pattern git/scope** — stage named in-scope files, commit, push (per the contract's push policy). Don't ask permission for the normal commit cadence.
- **Self-recommended chain choices** — a spec/prospect/plan fork a recommendation already answers → take the recommendation. "Self-recommended + answerable" is not a stop.

## Step 1: Drive the arc

Run the chain by **invoking the real skills** via the `Skill` tool, not by summarizing them. Composition keeps the gates honest: the quality checks are the actual checks, and improvements to those skills flow through automatically.

**Degrade gracefully when a composed skill or tool is absent.** `brainstorming`, `writing-plans`, `test-driven-development`, and `subagent-driven-development` are Superpowers skills (strongly recommended, optional). If one isn't installed, name what's missing, fall back to doing that phase inline (a plain brainstorm, a hand-written plan, manual red-green-refactor), and say the gate ran in degraded form. The `execute <ticket-id>` path needs a connected project-tracker MCP — if unavailable, ask the user to paste the ticket rather than proceed on a missing plan.

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

Skip steps 1–2. Resolve the plan source (path → `Read`; ticket ID → tracker MCP fetch if available; quoted string → treat as the plan), then run 3 → 6 → 7.

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

**A fork is a stop only AFTER investigation can't decide it — measure before escalating.** The 4th bullet is the trap: "load-bearing fork" reads like a license to stop, but most forks that *feel* load-bearing are just unfinished investigation. Before calling anything a stop, ask "is this an empirical question I can resolve myself?" (Rule 35: investigate the resolvable, ask only the residual.) In particular, a **reactive fix-forward cascade** — the same failure recurring as you patch each instance (model N, then N+1, then N+2…) — is a **smell, not a fork**: step back and probe whether one upstream change dissolves the whole class, pick the objectively-better option, and continue. Don't sink cycles into the reactive path and *then* escalate the choice you could have decided by measuring. Escalate only the genuine residual the 4th bullet describes: both branches plausible, the wrong one costly, AND investigation genuinely can't decide.

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

**Grain, once you DO fan out: one agent per shared-context cluster, not per item.** The stopgaps above bound *whether/how much* to delegate; this bounds *how to carve the work* once you're delegating. The intuitive "one agent per task/item" is usually the wrong default — it pays twice: **(1) redundant context re-loading** (N agents each re-derive the context their items share — that spends the very context delegation was meant to save), and **(2) seam-blindness** (a per-item agent can't see its neighbor items, so it makes locally-reasonable, globally-wrong choices at the seams — divergent identifiers, missed cross-item constraints). So the default grain is **one agent per cluster of items that share a context** — a file neighborhood, a repo, a document, a domain — keyed on *what the items share*, not *how many* there are. Split down to per-item ONLY when one of three forces requires it: **write-contention** (two agents would edit the same file set concurrently → serialize in one agent or split into separate waves), **per-item auditability** (the work needs a clean per-task review gate a blended cluster report would obscure — code with compounding failures earns this; inline content usually doesn't), or **context-ceiling** (the cluster won't fit one agent's working window with accuracy to spare — past which you just move seam-blindness inside one agent). Absent one of these, cluster — and if you split, say why.

## Step 6 (optional): Self-perpetuating run via resume cron

**Arm whenever work remains unfinished and the binding budget is usage, not context** (context-bound cannot be resumed by a schedule — see Step 3). **Arming is NOT gated on presence, and NOT gated on `continue`.**

That distinction is load-bearing and was wrong in v2.43.0. `continue` governs whether to find **new** work once the planned queue is clear — it says nothing about **finishing the goal you were already given**. Gating arming on it stranded the common case: a scoped `/auto full attended <goal>` that hit the 95% pause mid-goal simply stopped, goal unfinished, with nothing scheduled to pick it up. The question that decides arming is **"is the work I was given actually done?"**, not "will there be more after it?" and not "is anyone watching?".

**Presence changes only how the resume behaves, never whether it exists:** an `unattended` resume fires silently, without expecting anyone to see it; an `attended` resume **announces itself** when it fires, so you know work restarted while you were away from the keyboard. Both are armed on the same condition.

**Mechanisms are gated on availability first, capability second.** `CronCreate` is the **baseline and the default**: it is the only one present in **every runtime**. Its session-only nature is an accepted constraint, not a defect — an unattended run keeps its session open by design.

| Mechanism | Available | Survives session death | Fresh context | Use for |
|---|---|---|---|---|
| **`CronCreate`** — the default | **Always, every runtime** | No — **session-only**, in-memory; recurring auto-expires at 7 days; fires only while the REPL is idle | No — re-enters this session | Usage-bound resume with the session left open. The normal unattended run. |
| **A persisted scheduled task** | **Desktop runtime only** — probe, never assume | Yes — runs at next app launch if missed | Yes | A resume that must survive the session ending, where the runtime offers it |
| **launchd** (the `pm-schedule.sh` pattern) | macOS only; user opts in | Yes — OS-level | Yes — a fresh `claude` invocation | Truly session-independent recurring work on the CLI |
| **`bin/auto-runloop.sh`** (`self-restart`) | Wrapper must already be running | Wrapper-dependent | Yes — a fresh `claude -p` process | A context wall mid-arc (Step 3¾) |

**Selection rule.** Default to `CronCreate`. Reach past it only when the resume genuinely must survive the session ending — and then **probe what this runtime actually offers** rather than naming a mechanism the user may not have. State which one you chose and why. **Never promise durability the runtime cannot deliver.** The mechanisms are not substitutes: a schedule resumes work at a *time*, `self-restart` recovers from a *context wall*.

**Do not pass `durable: true`** — the tool documents it as having no effect; all jobs are session-only.

Arm it EARLY and re-arm at or before 90% usage — never wait until the end (the session can die first and break the chain): `recurring:false`, fire **5 minutes AFTER the next 5-hour reset boundary** (NOT at the exact reset minute — firing at the boundary risks landing before the window has actually reset/propagated, re-firing into a still-exhausted window and breaking the chain; the +5-min guard band ensures the new window is live). The prompt = a compressed mandate + "VERIFY STATE FIRST, this prompt may be stale" + "re-create this same cron for the next cycle before stopping (again +5 min after the following reset)." **The cron prompt MUST lead with prose — never start it with a slash command** (a leading `/auto` or any `/command` is parsed as an unknown command and the whole mandate is silently discarded; phrase the mandate in prose and, if you must reference a skill, name it mid-sentence). This is the same prose-first hazard as the Step 3¾ restart opener — one rule, two arming sites. Arming a cron is part of the autonomous remit when the user asked for a self-perpetuating run; it is NOT something to do silently on an ordinary scoped arc.

## Step 7: Knowledge capture (as you go — durable, best-guess location, never blocking)

Write memories / `/prospect`+`/retrospect` logs / contract docs **at the moment of learning**. Update CLAUDE.md Status + PROGRESS each milestone (lead with the new state, demote prior detail under a pointer, never delete). Save a stated design/process decision as a memory immediately, with the WHY. Unsure where it goes → general backlog, keep moving (placement is pre-answered above).

## Step 8: Close the arc

Leave a **verified-clean checkpoint** (tests green, tree clean, pushed if policy allows). Report what landed, the `[DECISION]` trail, and every noted-but-not-blocking item you surfaced. Then `/handoff (auto)` with a next-session opener that itself says "VERIFY STATE FIRST — this prompt may be stale." Offer `/wrapup` instead if the work is fully done and nothing carries forward. Don't auto-run a push/deploy inside the close — that's the ungranted-approval case unless the contract's push policy already granted it.

## Notes

- **`/auto` applies policy, it doesn't redefine it.** The decide-vs-ask *logic* is Rule 35; this skill adds *operational* discipline (never-stop list, budget-binding, work-selection, subagent gate, resume-cron). If you want to change *when to ask*, edit Rule 35 — keep the single source of truth.
- **Two rule sources, both loaded, neither restated.** `/auto` operates under two distinct rule files and owns *neither*: **Rule 35** in the plugin-managed `working-rules.md` is the decide-vs-ask *routing* policy (edit it to change *when to ask*); **`user-rules.md`** is the user's own *substantive* standing rules, loaded in Step 0.4 and applied as binding constraints for the arc (edit them via `/rules`-adjacent flows / `/audit-knowledge` promotion, never here). `/auto` reads and applies both; it restates neither. To see the rules' content, use `/rules`.
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
