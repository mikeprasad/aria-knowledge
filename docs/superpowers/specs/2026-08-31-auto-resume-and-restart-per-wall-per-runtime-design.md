# Design — `/auto` resume and restart, decided per wall and per runtime

**Date:** 2026-08-31
**Skill:** `skills/auto/SKILL.md` — ⛔ **THREE ports, diverged** (claude-code `65,104 B`,
antigravity `64,895 B`, openai-codex `52,099 B`; three distinct md5s; cowork has no `auto`)
**Status:** DRAFT — plan gated separately. **No code until `/prospect` passes.**
**Supersedes:** exactly one premise of `2026-07-30-auto-modifiers-and-standing-directives-design.md`
§"Step 6 rewrite" — named in full below. That spec's decision was correct on its own evidence;
this one changes a premise, not its reasoning.

**Rulings (Mike, 2026-08-31):**
1. *"1"* — full coverage, runtime-adaptive: both walls covered in both runtimes where possible.
2. *"make the usage resumption standard on all `/auto full unattended` sessions. no modifier word
   needed (it part of unattended)"* — reconciled, on the record, to **"presence picks the
   mechanism, not whether"** (the literal reading was put to him and declined; see D1/D2).
3. **OQ1 — probe live before committing the form.** The one-shot stall is a single observation
   from 2026-06-13→15; measure it current, then choose `fireAt` vs recurring. Probe method and
   result recorded at OQ1 below.
4. **OQ2 — `/setup` owns a narrow allowlist.** See D10.

---

## Problem

`/auto` must survive two different walls, and it conflates them in three ways.

| Wall | Meaning | What recovery requires |
|---|---|---|
| **Usage** | the 5-hour window is exhausted | resume *later in time*, local state intact |
| **Context** | the window reaches ~90% | continue *now*, with a *clean* context |

**Three defects in the current account, all measured:**

1. **The skill contradicts itself across two sections.** `SKILL.md:404` asserts *"The only
   autonomous path to clean context is a **fresh `claude` process**, which an external wrapper
   provides."* Its own Step 6 table, ~50 lines later, carries a **"Fresh context"** column with
   **Yes** on the persisted-scheduled-task row. Consequence: Desktop is documented as having no
   context-wall path while the mechanism that provides one sits in the skill's own table.
2. **The default mechanism is wrong precisely when nobody is watching.** `CronCreate` is
   session-only and in-memory. It is the default for every presence, including `unattended` —
   the one case where no human is present to keep the session alive.
3. **The silent-failure mode is documented nowhere.** An unattended one-shot `fireAt` task
   **stalls at the first tool-permission gate** and produces *zero output*, indistinguishable
   from never firing. Measured 2026-06-13→15; `grep` for it across all three ports returns **0**.

---

## Measured ground truth

Mechanism matrix. Evidence: live `claude mcp list` (2026-08-31), the tool schemas, and
`knowledge/references/claude-code-session-and-hooks.md:56-57` (measured 2026-06-13→15).

| Mechanism | Available | Survives session death | Fresh context | Local tree |
|---|---|---|---|---|
| `CronCreate` | **every runtime** | ❌ session-only (`durable:true` is a documented no-op) | ❌ same session | ✅ |
| `mcp__scheduled-tasks__create_scheduled_task` | **Desktop only** | ✅ on disk, runs at next launch if missed | ✅ *"no memory of this conversation"* | ✅ |
| `launchd` (`pm-schedule.sh`) | macOS CLI, user opts in | ✅ OS-level | ✅ fresh `claude` | ✅ |
| `bin/auto-runloop.sh` (`self-restart`) | wrapper must **parent** the session | wrapper-dependent | ✅ fresh `claude -p` | ✅ |

**Two candidates filtered — provable defects, not preferences:**
- **`/schedule` cloud routines** — run against a *repo checkout*, not the local working tree.
  Cannot continue uncommitted work. Disqualified for this purpose.
- **`ScheduleWakeup`** — clamped to `[60, 3600]` s. Cannot span a 5-hour window in one hop.

**Runtime evidence:** `scheduled-tasks` is absent from `claude mcp list` and is bare-prefixed
(`mcp__scheduled-tasks__`, not `mcp__plugin_*__`) ⇒ runtime-injected, Desktop-class only.

---

## The one premise this supersedes

The July 30 spec declined to promote `create_scheduled_task` and gave five reasons. **Four still
stand and are adopted here.** One is falsified:

> *"its session-only nature is an accepted constraint, not a defect — an unattended `/auto` run
> keeps its session open by design."*

An unattended overnight run **cannot guarantee** the session stays open: Mac sleep, app
auto-update, crash, or OS restart each end it. The same knowledge reference concedes the
condition — a CLI `CronCreate` fallback *"needs the terminal kept open + the Mac awake"* — which
is a precondition, not a design guarantee.

**What the July 30 spec got right and this spec keeps:** its load-bearing argument was about
*defaulting* — *"In a public plugin, defaulting CLI users to a mechanism that silently is not
there would dead-end `/auto`'s resume chain."* **That is correct and is preserved.** This design
never defaults CLI users to a Desktop mechanism; it probes.

The July 30 spec's own Selection rule already said *"reach past it only when the resume genuinely
must survive the session ending"* — but never defined **when that is**. Mike's ruling supplies the
missing predicate: **`unattended` *is* that condition.**

⚠ One further reason is now stale, minor: *"the plugin contains zero references to the
scheduled-tasks surface anywhere."* Measured today — `plugin.json` `.hooks.PreToolUse[4].matcher`
is `'CronCreate|mcp__scheduled-tasks__create_scheduled_task'`. The July 30 spec's **own
Deliverable B** wired the D2 prose-first hook to the surface its prose declined to default to.

---

## Decisions

**D1 — the arming *condition* is UNCHANGED.** Arm whenever work remains unfinished and the
binding budget is usage, not context. **Not gated on presence. Not gated on `continue`.**
`SKILL.md:443/445/447` and config knob 6 stay as written. *(The literal reading of the ruling —
arm only under `unattended` — was put to Mike with its cost named and declined; it would reopen
the v2.43.0 regression on the presence axis.)*

**D2 — presence selects the *mechanism*.** This is the new coupling and the substance of the
ruling.

| Presence | Runtime | Mechanism | Why |
|---|---|---|---|
| `unattended` | Desktop | `create_scheduled_task` (`fireAt`) | nobody keeps the app open |
| `unattended` | CLI | `launchd` if installed, else `CronCreate` **+ state the exposure** | no `scheduled-tasks` on CLI |
| `attended` | either | `CronCreate` | the session is being watched |

**D3 — detect by CAPABILITY, and reuse the probe that exists.** `kt_resolve_account()`
(`bin/config.sh:44`) already returns `<runtime>` in `{cli, desktop, desktop-unknown}`.
⛔ **CORRECTED 2026-08-31, measured two-sided — an earlier draft of this D3 said `desktop-unknown`
is NOT desktop and must fall to the CLI branch. That is WRONG and would have denied the durable
mechanism to a genuine Desktop session.** `config.sh:83-86` prints `desktop-unknown` in **both**
the account field and the runtime field, and its comment reads *"Desktop but unresolved → degrade
(**never assert an account**)"* — the degrade concerns the **account key**, never the runtime
class. Forced-degrade run (desktop signal present, Tier 1+2 resolution broken) returned
`desktop-unknown`; negative control (no desktop signal) returned `cli`.

**Routing: `desktop` → Desktop branch · `desktop-unknown` → Desktop branch · `cli` → CLI branch.**

**Capability presence is the authority; the classifier is only the hint.** Select the durable
mechanism only when the classifier says Desktop-class **and** the verb is actually callable. A
Desktop classification with the verb absent falls back to `CronCreate` **with the exposure
stated** — that is the real fail-closed rule, and it does not depend on reading the degrade tier
correctly. This mirrors the
capability-not-name principle already ratified in
`2026-08-28-runtime-gate-auto-redirect-design.md` (which tests for `Bash`, not a runtime name).
⚠ `config.sh:42` is marked **KEEP BYTE-IDENTICAL** with a `statusline-meter.sh` mirror — this
design **reads** it and must not modify it.

**D4 — Desktop gains a context-wall path, resolving the self-contradiction.** At the context
wall on Desktop: `/extract` → `/handoff` (prose-first opener) → `create_scheduled_task` with
`fireAt ≈ now + 2 min` → stop cleanly. Each run *"starts fresh with no memory of this
conversation"*, which is the clean context. `SKILL.md:404`'s "only autonomous path" claim is
rewritten to "the only path **on the CLI**".

**D5 — one honest gap, stated not papered over.** CLI + *interactive* (no wrapper parenting the
session) has **no autonomous context-wall path** — `/clear` is a REPL built-in a skill cannot
issue. Behaviour there is unchanged: `/extract` → `/handoff` → terminal stop.

**D6 — the approval precondition is ALLOWLIST-CONDITIONAL, and the arc contract must report it.**
Measured both ways (OQ1): an unattended one-shot `fireAt` **stalls** on a Bash call that is *not*
in `permissions.allow`, and **executes normally** on one that is. Per-task approvals do inherit
forward, so a one-shot has none to inherit — but that route is moot, because **D10's settings
allowlist removes the need for per-task approval entirely.**

⇒ The precondition is simply: *are the arc's Bash patterns allowlisted?* Satisfied once, by
`/setup` (D10).

**Step 0.5 must state `durable resume: ARMED | UNAVAILABLE (patterns not allowlisted)`.** Arming
something that will silently stall is worse than not arming it — and the stall is invisible
(`lastRunAt` set, task auto-disabled, nothing executed; see D7).

**D7 — the success oracle is a task-produced ARTIFACT. `lastRunAt` is a *dispatch* oracle and
must never be read as success.** ⛔ **CORRECTED 2026-08-31 by live probe — an earlier draft of
this D7 said to "verify a resume with `lastRunAt`". That is wrong and would certify a stalled
run as a working one.**

Measured: the stalled probe set **`lastRunAt: 08:53:15.725Z`** *and* flipped **`enabled: false`**,
while executing nothing. So a stalled one-shot **reports as having run, disables itself, and is
never retried.** `lastRunAt` answers *"was it dispatched"*, never *"did it work"* — the
guard-scoped-to-the-wrong-unit shape.

⇒ **Every armed resume must carry an observable the task itself produces** (a sentinel, a commit,
a ticket comment). Absence of that artifact with `lastRunAt` set **is** the stall signature.

⚠ Two instrument traps, both measured today:
- **`ls` is not a registration oracle.** `delete_scheduled_task` removes the task from the
  scheduler and **leaves `SKILL.md` on disk by design.** The 3 pre-existing dirs in
  `~/.claude/scheduled-tasks/` are therefore *deleted tasks*, not orphans or a stale format —
  which fully explains 4 dirs on disk against 0 registered. **(This resolves OQ4.)**
- **The stall's own signature is in the transcript, not in the task record.** Final record is an
  `assistant tool_use:Bash` with **zero records after it and no `tool_result` anywhere in the
  file**. Evidence:
  `~/.claude/projects/-Users-mikeprasad-Projects/70ff01c6-a8ba-46f7-a626-1c608e5a4884.jsonl`.

**D8 — no new modifier word.** Nothing new to type, in any branch. Presence already carries it.
This satisfies the ruling's *"no modifier word needed"* and honours the retirement reasoning that
killed `loop` and `preflight`: a word that adds no capability does not ship.

**D9 — port scope is three files, not one.** `SKILL.md:15` claims *"`/auto` ships in the Claude
Code port only, and that is deliberate."* **False** — measured above. Each port needs its own
edit; codex is a trimmed port missing two of the defect sites.

**D10 — `/setup` owns the approval grant; `/auto` never performs it.** (Ruled by Mike,
2026-08-31.) The unattended Desktop path needs tool approvals present before a task fires (D6).
That grant is installed **once, deliberately, by `/setup`**, as a **narrow** `permissions.allow`
set covering only the Bash patterns an arc actually needs, shown to the user before it lands.

⛔ **`/auto` must never widen permissions mid-arc, in any mode, including `full`.** Silently
editing `permissions.allow` is an authority expansion of the same class D4 forbids for push and
deploy — the fact that it would make the arc work better is exactly the argument D4 already
rejects. `/auto`'s only role is to **detect and report** readiness (D6's contract line).

⚠ **Accepted cost, knowingly:** an allowlist widens standing permissions for *every* session, not
only scheduled ones. Mike accepted this over the two narrower alternatives (per-task "Run now"
capture, which cannot work when the arc creates the task unattended at 3am; and document-only,
which leaves the capability unused until manually enabled).

⚠ **Left to the plan:** which Bash patterns qualify as "narrow." This is the load-bearing detail
— an allowlist wide enough to be convenient is an allowlist that stops being a decision. It needs
its own scope pass, derived from what an arc actually calls, not from what it might.

**D11 — no grant may permit a destructive or force-overwriting operation without user approval or
an explicit stated grant.** (Ruled by Mike, 2026-09-01, verbatim: *"it should not allow destructive
or force overwrites without user approval or explicit user stated grants."*)

This is a constraint on **every** allowlist entry, present or proposed — not advice, and not
scoped to this arc's four patterns. It is stricter than D4, which forbids a *modifier* from
granting push; D11 forbids the *permission layer* from silently granting the destructive class at
all.

⛔ **Measured 2026-09-01: three already-allowlisted entries VIOLATE D11**, because each permits
arbitrary command execution and therefore the whole destructive class:

| Entry | Vector | Verified |
|---|---|---|
| `Bash(git push:*)` · `Bash(git push *)` | `--receive-pack=<cmd>` | injected marker printed |
| `Bash(git fetch:*)` | `--upload-pack=<cmd>` | injected marker printed |
| `Bash(git ls-remote *)` | `--upload-pack=<cmd>` | injected marker printed |

⇒ **D11 makes D4 enforceable rather than aspirational.** Until these are narrowed, D4 is carried by
the skill's prose alone while the permission layer grants strictly more than push.

**Remedy — NARROW the `allow` patterns; do not rely on adding `deny` rules.** Two reasons, both
measured rather than preferred:
1. A `deny` on a mid-command flag (`--upload-pack` / `--receive-pack` / `--exec`) is **unverifiable
   in-session** — settings arm at session start, so its effect cannot be observed until a fresh
   session. Shipping a security control you have not seen work is the shape Rule 36 forbids.
2. Narrowing an `allow` to an argument-bounded or literal form has **already-known semantics** — a
   literal pattern matches only that literal, so no probe is needed. `Bash(git push origin master)`
   already exists alongside `Bash(git push:*)`; the glob is what carries the vector.

⚠ **Not applied.** This is the user's own settings file and a change affects every session, not
only scheduled ones. D11 records the standard; the narrowing is presented for his approval.

---

## Defect census (per port, measured 2026-08-31)

| # | Defect | claude-code | antigravity | codex |
|---|---|---|---|---|
| 1 | `:137` "Four modes, **three** stackable modifiers" — stale; 4 groups / 8 tokens, and `:216` says "six axes" | ✅ | ✅ | ✅ |
| 2 | `:201` "`unattended` arms the resume" — contradicts D1 | ✅ | ✅ | — |
| 2b | knob 7 "the run arms its own resume" — worst placement; one knob after knob 6 says it is not gated on knob 7 | ✅ | ✅ | ✅ |
| 3 | `:404` ↔ Step 6 table self-contradiction on fresh context | ✅ | ✅ | — |
| 4 | approval-stall trap absent | **0** | **0** | **0** |
| 5 | `:15` "Claude Code port only" — false | ✅ | ✅ | ✅ |

Defects 2 / 2b are the same conflation class the July 30 spec fixed on the *duration* axis and
left standing on the *presence* axis: the normative rule was corrected, three descriptive
sentences kept the old model.

---

## Acceptance criteria

Each must be able to fail for the right reason.

- **AC1** — `grep -c 'three stackable modifiers'` = **0** in all three ports; the modifier-count
  sentence agrees with the axis count. Positive control: the phrase currently returns 1 in each.
- **AC2** — no port asserts that presence arms the resume. `grep` for `arms the resume` and
  `arms its own resume` = **0**; `SKILL.md:443`'s ungated rule is intact and unedited.
- **AC3** — no port asserts the wrapper is the *only* path to clean context; the Desktop branch
  (D4) is present and names `create_scheduled_task`.
- **AC4** — the approval-stall trap and its three fixes appear in every port carrying a Desktop
  durable path. Currently 0/3.
- **AC5** — `SKILL.md:15` states the real port set. Falsifier: the sentence still says "only".
- **AC6** — the mechanism-selection table (D2) is present, and the prose routes **both** `desktop`
  **and** `desktop-unknown` to the Desktop branch, with capability-presence named as the deciding
  authority. **Mutation (known-reachable — this is the error the first draft of D3 actually
  made): route `desktop-unknown` to the CLI branch.** A reader following the mutated prose denies
  the durable mechanism to a genuine Desktop session whose account merely failed to resolve — the
  inverse dead-end to the one the July 30 spec forbade, and invisible because it fails *safe-
  looking*: the run still arms, just session-only, and nothing errors.
- **AC7** — Step 0.5's contract line reports durable-resume availability (D6), not merely that a
  resume is armed.
- **AC8** — D2's prose-first hook still matches both verbs after the edits
  (`plugin.json` `.hooks.PreToolUse[4].matcher`) — this design adds no new guard and must not
  disarm the existing one.

---

## Open questions for the plan

- **OQ1 — ✅ CLOSED 2026-08-31 by two live probes. The form is one-shot `fireAt`, paired with
  D10's allowlist. Recurring is rejected.**

  **Method:** one-shot `fireAt` +4 min, prose-first per D2, single Bash command writing a
  distinctive sentinel, no pre-approval of any kind.
  **Result:** task fired (`lastRunAt` 08:53:15.725Z, 15 s after `fireAt`), auto-disabled, and
  **wrote nothing**. Transcript's final record is `assistant tool_use:Bash` carrying the exact
  intended command, with **zero records after it and no `tool_result` anywhere in the file**.
  ⇒ The command never executed. The 2026-06-13→15 single observation is **current and
  replicated**.
  **Rivals excluded** by the absence of *any* `tool_result`: not a failed write, not a refusal,
  not a wrong path. *(A confound in the probe's own design — the sentinel path was scoped to the
  authoring session's id — never came into play, because execution stopped earlier. Noted because
  had the stall not occurred, a write failure would have been ambiguous.)*

  ⛔ **Probe 1's result was NARROWER than first recorded, and the difference is the whole answer.**
  Its command was `printf`, which is **not** among the 161 `Bash(...)` entries in this user's
  settings. So it established *"an **unallowlisted** Bash call stalls"* — ordinary permission
  behaviour — not *"Bash is gated"*. An earlier draft of this OQ asserted the latter; **retracted.**

  **Probe 2 — the decisive one.** Same shape, same unattended one-shot `fireAt`, but the command
  was `ls -1 …` (allowlisted in **user** settings, so cwd-independent). **Result: EXECUTED.**
  `tool_result` `is_error=False` carrying the real directory listing, followed by a completing
  assistant turn. Evidence:
  `~/.claude/projects/-Users-mikeprasad-Projects/52c058ac-cd90-43d5-a467-a9de05ac635c.jsonl`
  (30 records, vs probe 1's 26 ending at an unanswered `tool_use`).
  ⚠ Verified by `tool_result` **content**, not by the mere presence of a `tool_result` — a bare
  presence check could match an unrelated block.

  ⇒ **D10's premise is VALIDATED:** a settings `permissions.allow` entry **does** satisfy a
  scheduled task's gate. An allowlisted call runs **unattended, from cold** — no human, no
  "Run now", no per-task approval.

  ⇒ **`fireAt` + D10's allowlist is the design.** No artifact to clean beyond the by-design
  `SKILL.md` residue, no 7-day expiry, no re-fire risk.

  ⛔ **Recurring-then-self-delete is REJECTED, with its reason:** the vendor text is *"tool
  approvals **granted during a run** are stored on the task and auto-applied to future runs"* —
  *granted* implies a human. With no attended run there is nothing to inherit, so recurring
  **relocates** the human step rather than removing it. It buys nothing the allowlist does not.

  ⚠ **The 2026-06-13→15 reference needs a narrow correction at source**
  (`knowledge/references/claude-code-session-and-hooks.md:57`) — narrower than an earlier draft of
  this OQ claimed. ⛔ **That draft said the reference "missed the second route, where a settings
  allowlist makes per-task approval unnecessary." FALSE — line 57 names it explicitly:** *"OR add
  the needed Bash patterns to the settings allowlist before the fire time."* Retracted.

  What the reference actually lacks is two things: (1) its **headline over-generalizes** —
  *"Unattended one-shot scheduled tasks STALL on the first tool-permission prompt"* is true only
  for a call that is **not allowlisted**, and reading the headline alone leads a designer to treat
  one-shot-ness as causal; (2) its allowlist remedy was **stated but never validated** — probe 2
  now validates it, so the line can carry a measurement instead of a suggestion.
- **OQ2 — is a one-time setup step acceptable, and where is it documented?** The unattended
  Desktop path needs approvals pre-captured once. `/setup` is the natural owner; `/auto` must not
  perform it silently.
- **OQ3 — sequencing against the in-flight runtime-gate work.**
  `2026-08-28-runtime-gate-auto-redirect-plan.md` also edits near Step 0 / the Runtime precondition
  block. Confirm no textual collision before either lands.
- **OQ4 — stale artifact cleanup.** Three registered-nowhere task dirs sit in
  `~/.claude/scheduled-tasks/`. Out of scope for the skill, but they are live evidence for D7 and
  someone should decide whether to remove them.
