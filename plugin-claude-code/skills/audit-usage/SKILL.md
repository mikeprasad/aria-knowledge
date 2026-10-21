---
description: "Internal facet of the audit family — invoke via '/audit usage'. Value/ROI report over your own knowledge corpus (cost surface + quality distributions + trends). (Code port — ADR-094.)"
argument-hint: ""
allowed-tools: Read, Glob, Grep, Bash, Write
---

# /audit usage — Value/ROI Self-Analysis

Canonical invocation: **`/audit usage`**. The direct `/audit-usage` form is retained for compatibility and is not advertised.

Generate a value-analysis report computed against the user's OWN knowledge corpus — the user-facing counterpart to the plugin's published `docs/value-analysis.md` (which is the author's N=1 digest). Deterministic metrics come from `scripts/usage-metrics.sh`; the interpretive narrative is written here, gated on sample size.

## Runtime Gate (per ADR-094)

**Canonical resolution:** This is the Claude Code variant, and the only one — **no Cowork counterpart of this skill exists** (a settled exclusion). Do not offer or invoke one.

**Before Step 0:** Check that the `Bash` tool is available. If `Bash` is NOT available:

> ⚠️ **Runtime mismatch — you invoked aria-knowledge's `/audit usage` from a non-Code runtime.**
>
> This audit runs `scripts/usage-metrics.sh` via Bash, unavailable here.
>
> **Proceed with this Code variant anyway?** (`y` / `n`)

- **`y`** — proceed despite mismatch. **`n` / no response** — exit cleanly.

This gate applies even in auto mode per ADR-094 §Part 3.

If `Bash` is available, proceed to Step 0.

## Step 0: Resolve Config

Read `~/.claude/aria-knowledge.local.md`; extract `knowledge_folder`. If missing: stop with "aria-knowledge is not configured. Run /setup to get started."

## Step 1: Gather Metrics

Run the deterministic emitter once:

    bash ${CLAUDE_PLUGIN_ROOT}/scripts/usage-metrics.sh

Parse the labeled block (each line is `KEY value`, or `KEY subkey value` for month buckets). If the output contains `USAGE_METRICS_ERROR`, stop and tell the user their knowledge_folder is unset or missing.

If `PROSPECT_TOTAL` and `RETRO_TOTAL` are both 0: stop with "No prospect/retrospect history yet — run some /prospect and /retrospect cycles, then check back. (Cost-surface metrics are still available; say 'cost only' to see them.)" Do not fabricate a report.

## Step 2: Write the Analysis (sample-size honest)

Compose the report over the user's numbers. Lead with what the gates caught, not with how often they say "needs changes". Sections:

1. **TL;DR** — three lines. (a) **Errors caught**: falsified premises per run (`PROSPECT_YIELD` `fals` ÷ `runs`) and retrospect fixes absent from the bundle (`RETRO_BUNDLE` `not_in_bundle` of `cand`). (b) **Fixed cost**: `FIXED_COST_BYTES`÷4 tokens — when that line carries `partial`, call the figure a **lower bound** (the rules digest was unmeasured, so only skill discovery is counted). (c) **User-rules digest, opt-in**: `USER_RULES_DIGEST_BYTES`÷4 tokens, reported on its own line and never added to the fixed cost.
2. **Errors caught** — from `PROSPECT_YIELD <runs> <cand> <val> <fals> <nm> <nm_cap> <nm_struct>`: print `runs`, candidates, validated, falsified, and falsifications per run. Report the near-miss (`nm`) count and, when the split is non-zero (`nm_struct` ≠ `nm`), the **settled share** `(cand−nm)/cand` and the **addressable-settled share** `(cand−nm)/(cand−nm_struct)` — the second excludes near-misses that no step could have addressed. From `RETRO_BUNDLE <cand> <verified> <not_in_bundle>` and `RETRO_CLAIMS <cand> <validated> <partial> <invalidated>`: how many fixes were verified, how many were absent from the bundle, and the claim outcomes. Print every `n`.
3. **Cost surface** — `FIXED_COST_BYTES` (÷4 ≈ tokens; "lower bound" when `partial`), `RULES_DIGEST_BYTES` (`unmeasured` is not zero), `SKILL_DISCOVERY_BYTES`, `SKILL_COUNT`, per-session floor note: the universal fixed cost every session pays (mostly cache-eligible if the session stays warm). Then the opt-in `USER_RULES_DIGEST_BYTES` surface on its own line, labelled opt-in. Also `PATTERN_COUNT` and each `PATTERN_LIB` file with its count.
4. **Verdict distribution** — prospect table with `n = PROSPECT_TOTAL` (PWC/clean/hold) and the retrospect outcome table (`RETRO_CLOSED`/`PARTIAL`/`MIXED`/`UNRESOLVED`) plus per-fix-verdict rate. State beside the table: **it measures how much the gate finds, not plan quality** — a high needs-changes rate can mean sharp gates or weak plans, and a low one the reverse. Do not rank or grade the user on it.
5. **Trends** — month tables only for **falsifications per run** and **premises per run** (`PROSPECT_YIELD_MONTH <ym> <runs> <cand> <fals> <nm>`), **only for months whose runs ≥ 10 logs**. Any month below 10: omit and note "insufficient sample — directional only." If NO month clears 10, print "Not enough history for a trend yet (need ≥10 logs in a month)." — no table. The verdict mix is never trended.
6. **Conditions** — one line from `GATE_MODEL` and `GATE_EFFORT` (value and `n` each; `absent` means the log carried no field). These are prospect logs only; a different model or effort level changes what a gate finds, so say so before any comparison across periods.
7. **Confounds + limits** — always include the standing caveats: author-learning, the tool trains its own user, work-mix shift; and the N=1 limit (this is the user's own corpus, not a controlled study — no counterfactual proof that uncorrected plans would have shipped wrong).

Say "improving over time" only for falsifications per run or premises per run, and only when at least two months each clear the ≥10 threshold AND the direction is monotonic. Otherwise say "directional only."

## Step 3: Persist

Write `{knowledge_folder}/references/usage-analysis.md` (full rewrite each run) with frontmatter — get the timestamp via `date -u +%Y-%m-%dT%H:%M:%SZ`:

    ---
    synthesized_at: <UTC now>
    measured_at_corpus: <PROSPECT_TOTAL>/<RETRO_TOTAL>
    plugin_version: <from plugin.json if resolvable, else "unknown">
    ---

followed by the Step 2 report body. This is the one file the skill creates. Create the `references/` directory if absent.

## Step 4: Report

Print a 3-4 line inline summary (errors caught: falsified premises per run and fixes absent from the bundle; fixed-token cost from `FIXED_COST_BYTES`, "lower bound" when `partial`; the opt-in user-rules digest on its own line; the `GATE_MODEL`/`GATE_EFFORT` conditions) and "Full report written to {knowledge_folder}/references/usage-analysis.md".

## Rules

- **Opt-in only** — never fired by a cadence nudge; only explicit `/audit usage` or a menu pick.
- **Honest on small samples** — print every `n`; gate trends on ≥10/month; never fabricate on a zero corpus.
- **Errors caught lead; the verdict rate is not quality** — never present needs-changes or clean rate as plan quality, and never add `USER_RULES_DIGEST_BYTES` to the fixed cost.
- **Metrics are the script's job** — do not re-derive counts inline; `scripts/usage-metrics.sh` is the single source of truth. The skill only interprets and persists.
- **The user's corpus, not the author's** — the report reflects THIS user's logs; do not import the published doc's numbers.
