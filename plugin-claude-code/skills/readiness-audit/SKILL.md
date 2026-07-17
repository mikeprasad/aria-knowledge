---
name: readiness-audit
description: "Audit a surface against a checklist to answer 'is it clean/legal/consistent to ship for THIS event?' — the recurring sibling of /foundational-review. Parallel exploration per surface, controller re-verification of every load-bearing claim, then tiered evidence-celled findings and a phased remediation plan (findings triage to phases, NOT a shipping list). Read-only probes only. No irreversible-decision anchor required (contrast /foundational-review). Triggers: '/readiness-audit <scope-root> --for \"<event>\"', '/audit-ready', 'readiness audit', 'release-readiness audit', 'is this ready to ship/publish/hand over', 'public-release audit'. (Code port — ADR-094.)"
argument-hint: "<scope-root> [--for \"<event: release|public-flip|handover|…>\"]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, WebFetch, WebSearch, Skill, Task
---

# /readiness-audit — "Is it clean / legal / consistent to ship?"

A checklist-against-a-surface audit that recurs, needs no irreversible-decision anchor, and answers "is it ready to ship for THIS event," not "should this shape exist." The companion format is canonicalized in the **"Companion format: the readiness audit"** section of the foundational review chain process doc (read at Step 1).

This skill is **orchestration + artifact templates only**. The format spec and the pairing contract live in the canonical process doc, which Step 1 reads. Do not reproduce them from memory.

**Sibling of `/foundational-review`** — audit = recurring, checklist-shaped, surface-anchored; chain = per-decision, verdict-shaped. When the event is a SHIP / FREEZE / PUBLIC-FLIP, the pairing contract says run BOTH: this audit for the surface, the chain for the decision (audit first — cheaper, produces the evidence base). Step 8 surfaces that pairing.

## Runtime Gate (per ADR-094)

**Canonical resolution:** This is the Claude Code variant. When both `plugin-claude-code` and `plugin-claude-cowork` are loaded in the same session (most common in Claude Desktop), bare `/readiness-audit` resolves to this skill — aria-knowledge (Code) is the canonical owner of all dual-port skills per ADR-094 §Part 1. (No Cowork variant ships yet — tracked-drift for a later parity pass.)

**Before Step 0:** Check that the `Bash` tool is available in this session. If `Bash` is NOT available (you are running in Claude Cowork or another non-Code runtime), surface the following notification and wait for explicit user confirmation:

> ⚠️ **Runtime mismatch — you invoked aria-knowledge's `/readiness-audit` from a non-Code runtime.**
>
> The audit leans on live read-only probes (`git`, `grep`, build dry-runs) and commits the report via `git`. In Cowork those degrade to manual file checks and a copy-paste commit message. No Cowork-native variant ships yet.
>
> **Proceed with this Code variant anyway?** (`y` / `n`)

Wait for an explicit reply:

- **`y` / `yes`** — Proceed with this variant; probe/commit steps degrade to manual checks + copy-paste where the tools are absent. The user has explicitly opted in.
- **`n` / `no`** — Exit cleanly without running.
- **No response / any other reply** — Treat as "do not proceed" and exit cleanly.

**This gate applies even when running unattended** per ADR-094 §Part 3.

If `Bash` is available, proceed to Step 0.

## When to use

- Before a release, a public-repo flip, a handover, or any "is this ready for X" moment that's about the *surface* (clean, legal, consistent), not the *shape*.
- As the recurring instrument — re-runnable whenever the surface changes; no decision anchor needed.

If the question is "should this shape exist / is this the right thing built the right way" before an expensive-to-undo step → use `/foundational-review`. If it's a plan about to execute → `/prospect`.

## Step 0: Inputs

Parse `<scope-root>` (first positional) and `--for "<event>"`. If thin, collect interactively:

```
Inputs:
  Scope root:   <path under audit>
  Ready for WHAT:  <the event: public release | repo public-flip | handover | v1.0 tag | …>
  Locked decisions:  <any already-decided constraints that become audit premises>
  Inherited audits:  <prior audits whose findings/claims this one re-derives, never trusts>
```

"Ready for WHAT" is the frame that makes a finding a blocker vs. a nice-to-have — get it explicit before exploring.

## Step 1: Load Canonical Companion Format & Bound Scope

1. Read the **"Companion format: the readiness audit"** section of the canonical process doc, preferring a user copy when present:
   - If `<knowledge_folder>/approaches/foundational-review-chain.md` exists (resolve `<knowledge_folder>` from `~/.claude/aria-knowledge.local.md`), read THAT.
   - Otherwise read the plugin-bundled copy at `${CLAUDE_PLUGIN_ROOT}/skills/foundational-review/foundational-review-chain.md` (always present).

   It defines the tier structure, the agent-claim-correction discipline, and the composition contract with the chain.
2. State in-scope / out-of-scope explicitly. Fence sibling workstreams ("the chain's plan owns architecture-freeze risks — not duplicated here").

## Step 2: Parallel Exploration (read-only)

Dispatch exploration agents per surface — typically:
- **source/build** — what builds, what's dead, what the artifact actually contains
- **licensing/hygiene** — license headers, secrets, internal URLs, third-party-asset rights
- **docs/tooling** — stale docs, broken references, release pipeline presence
- **over-build** (opt-in: when `--for` mentions bloat/over-engineering, or always when the scope is a code repo) — one read-only Explore agent walks `rules/overbuild-patterns.md`'s ladder + smells across the surface's source, reporting candidate over-build sites (each: `file:line`, matched smell, failed ladder rung, concrete leaner alternative). Respects `aria:simplification` markers — a marked site is reported "resolved", never flagged. Read-only per the guardrail below: it reports what it would change, never mutates a build artifact.

Use the `Task` tool (Explore agent type) per surface, in parallel. **Guardrail — read-only verification probes only.** No probe may mutate a build artifact. (A real incident: an agent "verified a build" by RUNNING it and overwrote a generated source file.) If a check would require building/running, the agent reports *what it would run + expected output*, and the controller decides whether to run it under the diff-check discipline in Step 3.

## Step 3: Controller Re-Verification (the defining discipline)

This is what separates a readiness audit from a pile of agent claims. **Re-verify every load-bearing agent claim with a direct controller-level check** before it enters the findings. In real runs, multiple agent claims were corrected by direct checks.

For each claim an agent surfaced:
- Re-derive it yourself (`Read`/`Grep`/`git`), at `file:line`.
- If it holds → it becomes a finding with a verified Evidence cell.
- If it's wrong → record the correction as a **decision-trail row**: `Agent claimed X → direct check showed Y → corrected.`
- **Inherited claims from prior audits are re-derived, never trusted** (per the composition contract — a real review corrected an inherited file misattribution and a mis-scoped variable claim).

**Artifact diff-check (mandatory).** If any verification required building or running anything, immediately run `git diff --stat` (and restore) to prove no tracked artifact was mutated. Record the diff-check result in the audit. A test-build step that can't show a clean diff is a finding against the audit itself.

## Step 4: Tiered Findings

Each finding carries a **verified Evidence cell** (citation from Step 3, not an agent assertion):

```
## Tier 0 — Blockers (must fix before the event)
| # | Finding | Evidence (file:line / probe result) | Owner |
## High
## Medium
## Low (hygiene)
```

The tier is set by the "ready for WHAT" frame from Step 0 — a stale internal URL is Tier 0 for a public flip, Low for an internal handover.

## Step 5: Conceptual Observations (no code change)

Observations worth recording that don't propose a code change — design smells, future risks, "we should decide X someday." Kept separate from findings so the remediation plan stays actionable.

## Step 6: Phased Remediation Plan

**Findings are NOT a shipping list** (cite `audit-findings-as-shipping-list-without-triage`). Triage them into phases with owners:

```
## Remediation Plan
Phase 1 (pre-event): <Tier 0 + the High items that block the event> — owners
Phase 2 (fast-follow): <remaining High + Medium> — owners
Phase 3 (backlog): <Low / hygiene> — owners
```

One owner per item. If the chain (`/foundational-review`) is also running, fence by reference: each item has exactly one owning document.

## Step 7: End-to-End Verification Recipe

The exact sequence to prove the surface is ready *after* remediation — the commands/checks + expected output a cold executor runs to confirm. This is the audit's definition-of-done.

## Step 8: Gates & Pairing

- **Gates** — for genuine decisions, surface via `AskUserQuestion`: the decision, the options, the consequence of each. Don't bake a default for a real decision.
- **Pairing** — if the event is a SHIP / FREEZE / PUBLIC-FLIP, note that the pairing contract recommends running `/foundational-review --decision "<event>"` on the *decision*, with this audit's verified findings as admissible evidence and its locked decisions as review premises. Gates from both should land in ONE gate table (the chain's spec) so nothing ships on a gate answered in only one document.

## Step 9: Output & Commit

- Write `<scope-root>/…/audit-<YYYY-MM-DD>-<event>-readiness.md` (match the project's docs convention for the location).
- Commit local (named path, no push). If `Bash`/`git` is unavailable, emit a copy-paste commit message.
- Suggest aria intake entries (insights / decisions) per the standard confirmation flow.

## Step 10: Validation Gates

Before declaring the audit complete, verify:
1. **"Ready for WHAT" stated** and used to set tier severity.
2. **Every finding has a verified Evidence cell** sourced at Step 3, not an unverified agent claim.
3. **Controller re-verification ran** — agent claims re-derived; corrections recorded as a decision trail.
4. **Artifact diff-check recorded** if any verification built/ran anything (`git diff --stat` clean + restore).
5. **Inherited claims re-derived,** never trusted from a prior audit.
6. **Findings tiered,** not flat; remediation is PHASED with one owner per item (not a shipping list).
7. **End-to-end verification recipe present.**
8. **Real decisions surfaced as gates** (AskUserQuestion), no fabricated defaults.
9. **Pairing surfaced** if the event is a ship/freeze/flip.
10. **Report committed** (named path, no push).

If any check fails, self-correct once; if it can't be closed, surface the gap explicitly.
