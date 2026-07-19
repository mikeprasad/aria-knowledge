---
description: "Umbrella for the audit family. Routes to the sub-audits: knowledge (backlog→knowledge promotion), config (CLAUDE.md/settings drift), style (mine session-log history for revealed working-style rules), and usage (value/ROI report for your own corpus). Use '/audit' for a menu, or '/audit knowledge|config|style|usage|all' to skip it. Trigger: '/audit', '/audit usage', 'run an audit', 'audit everything'."
argument-hint: "[knowledge|config|style|all]"
allowed-tools: Read, Glob, Grep, Bash, Skill
---

# /audit — Audit Family Dispatcher

A thin umbrella over the four sub-audits. `/audit` does not scan anything itself — it resolves which sub-audit(s) the user means, then delegates to the sub-skill that owns the actual work. Think of it as a menu + router, not another audit implementation.

## Runtime Gate (per ADR-094)

**Canonical resolution:** This is the Claude Code variant. When both `plugin-claude-code` and `plugin-claude-cowork` are loaded in the same session (most common in Claude Desktop), bare `/audit` resolves to this skill — aria-knowledge (Code) is the canonical owner of all dual-port skills per ADR-094 §Part 1. The Cowork variant is namespaced-only: `/aria-cowork:audit`.

**Before Step 0:** Check that the `Bash` tool is available in this session. If `Bash` is NOT available (you are running in Claude Cowork or another non-Code runtime), surface the following notification and wait for explicit user confirmation:

> ⚠️ **Runtime mismatch — you invoked aria-knowledge's `/audit` from a non-Code runtime.**
>
> This dispatcher delegates to sub-audits that scan local files via Bash, none of which are reachable here. For the Cowork-native variants (audits reachable from the attached knowledge folder), use `/aria-cowork:audit-knowledge` or `/aria-cowork:audit-config` directly.
>
> **Proceed with this Code variant anyway?** (`y` / `n`)

Wait for an explicit reply:

- **`y` / `yes`** — Proceed with this (aria-knowledge) variant anyway despite the runtime mismatch. The user has explicitly opted in.
- **`n` / `no`** — Exit cleanly without running.
- **No response / any other reply** — Treat as "do not proceed" and exit cleanly.

**This gate applies even when `mode = auto`** per ADR-094 §Part 3. Auto mode's "implicit-yes on all gates" rule is suspended for the runtime-mismatch check — auto trusts that the user invoked the correct variant, and this gate enforces that precondition. All other auto-mode gates remain bypassed.

If `Bash` is available, proceed to Step 0.

## Step 0: Parse the Verb

`/audit` takes at most one trailing verb. Resolve it against the grammar below before doing anything else.

| Input | Resolution |
|---|---|
| `/audit` (bare, no argument) | Present the **bare-menu** (Step 1) and wait for a pick. |
| `/audit knowledge` | Delegate directly to `audit-knowledge` (Step 2). |
| `/audit config` | Delegate directly to `audit-config` (Step 2). |
| `/audit style` | Delegate directly to `audit-style` (Step 2). Style is **opt-in only** — see the note at the end of this section. |
| `/audit usage` | Delegate directly to `audit-usage` (Step 2). Usage is **opt-in only** — same note as style. |
| `/audit all` | Run all four sub-audits in sequence — knowledge → config → style → usage — each to completion, then print a combined one-line tally (Step 3). |
| anything else (unrecognized verb) | **Unknown-verb branch** — do not guess or silently fall through. List the valid verbs and stop: *"'{verb}' is not a valid /audit sub-command. Valid verbs: knowledge, config, style, usage, all. Run bare `/audit` for a menu."* |

**Style is opt-in, never routine.** `/audit style` only runs when explicitly selected — either the user types `/audit style` / `/audit all` directly, or picks "style" off the bare-menu in Step 1. It is never fired automatically by the SessionStart audit-cadence nudge the way `/audit-knowledge` and `/audit-config` can be — session-start cadence checks are a knowledge/config concern, not a style-mining concern, so `/audit style` stays a deliberate, explicit action every time.

## Step 1: Bare `/audit` — Present the Menu

When invoked with no argument, present the four options and wait for the user to pick one before doing anything else:

> **Which audit?**
> 1. `knowledge` — scan Claude memory and plans for extractable knowledge (backlog → promotion review)
> 2. `config` — check CLAUDE.md files, plugin manifests, and knowledge docs for drift and staleness
> 3. `style` — mine session-log history for revealed working-style rules (opt-in — not part of routine cadence)
> 4. `usage` — value/ROI report for your own corpus (cost + quality + trends; opt-in — not routine cadence)
> 5. `all` — run all four in sequence, then a combined tally

Do not default to any one sub-audit and do not run anything before the user picks. A bare `/audit` with no reply is a no-op — exit cleanly, nothing was scanned.

## Step 2: Delegate to a Resolved Sub-Skill

Once a verb is resolved (from Step 0's direct-invocation column or Step 1's menu pick), delegate to the matching sub-skill via the `Skill` tool, with no additional arguments — the sub-skill runs its own full step sequence (config resolution, cadence/mode determination, findings presentation, user review, promotion) exactly as it would under direct invocation:

- `knowledge` → Use the `Skill` tool to invoke `audit-knowledge`.
- `config` → Use the `Skill` tool to invoke `audit-config`.
- `style` → Use the `Skill` tool to invoke `audit-style`.
- `usage` → Use the `Skill` tool to invoke `audit-usage`.

`/audit`'s job ends at the handoff — it does not re-implement, intercept, or post-process what the sub-skill does. Whatever the sub-skill reports (findings, promotions, "nothing new to extract") is the final output of that leg.

## Step 3: `/audit all` — Sequence + Tally

`/audit all` runs the four sub-audits **in sequence, each to completion**, not in parallel and not short-circuited on an early empty result:

1. Use the `Skill` tool to invoke `audit-knowledge`. Let it run its full flow (including any user-review prompts) to completion.
2. Use the `Skill` tool to invoke `audit-config`. Let it run its full flow to completion.
3. Use the `Skill` tool to invoke `audit-style`. Let it run its full flow to completion.
4. Use the `Skill` tool to invoke `audit-usage`. Let it run its full flow to completion.

After all four finish, print a combined one-line tally summarizing what each leg did, e.g.:

> **Audit all — summary:** knowledge: 3 promoted, 1 rejected · config: 2 drift items flagged, 0 fixed · style: 1 rule candidate staged · usage: report written.

If any leg errors or the user backs out mid-leg (e.g., declines a runtime-mismatch gate), note that leg as incomplete in the tally rather than silently omitting it, and continue to the next leg — one leg's early exit doesn't cancel the other two.

## Back-Compat: Direct Sub-Skill Invocation Still Works

`/audit` is an added convenience layer, not a replacement. `/audit-knowledge` and `/audit-config` remain **directly invocable** exactly as before — nothing about adding `/audit` changes their standalone triggers, and the SessionStart audit-cadence nudge continues to name them directly (`/audit-knowledge`, `/audit-config`) rather than routing through `/audit`. `/audit-style` and `/audit-usage` are likewise directly invocable. Use `/audit knowledge|config|style|usage` when you want the umbrella's menu/tally framing; use the bare `/audit-knowledge` / `/audit-config` / `/audit-style` / `/audit-usage` forms when you want that one audit with no dispatcher layer in between. Both paths land on the same sub-skill — this is a routing convenience, not a new code path.

## Rules

- **Never silently guess a verb.** An unrecognized argument always hits the unknown-verb branch in Step 0 — list the valid verbs and stop.
- **Never auto-run style or usage.** `/audit style` and `/audit usage` fire only on explicit selection (direct invocation or menu pick) — never as part of a cadence nudge or as part of resolving a bare `/audit` without a menu pick.
- **Never reimplement sub-audit logic here.** This skill's job is parse-and-delegate; all scanning, cadence math, and promotion logic lives in the sub-skill being delegated to.
- **`/audit all` is sequential, not short-circuited.** Every leg runs to completion regardless of what the prior leg found, and every leg's outcome (including "declined" or "errored") shows up in the final tally.
