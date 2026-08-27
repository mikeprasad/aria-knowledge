---
description: "Internal facet of the audit family — invoke via '/audit usage'. Value/ROI report over your own knowledge corpus (cost surface + quality distributions + trends). (Code port — ADR-094.)"
argument-hint: ""
allowed-tools: Read, Glob, Grep, Bash, Write
---

# /audit usage — Value/ROI Self-Analysis

Canonical invocation: **`/audit usage`**. The direct `/audit-usage` form is retained for compatibility and is not advertised.

Generate a value-analysis report computed against the user's OWN knowledge corpus — the user-facing counterpart to the plugin's published `docs/value-analysis.md` (which is the author's N=1 digest). Deterministic metrics come from `bin/usage-metrics.sh`; the interpretive narrative is written here, gated on sample size.

## Runtime Gate (per ADR-094)

**Canonical resolution:** This is the Claude Code variant, and the only one — **no Cowork counterpart of this skill exists** (a settled exclusion). Do not offer or invoke one.

**Before Step 0:** Check that the `Bash` tool is available. If `Bash` is NOT available:

> ⚠️ **Runtime mismatch — you invoked aria-knowledge's `/audit usage` from a non-Code runtime.**
>
> This audit runs `bin/usage-metrics.sh` via Bash, unavailable here.
>
> **Proceed with this Code variant anyway?** (`y` / `n`)

- **`y`** — proceed despite mismatch. **`n` / no response** — exit cleanly.

This gate applies even in auto mode per ADR-094 §Part 3.

If `Bash` is available, proceed to Step 0.

## Step 0: Resolve Config

Read `~/.claude/aria-knowledge.local.md`; extract `knowledge_folder`. If missing: stop with "aria-knowledge is not configured. Run /setup to get started."

## Step 1: Gather Metrics

Run the deterministic emitter once:

    bash ${CLAUDE_PLUGIN_ROOT}/bin/usage-metrics.sh

Parse the labeled block (each line is `KEY value`, or `KEY subkey value` for month buckets). If the output contains `USAGE_METRICS_ERROR`, stop and tell the user their knowledge_folder is unset or missing.

If `PROSPECT_TOTAL` and `RETRO_TOTAL` are both 0: stop with "No prospect/retrospect history yet — run some /prospect and /retrospect cycles, then check back. (Cost-surface metrics are still available; say 'cost only' to see them.)" Do not fabricate a report.

## Step 2: Write the Analysis (sample-size honest)

Compose the report over the user's numbers. Sections:

1. **TL;DR** — one-line verdicts (needs-changes rate = `PROSPECT_PWC`/`PROSPECT_TOTAL`, clean rate, per-fix-verdict rate = `RETRO_VERDICT_FILES`/`RETRO_TOTAL`, fixed cost = `SKILL_DISCOVERY_BYTES`÷4 tokens).
2. **Cost surface** — `SKILL_DISCOVERY_BYTES` (÷4 ≈ tokens), `SKILL_COUNT`, per-session floor note; state it's the universal fixed cost every session pays (mostly cache-eligible if the session stays warm).
3. **Quality — plan rigor** — prospect distribution table with `n = PROSPECT_TOTAL`. Interpret the PWC/clean/hold split (PWC = plans that needed pre-execution correction).
4. **Quality — validation discipline** — retrospect outcome table (`RETRO_CLOSED`/`PARTIAL`/`MIXED`/`UNRESOLVED`) + per-fix-verdict rate.
5. **Trends** — month tables from `PROSPECT_MONTH` / `RETRO_MONTH` **only for months whose total ≥ 10 logs**. Any month below 10: omit from the table and note "insufficient sample — directional only." If NO month clears 10, print "Not enough history for a trend yet (need ≥10 logs in a month)." — no table.
6. **Confounds + limits** — always include the standing caveats: author-learning, the tool trains its own user, work-mix shift; and the N=1 limit (this is the user's own corpus, not a controlled study — no counterfactual proof that uncorrected plans would have shipped wrong).

Never assert "improving over time" unless at least two months each clear the ≥10 threshold AND the direction is monotonic. Otherwise say "directional only."

## Step 3: Persist

Write `{knowledge_folder}/references/usage-analysis.md` (full rewrite each run) with frontmatter — get the timestamp via `date -u +%Y-%m-%dT%H:%M:%SZ`:

    ---
    synthesized_at: <UTC now>
    measured_at_corpus: <PROSPECT_TOTAL>/<RETRO_TOTAL>
    plugin_version: <from plugin.json if resolvable, else "unknown">
    ---

followed by the Step 2 report body. This is the one file the skill creates. Create the `references/` directory if absent.

## Step 4: Report

Print a 3-4 line inline summary (needs-changes rate, clean rate, per-fix-verdict rate, fixed-token cost) and "Full report written to {knowledge_folder}/references/usage-analysis.md".

## Rules

- **Opt-in only** — never fired by a cadence nudge; only explicit `/audit usage`, `/audit all`, or menu pick.
- **Honest on small samples** — print every `n`; gate trends on ≥10/month; never fabricate on a zero corpus.
- **Metrics are the script's job** — do not re-derive counts inline; `bin/usage-metrics.sh` is the single source of truth. The skill only interprets and persists.
- **The user's corpus, not the author's** — the report reflects THIS user's logs; do not import the published doc's numbers.
