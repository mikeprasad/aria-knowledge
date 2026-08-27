---
description: "Umbrella for the audit family — the canonical way to run every sub-audit: '/audit knowledge' (scan memory and plans for extractable knowledge, backlog-to-promotion review), '/audit config' (CLAUDE.md/settings/docs drift and staleness), '/audit style' (mine session-log history for revealed working-style rules), '/audit usage' (value/ROI report over your own corpus), '/audit rules' (mine your distilled corrections for promotable standing rules), or '/audit all'. Trigger: '/audit', 'run an audit', 'knowledge audit', 'config audit', 'audit my style', 'audit my rules', 'usage report', 'audit everything'."
argument-hint: "[knowledge|config|style|usage|rules|all] [args...]"
allowed-tools: Read, Glob, Grep, Bash, Skill
---

# /audit — Audit Family Dispatcher

A thin umbrella over the five sub-audits. `/audit` does not scan anything itself — it resolves which
sub-audit(s) the user means, then delegates to the sub-skill that owns the actual work. Think of it
as a menu + router, not another audit implementation. **The `/audit <verb>` forms are the canonical
invocations for the whole family** (see "Canonical forms and compatibility" below).

## Runtime Gate (per ADR-094)

**Canonical resolution:** This is the Claude Code variant, and the only `/audit` dispatcher — **Cowork has no `/audit` counterpart** (excluded on its summed-description cap, a settled decision), so there is no namespaced variant to redirect to. Cowork's audit facets are the namespaced sub-skills it does ship: `/aria-cowork:audit-knowledge` and `/aria-cowork:audit-config`.

**Before Step 0:** Check that the `Bash` tool is available in this session. If `Bash` is NOT available (you are running in Claude Cowork or another non-Code runtime), surface the following notification and wait for explicit user confirmation:

> ⚠️ **Runtime mismatch — you invoked aria-knowledge's `/audit` from a non-Code runtime.**
>
> This dispatcher delegates to sub-audits that scan local files via Bash, none of which are reachable here. For the Cowork-native variants (audits reachable from the attached knowledge folder), use `/aria-cowork:audit-knowledge` or `/aria-cowork:audit-config` directly (Cowork has no dispatcher and keeps those direct forms).
>
> **Proceed with this Code variant anyway?** (`y` / `n`)

Wait for an explicit reply:

- **`y` / `yes`** — Proceed with this (aria-knowledge) variant anyway despite the runtime mismatch. The user has explicitly opted in.
- **`n` / `no`** — Exit cleanly without running.
- **No response / any other reply** — Treat as "do not proceed" and exit cleanly.

**This gate applies even when `mode = auto`** per ADR-094 §Part 3. Auto mode's "implicit-yes on all gates" rule is suspended for the runtime-mismatch check — auto trusts that the user invoked the correct variant, and this gate enforces that precondition. All other auto-mode gates remain bypassed.

If `Bash` is available, proceed to Step 0.

## Step 0: Parse the Verb (+ passthrough arguments)

`/audit` takes a **verb followed by optional arguments**. Resolve the FIRST token against the
grammar below before doing anything else. **Arguments are legal only AFTER a recognized verb** —
any remaining tokens after a recognized verb are passed through to the sub-skill unchanged (e.g.
`/audit style recent`, `/audit rules promote R1 R3`). An unrecognized first token always hits the
unknown-verb branch, exactly as before — passthrough never weakens the never-silently-guess rule.

| Input | Resolution |
|---|---|
| `/audit` (bare, no argument) | Present the **bare-menu** (Step 1) and wait for a pick. |
| `/audit knowledge [args…]` | Delegate to `audit-knowledge` with the args (Step 2). |
| `/audit config [args…]` | Delegate to `audit-config` with the args (Step 2). |
| `/audit style [args…]` | Delegate to `audit-style` with the args (Step 2). Style is **opt-in only** — see the note at the end of this section. |
| `/audit usage [args…]` | Delegate to `audit-usage` with the args (Step 2). Usage is **opt-in only** — same note as style. |
| `/audit rules [args…]` | Delegate to `audit-rules` with the args (Step 2) — e.g. `/audit rules promote R1 R3`. Rules is **opt-in only** — same note as style. |
| `/audit all` | Run all five sub-audits in sequence — knowledge → config → style → usage → rules — each to completion, then print a combined one-line tally (Step 3). Takes no passthrough args. |
| anything else (unrecognized verb) | **Unknown-verb branch** — do not guess or silently fall through. List the valid verbs and stop: *"'{verb}' is not a valid /audit sub-command. Valid verbs: knowledge, config, style, usage, rules, all. Run bare `/audit` for a menu."* |

**Style, usage, and rules are opt-in, never routine.** They run only when explicitly selected —
the user types the `/audit <verb>` form directly, or picks it off the bare-menu in Step 1. None of
the three is ever fired automatically by the SessionStart audit-cadence nudge the way `/audit
knowledge` and `/audit config` can be — session-start cadence checks are a knowledge/config
concern; style-mining, usage reporting, and rule-mining stay deliberate, explicit actions every time.

## Step 1: Bare `/audit` — Present the Menu

When invoked with no argument, present the options and wait for the user to pick one before doing anything else:

> **Which audit?**
> 1. `knowledge` — scan Claude memory and plans for extractable knowledge (backlog → promotion review)
> 2. `config` — check CLAUDE.md files, plugin manifests, and knowledge docs for drift and staleness
> 3. `style` — mine session-log history for revealed working-style rules (opt-in — not part of routine cadence)
> 4. `usage` — value/ROI report for your own corpus (cost + quality + trends; opt-in — not routine cadence)
> 5. `rules` — mine your distilled corrections for promotable standing rules (opt-in — not routine cadence)
> 6. `all` — run all five in sequence, then a combined tally

Do not default to any one sub-audit and do not run anything before the user picks. A bare `/audit` with no reply is a no-op — exit cleanly, nothing was scanned.

## Step 2: Delegate to a Resolved Sub-Skill

Once a verb is resolved (from Step 0's direct-invocation column or Step 1's menu pick), delegate to the matching sub-skill via the `Skill` tool, **passing through any trailing arguments from the invocation** — the sub-skill runs its own full step sequence (config resolution, cadence/mode determination, findings presentation, user review, promotion) exactly as it would under direct invocation:

- `knowledge` → Use the `Skill` tool to invoke `audit-knowledge` (with any passthrough args).
- `config` → Use the `Skill` tool to invoke `audit-config` (with any passthrough args).
- `style` → Use the `Skill` tool to invoke `audit-style` (with any passthrough args).
- `usage` → Use the `Skill` tool to invoke `audit-usage` (with any passthrough args).
- `rules` → Use the `Skill` tool to invoke `audit-rules` (with any passthrough args).

`/audit`'s job ends at the handoff — it does not re-implement, intercept, or post-process what the sub-skill does. Whatever the sub-skill reports (findings, promotions, "nothing new to extract") is the final output of that leg.

## Step 3: `/audit all` — Sequence + Tally

`/audit all` runs the five sub-audits **in sequence, each to completion**, not in parallel and not short-circuited on an early empty result:

1. Use the `Skill` tool to invoke `audit-knowledge`. Let it run its full flow (including any user-review prompts) to completion.
2. Use the `Skill` tool to invoke `audit-config`. Let it run its full flow to completion.
3. Use the `Skill` tool to invoke `audit-style`. Let it run its full flow to completion.
4. Use the `Skill` tool to invoke `audit-usage`. Let it run its full flow to completion.
5. Use the `Skill` tool to invoke `audit-rules`. Let it run its full flow to completion.

After all five finish, print a combined one-line tally summarizing what each leg did, e.g.:

> **Audit all — summary:** knowledge: 3 promoted, 1 rejected · config: 2 drift items flagged, 0 fixed · style: 1 rule candidate staged · usage: report written · rules: 2 proposed, staged.

If any leg errors or the user backs out mid-leg (e.g., declines a runtime-mismatch gate), note that leg as incomplete in the tally rather than silently omitting it, and continue to the next leg — one leg's early exit doesn't cancel the others.

## Canonical forms and compatibility

**The `/audit <verb>` space forms are the canonical, advertised invocations for the whole family.**
Every doc, help table, and cadence nudge names them — the SessionStart audit-cadence nudge says
`/audit knowledge` and `/audit config`.

**Compatibility aliases (never advertised):** `/audit-knowledge` · `/audit-config` · `/audit-style` · `/audit-usage` · `/audit-rules` — all still resolve.
The sub-skill files are this dispatcher's delegation targets and keep their names, but the
hyphenated forms are aliases, not separate behaviour, and are never advertised as the canonical
form (the same posture as the legacy `linear` spellings elsewhere in the family). Both paths land
on the same sub-skill.

## Rules

- **Never silently guess a verb.** An unrecognized first token always hits the unknown-verb branch in Step 0 — list the valid verbs and stop. Passthrough args exist only after a recognized verb.
- **Never auto-run style, usage, or rules.** They fire only on explicit selection (direct invocation or menu pick) — never as part of a cadence nudge or as part of resolving a bare `/audit` without a menu pick.
- **Never reimplement sub-audit logic here.** This skill's job is parse-and-delegate; all scanning, cadence math, and promotion logic lives in the sub-skill being delegated to.
- **`/audit all` is sequential, not short-circuited.** Every leg runs to completion regardless of what the prior leg found, and every leg's outcome (including "declined" or "errored") shows up in the final tally.
