---
description: "Is it clean/legal/consistent to ship for THIS event? Surface-audit sibling of /foundational-review: sequential probes → re-verify load-bearing claims → tiered findings (Tier 0/High/Med/Low) → phased remediation. Read-only; no anchor needed. (Cowork variant — namespaced-only; no subagents.)"
argument-hint: "<scope-root> [--for \"<event>\"]"
allowed-tools:
---

# /readiness-audit — "Is it clean / legal / consistent to ship?"

The Cowork variant. The recurring surface sibling of `/aria-cowork:foundational-review`: that one gates an irreversible decision; this one answers "is this surface ready for THIS event?" (a release, a public flip, a handoff, a demo). Read-only — it never changes the thing it audits.

## Runtime Gate (per ADR-094)

**Canonical resolution:** This is the Claude Cowork variant — namespaced-only. When both ports are loaded, bare `/readiness-audit` resolves to aria-knowledge's variant (Code is canonical owner per ADR-094 §Part 1). To reach this skill use `/aria-cowork:readiness-audit`. Do NOT match bare `/readiness-audit`.

**Before Step 0:** Check whether the `Bash` tool is available. If `Bash` IS available (Claude Code or another shell runtime), surface and wait:

> ⚠️ **Runtime mismatch — you invoked aria-cowork's `/readiness-audit` from a runtime with shell access.**
>
> This variant probes surfaces sequentially via file tools and asks you to paste anything it can't reach (no Bash, no parallel subagents, no `git diff --stat`). For the Code-native variant (parallel exploration + a real artifact `git diff --stat` check), use `/readiness-audit` (the aria-knowledge canonical).
>
> **Use `/readiness-audit` instead?** (`y` / `n`)

- **`y` / `yes`** — Invoke `readiness-audit` (bare-slash canonical) with the same args via the `Skill` tool; do not proceed here. Default-yes path.
- **`n` / `no`** — Proceed with this variant anyway (explicit opt-in).
- **No response / other** — do not proceed; exit cleanly.

**Applies even when `mode = auto`** per ADR-094 §Part 3. If `Bash` is NOT available (normal Cowork runtime), proceed to Step 0.

## When to use

- Before a launch / release / public flip / handoff / demo — a "ready for THIS event?" check.
- NOT for gating an irreversible *decision* (use `/aria-cowork:foundational-review`) and NOT for a plan pre-mortem (use `/aria-cowork:prospect`).
- No decision anchor required, but naming the **event** (`--for "public v1 launch"`) sharpens every check.

## Step 0: Inputs

```
Readiness Audit
  Scope: <surface being audited>
  For:   <the event — what "ready" is measured against>
  Reach: <what you can read directly vs. must ask the user to paste>
```

## Step 1: Bound Scope & Load Companion Format
Read the foundational-review chain doc's readiness-audit section — prefer `<knowledge_folder>/approaches/foundational-review-chain.md`, else `${CLAUDE_PLUGIN_ROOT}/skills/foundational-review/foundational-review-chain.md`. List the surfaces the event depends on (code paths, docs, licenses, configs, public copy) and bound what's in/out.

## Step 2: Per-Surface Probes (read-only, sequential)
Cowork has no parallel subagents — walk each surface in turn. For each, note what you read and what you had to ask the user to paste. **Read-only**: never edit the audited surface; never run mutating commands (you have no shell anyway).

**Over-build surface (opt-in: when the event mentions bloat/over-engineering, or always when the scope is a code repo).** Walk `rules/overbuild-patterns.md`'s ladder + smells across the surface's source (reading files in turn, asking the user to paste what you can't reach). Report candidate over-build sites — each with `file:line`, the matched smell, the failed ladder rung, and a concrete leaner alternative. Respect `aria:simplification` markers: a marked site is reported "resolved", never flagged. A site whose leaner alternative can't be named is suppressed. Read-only like every other surface here.

## Step 3: Re-Verify Every Load-Bearing Claim (the defining discipline)
The Code variant uses a controller to re-verify subagent claims; in Cowork **you are both explorer and controller**, so re-verify your own load-bearing claims before they enter findings. For each claim a finding rests on, re-open the source and confirm it — keep a short correction trail of anything that changed on re-read. A claim with no re-verified evidence cell does not get a tier.

## Step 4: Tiered Findings (fixed structure — emit every tier with a zero-state line)
```
## Tier 0 — Blockers (must fix before the event)   | <findings or "none">
## High                                            | <findings or "none">
## Medium                                          | <findings or "none">
## Low (hygiene)                                   | <findings or "none">
```
Every finding carries an **Evidence** cell with the re-verified source. A tier with nothing emits an explicit "none" line — silence is not a pass.

## Step 5: Conceptual Observations (no code change)
Things worth noting that aren't defects — framing, posture, future risk.

## Step 6: Phased Remediation Plan
Group fixes into phases. **Findings are NOT a shipping list** — say plainly which Tier 0 items actually block the named event vs. which are safe to defer.

## Step 7: End-to-End Verification Recipe
The concrete steps (the user runs them — you have no shell) to confirm readiness after remediation: what to check, what "good" looks like.

## Step 8: Gates
Surface the go/no-go decisions to the user as explicit gates. Do not declare "ready" — present the evidence and let the user decide.

## Step 9: Output & Commit
Offer to save the audit to the knowledge folder (if reachable) or emit inline. No shell — describe the commit; never run `git`.

## Step 10: Validation Gates
Verify before finishing: every tier emitted (zero-state where empty); every finding has a re-verified Evidence cell; remediation separates true blockers from deferrable; verification recipe present; gates surfaced (not auto-decided). Self-correct once, else surface the gap.
