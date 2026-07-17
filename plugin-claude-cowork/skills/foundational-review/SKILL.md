---
description: "Foundational review before an irreversible decision (freeze, format/schema/spec tag, public flip, major re-scope): verdict + premises + A–F + irreversibility inventory → design spec → plan → /prospect. Requires a named decision (else redirects). (Cowork variant — namespaced-only; no subagents.)"
argument-hint: "<scope-root> [--decision \"...\"] [--extend]"
allowed-tools:
---

# /foundational-review — "Is this the right thing, built the right way?"

The Cowork variant of the foundational review chain. Same genre as `/aria-cowork:prospect` (plan pre-mortem) and `/aria-cowork:retrospect` (post-ship) — but aimed at a **decision**, not a plan or a diff: run it before a one-way door (freeze, format/schema/spec tag, public API or repo flip, major re-scope, or a "should we keep building this" moment).

## Runtime Gate (per ADR-094)

**Canonical resolution:** This is the Claude Cowork variant — namespaced-only. When both `plugin-claude-code` and `plugin-claude-cowork` are loaded in the same session, bare `/foundational-review` resolves to aria-knowledge's variant — Code is the canonical owner of all dual-port skills per ADR-094 §Part 1. To reach this skill, use the namespaced form: `/aria-cowork:foundational-review`. Do NOT match bare `/foundational-review` — that belongs to aria-knowledge.

**Before Step 0:** Check whether the `Bash` tool is available in this session. If `Bash` IS available (you are running in Claude Code or another runtime with shell access), surface the following notification and wait for explicit user confirmation:

> ⚠️ **Runtime mismatch — you invoked aria-cowork's `/foundational-review` from a runtime with shell access.**
>
> This variant runs conversationally (no Bash, no parallel subagents — it reads via file tools and asks you to paste anything it can't reach). For the Code-native variant (parallel agent exploration, `git`/`gh` via Bash, automatic commit + kickoff), use `/foundational-review` (the aria-knowledge canonical).
>
> **Use `/foundational-review` instead?** (`y` / `n`)

- **`y` / `yes`** — Use the `Skill` tool to invoke `foundational-review` (the bare-slash canonical) with the same arguments. Do not proceed here; the aria-knowledge variant takes over. This is the default-yes path.
- **`n` / `no`** — Proceed with this (aria-cowork) variant anyway. The user has explicitly opted in.
- **No response / any other reply** — Treat as "do not proceed" and exit cleanly.

**This gate applies even when `mode = auto`** per ADR-094 §Part 3. If `Bash` is NOT available (normal Cowork runtime), proceed to Step 0.

## When to use

- BEFORE an irreversible decision: a version freeze, a format/schema/spec tag, a public API or repo visibility flip, a major re-scope, or a kill/keep call.
- NOT for a routine plan (use `/aria-cowork:prospect`) or a "is this surface clean to ship" check (use `/aria-cowork:readiness-audit`).

**Decision anchor required.** If the invocation names no irreversible decision (no `--decision` and none derivable from the scope), STOP and redirect: "No irreversible decision named. For a plan pre-mortem use `/aria-cowork:prospect`; for a surface readiness check use `/aria-cowork:readiness-audit`." Do not run the chain without an anchor.

## Step 0: Invocation Block

Emit an anchor the rest of the review traces to:

```
Foundational Review
  Scope:     <scope-root — repo/folder/product being reviewed>
  Decision:  <the named irreversible decision this gates>
  Reach:     <what the model can read directly (granted folders) vs must ask you to paste>
  Mode:      foundational-review [--extend]
```

If a path the review needs is outside the session's connected folders, ask the user to paste it (or `/add-dir` it) rather than guessing — fail-closed on reachability, never fabricate.

### Model Routing
This review is judgment-heavy. Recommend the highest-ceiling model available (Fable at extreme stakes, else top-tier Opus, high/xhigh effort). The executor tasks the chain emits route to a mid/high model.

## Step 1: Load the Canonical Process

Read the foundational-review chain doc. **Prefer the user's richer copy** at `<knowledge_folder>/approaches/foundational-review-chain.md` if it exists and is reachable; otherwise read the plugin-bundled copy at `${CLAUDE_PLUGIN_ROOT}/skills/foundational-review/foundational-review-chain.md`. Then survey the scope: read the project's CLAUDE.md/README/specs and enough of the structure to ground the verdict. In Cowork you read sequentially (no parallel subagents) — be explicit about what you read vs. what you inferred.

## Step 2: Findings Document

Produce the verdict-led findings (this is a fixed-structure report — emit every section; an empty section states "nothing found here," which is itself a signal):

```
# Foundational Review — <scope> — <YYYY-MM-DD>

## Verdict
<FOUNDATIONALLY SOUND | SOUND-WITH-CHANGES | RE-SCOPE | DO-NOT-PROCEED> — one paragraph, lead with the single most important reason.

## Premises
<the named assumptions the verdict rests on; mark each as verified or assumed>

## A. Problem–Solution Fit
## B. Foundational Correctness   (steelman ≥1 alternative; say why rejected)
## C. Built Right                (within the current approach)
## D. Gaps                       (smallest v-next-worthy set)
## E. Over-build                 (what to cut or freeze)
## F. Product / Portfolio Coherence

## Irreversibility Inventory
<every one-way door this decision opens or depends on; the asymmetric-cost items>

## Uncertainty Flags
<claims you could not verify in Cowork — what you'd need pasted/checked to close them>
```

## Step 3: Design Spec(s)

For each change the verdict implies, a spec section: **Decisions** (D1, D2… with the rejected alternatives preserved), **Gates** (the human decisions that block execution, labelled G-A, G-B…), **Non-goals**, and **sibling-workstream fencing** (what this must NOT disturb).

## Step 4: Plan(s)

A cold-executable plan: tasks in dependency order, each with an owner-model recommendation and acceptance criteria, written so a fresh session could execute it without this conversation's context. Mark tasks BLOCKED on a gate.

## Step 5: Compose /prospect

Run the plan through the pre-mortem lens (invoke `/aria-cowork:prospect file <plan>` or apply its discipline inline): per-step risk verdicts, simpler-alternative pass. Apply non-controversial amendments in place; surface the rest as gate items.

## Step 6: Self-Check & Kickoff

Before finalizing: re-read your own verdict for the failure modes in the chain doc (premise-not-named, irreversible-not-inventoried, alternative-not-steelmanned). Then emit a paste-ready **Executor Kickoff** — the opener a fresh session needs to execute the unblocked tasks. In Cowork, writing the findings/spec/plan files requires a granted folder; if none is reachable, emit them inline for the user to save.

## Step 7 (optional): Extension Loop `--extend`
Adds a system-design assessment + a waves roadmap on top of the chain. Skip unless requested.

## Step 8: Outputs & Intake
Offer to save the findings + spec + plan to the user's knowledge folder (if reachable) and to file any surfaced ideas to the intake backlog. Cowork has no shell — never attempt `git`; describe the commit the user should make.

## Step 9: Validation Gates
Before finishing, verify: verdict + premises present; every A–F section emitted; irreversibility inventory non-empty; each spec decision has a rejected-alternative; gates labelled; plan tasks have owners + acceptance; uncertainty flags list everything you couldn't verify. If any is missing, self-correct once, then surface the gap rather than skipping it.
