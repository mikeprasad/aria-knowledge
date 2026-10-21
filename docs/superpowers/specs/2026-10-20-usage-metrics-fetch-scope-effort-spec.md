# Spec — three fixes found by the 2026-10-20 value-analysis refresh

**Status:** DRAFT — gate chain SPPP (spec → /prospect → plan → /prospect); **Execute held** until the parallel
2.56.x release session is finished (Mike, 2026-10-20).
**Scope:** `/audit usage` recipes (B) · external-fetch hook scan scope (C) · gate `effort:` recording + backfill (D).
**Source:** findings from `docs/value-analysis.md` (2026-10-20 revision, unpushed branch `docs/value-analysis-2026-10-20`).

All measurements below were taken 2026-10-20 on the plugin author's machine (N=1).

---

## B — `/audit usage` reproduces three methods the refresh corrected

`/audit usage` = `skills/audit-usage/SKILL.md` (interprets) + `scripts/usage-metrics.sh` (counts; declared "the single
source of truth" by the skill's Rules section). Measured defects:

| # | Defect | Effect |
|---|---|---|
| B-a | Fixed cost = skill-description bytes only | Omits the working-rules digest (`rules/aria-rules.md`, 23,425 B ≈ 5,856 tok), loaded every session since v2.48.0 → reports ~half the real default cost |
| B-b | `PATTERN_COUNT` reads `rules/retrospect-patterns.md` only, `^## …$` exact | Misses `prospect-patterns.md` (347) and `overbuild-patterns.md` (6): 474 vs 831 |
| B-c | `AUDIT_PASSES` = `grep -c '^## '` on the audit log | The log is not `## `-delimited; the authoritative count is the self-numbered ordinal (129 vs the `## ` count) |
| B-d | Report leads with the needs-changes rate and permits "improving over time" when it is monotonic | The refresh showed that rate tracks gate *sensitivity*, not plan quality, in both directions |
| B-e | No yield metrics at all | The strongest evidence (premises falsified before execution, fixes absent from the bundle) is never reported to users |

### Options

1. **Extend `usage-metrics.sh` (POSIX sh + awk) and rewrite the skill's report sections.** Keeps the existing
   single-source-of-truth split and the port layout.
2. Rewrite the emitter in Python. Rejected: the script is deliberately POSIX sh (ports copy it verbatim); a language
   change is churn with no measurement gain — awk can read a frontmatter block.
3. Patch the skill prose only (tell the model to add the digest by hand). Rejected: violates the skill's own rule
   "metrics are the script's job — do not re-derive counts inline", and leaves the counts unreproducible.

### Decision — option 1

**`usage-metrics.sh` gains (keys are additive; no existing key is renamed or removed, so an older skill copy still parses):**

- `RULES_DIGEST_BYTES` — bytes of the bundled `$DIR/../rules/aria-rules.md`; **`unmeasured` when absent, never 0.**
  (Prospect, 2026-10-20: cursor delivers always-on rules through `.cursor/rules/aria-core.mdc` with `alwaysApply: true`,
  so a 0 there would be a false cost claim. Ports without a bundled digest report the gap rather than a number.)
- `USER_RULES_DIGEST_BYTES` — bytes of `$HOME/.claude/rules/aria-user-rules.md` if present, else 0 (opt-in surface;
  absence of the file genuinely means 0).
- `FIXED_COST_BYTES` — `SKILL_DISCOVERY_BYTES + RULES_DIGEST_BYTES` (the default, model-delivered fixed cost); emitted as
  `FIXED_COST_BYTES <skills-only-bytes> partial` when the digest is `unmeasured`, so the report cannot present a lower
  bound as the total.
- `PROSPECT_YIELD <runs> <candidates> <validated> <falsified> <no_movement> <nm_capability> <nm_structural>` — summed
  over prospect logs carrying both `overall_verdict:` and a `sourcing_pass:`, **in either form**: the block form and the
  inline flow form `sourcing_pass: { candidates: 3, upgraded_validated: 2, no_movement: 1 }` (37 logs on the author's
  corpus; a block-only parser silently drops them). Split fields summed only where present.
- `PROSPECT_YIELD_MONTH <ym> <runs> <candidates> <falsified> <no_movement>`.
- `RETRO_BUNDLE <candidates> <verified> <not_in_bundle>` and `RETRO_CLAIMS <candidates> <validated> <partial> <invalidated>`
  — parsed from the NESTED `bundle_marker` / `outcome` sub-blocks (never a flat sum: both carry `candidates`).
- `GATE_MODEL <model> <n>` and `GATE_EFFORT <effort> <n>` — per-value counts over prospect frontmatter (`absent` when the
  field is missing).
- `PATTERN_COUNT` — **redefined in value, not in name**: canonical kebab headings (`##`/`###`) across every
  `rules/*-patterns.md`; plus `PATTERN_LIB <file> <n>` per library. (Same key, corrected meaning — the old value was wrong.)
- `AUDIT_PASSES` — **redefined**: highest `<N>(st|nd|rd|th) pass` ordinal in the log; fall back to the `- **Date:**`
  entry count when no ordinal exists (a fresh install's log). Plus `AUDIT_DATED_ENTRIES`.

**`skills/audit-usage/SKILL.md` report changes:**

- TL;DR leads with **errors caught** (falsified premises, per run; fixes absent from the bundle) and **fixed cost =
  `FIXED_COST_BYTES`÷4**, stating the user-rules digest separately as opt-in.
- New "Errors caught" section from `PROSPECT_YIELD` / `RETRO_BUNDLE` / `RETRO_CLAIMS`, incl. settled share and — where
  the split exists — addressable settled share `(cand−nm)/(cand−nm_structural)`.
- The verdict distribution stays, **demoted** under an explicit caveat: it measures how much the gate finds, not plan
  quality. The "improving over time" permission is **removed**; trends are reported on falsifications/run and
  premises/run only, under the existing ≥10-runs-per-month gate.
- A "conditions" line from `GATE_MODEL` / `GATE_EFFORT` (so a user sees when their own model/effort mix changed).

## C — external-fetch hook scans the whole knowledge folder and outlives its timeout

Measured (whole folder vs the six curated content dirs `approaches references projects rules guides decisions`):

| Host | Whole folder | Curated dirs |
|---|---|---|
| a payments API | 58 files · 7.9 s | 2 files · 0.31 s |
| a CLI hooks reference | 14 files · 19.4 s | 6 files · 0.31 s |
| a UI framework | 13 files · 18.8 s | 3 files · 0.30 s |
| a web framework | 10 files · 16.3 s | 0 files · 0.30 s |

The hook is registered with a 5 s timeout; its own 4 s budget check runs **after** the scan, so it bounds nothing. 2.1 GB
folder, 1.5 GB of it `intake/` (retained transcript captures), 50 MB `logs/`. Two defects, not one:

- **C-a performance** — scans exceed the timeout → hook cancelled → silent fail-open.
- **C-b semantics** — the hook's message says "a recorded local **reference** already covers this surface". Transcript
  captures and gate logs are not references; they also push real hosts over the 8-hit ambient cap (58 vs 2), so even a
  fast scan of the whole folder would stay silent where curated coverage exists.

### Options

1. **Scope the scan to the curated content dirs (+ the memory dirs it already scans).** Fixes both defects.
2. Exclude `intake/` and `logs/` by `--exclude-dir`. Rejected: a denylist admits every new top-level dir by default (the
   same failure mode this workspace has hit with `.env*`); the allowlist is the definition that matches the message.
3. Build an index. Rejected for now: 0.3 s does not need one; revisit if curated dirs alone approach the budget.
4. Wrap the scan in a watchdog (background grep + kill). Rejected as primary fix (it bounds cost but keeps C-b); kept
   as a cheap secondary guard in the form below.

### Decision — option 1, plus a per-dir budget check

- Scan `approaches references projects rules guides decisions` under the knowledge folder (each only if present), then the
  memory dirs as today.
- Move the budget check **inside** the loop: after each directory, if elapsed ≥ `EF_BUDGET_S`, allow. This bounds the scan
  at directory granularity so growth of one curated dir cannot silently re-create C-a.
- **Single source of truth for the curated-dir list:** define it once in `config.sh` (`KT_CONTENT_DIRS`) and use it from
  both the hook and `usage-metrics.sh` (which today hard-codes the same six). Rule 38 — two copies of one list drift.

## D — gate logs mostly record effort as `unrecorded`, and the rest is partly guessed

- `effort:` reads `unrecorded` on 64% of split-era prospect runs; the skill asks the model to fill it, and the model cannot
  see its own effort setting.
- **The recorded values are not reliable either.** Matched against the harness-recorded `effort` on the transcript record
  of the `Write` that created each log: 140 matched, **33 disagree (24%)**. The harness value agrees with the documented
  `$CLAUDE_EFFORT` in this session (both `high`) — one sample, a bound not a proof.
- Claude Code documents `CLAUDE_EFFORT`: *"Set automatically in Bash tool subprocesses and hook commands to the effort
  level in effect when the subprocess starts … Only set when the current model supports the effort parameter."*
  (code.claude.com/docs/en/env-vars; available since v2.1.128.)
- 1,105 existing logs carry `unrecorded`; 579 match a surviving transcript record unambiguously (0 ambiguous); values
  high 502 · xhigh 62 · medium 15.

### Options

1. **Skills read `$CLAUDE_EFFORT` at write time via Bash; never self-infer.** Plus a backfill tool for existing logs.
2. A PostToolUse hook that stamps effort into gate logs after they are written. Rejected: Mike's standing ruling is no
   new pre/post-edit hook checks; and option 1 needs no hook.
3. Read effort from the transcript inside the skill. Rejected: the documented env var is simpler and is the interface
   Claude Code supports; the transcript field is undocumented.

### Decision — option 1

- **D-1 skills.** In `prospect` and `retrospect` SKILL.md, the `effort:` field instruction becomes: run
  `printf '%s\n' "${CLAUDE_EFFORT:-unrecorded}"` and copy the output verbatim; **never infer or guess it**; `unrecorded`
  when the variable is unset (non-Claude-Code runtimes, or a model without effort support).
- **D-2 backfill tool** `scripts/backfill-gate-effort.py` (python3, already a plugin dependency via `pre-edit-check.sh`):
  - For each `logs/{prospect,retrospect,preflight}/*.md`, find transcript records (`~/.claude/projects/*/*.jsonl` and
    `*/subagents/*.jsonl`) whose `Write` tool call targeted that path; take that record's `effort`.
  - **Dry-run by default**; prints per-file proposals and a summary. `--apply` writes.
  - Only fills `effort: unrecorded`. With `--correct-self-reported`, also replaces a recorded value that disagrees with
    the harness record. Every rewritten line carries a trailing marker:
    `effort: high  # from transcript 2026-10-xx` / `# corrected from transcript 2026-10-xx; was medium`.
  - Never writes when the match is ambiguous (>1 distinct effort for one file) or absent.
  - Logs without an `effort:` line (pre-v2.48.0) are **left alone** — adding a field changes the schema of old logs; out of
    scope.
- **D-3 analysis follow-through.** After the backfill runs on the author's corpus, re-run finding #3 of
  `docs/value-analysis.md` on harness-recorded effort and revise the doc on its branch. The current matched-effort claim
  rests on self-reported values that are wrong ~24% of the time. **Also re-derive every yield figure in the doc** with a
  parser that reads both `sourcing_pass` forms — the published census skipped the 37 inline-form logs (2,028 runs with a
  verdict, 1,990 counted).

## Ports

| Port | B | C | D-1 |
|---|---|---|---|
| plugin-claude-code (canonical) | edit | edit | edit |
| plugin-antigravity | regenerate via `build.sh` (verify `bin/` translation) | regenerate | regenerate (env var unset there → `unrecorded`) |
| plugin-openai-codex | hand-sync script + skill | hand-sync hook | hand-sync; no `CLAUDE_EFFORT` → `unrecorded` |
| plugin-cursor-template | hand-sync `scripts/aria/` copies; recompile `.mdc` via `port-skills-to-mdc.py` | hand-sync | via generator |
| plugin-claude-cowork | no `audit-usage` | no hook | skills-only, no Bash → instruct `unrecorded` |

D-2 ships in `plugin-claude-code` only (it reads Claude Code transcripts). `plugin-antigravity/build.sh` copies only
`scripts/*.sh` (its loop at line 200), so a `.py` tool is never carried over and no skip-list entry is needed — the
plan asserts its absence from the regenerated port instead. *(Corrected 2026-10-20 during planning: the spec prospect
had marked this premise falsified and prescribed a skip-list entry; reading the copy loop showed the glob is `*.sh`.)*

## Acceptance criteria

Each criterion names the check that must be **seen red** against the pre-fix code before it counts.

- **AC-B1** `usage-metrics.sh` on a fixture folder emits `RULES_DIGEST_BYTES` equal to `wc -c` of the bundled digest and
  `FIXED_COST_BYTES` = sum. *Red:* old script emits no such key.
- **AC-B2** `PATTERN_COUNT` on a fixture with headings in three `rules/*-patterns.md` files equals their sum. *Red:* old
  script counts one file.
- **AC-B3** `AUDIT_PASSES` on a fixture log whose highest ordinal differs from its `## ` count reports the ordinal.
- **AC-B4** `PROSPECT_YIELD` / `RETRO_BUNDLE` / `RETRO_CLAIMS` on fixtures equal hand-computed sums, including a nested
  retrospect block where a flat sum would double-count `candidates`.
- **AC-B5** Run on the author's real corpus, the new keys equal an **independent python census run the same minute**
  that reads both `sourcing_pass` forms. ⛔ Not the published refresh's figures: those came from a parser that skipped
  the 37 inline-form logs, so matching them would certify the blind spot. Any mismatch is a finding to explain, never a
  tolerance to absorb.
- **AC-B6** The skill text no longer permits "improving over time" from the verdict series; the TL;DR names errors caught
  and `FIXED_COST_BYTES`.
- **AC-C1** On a fixture whose only mention of a host is under `intake/`, the hook emits nothing (allow). *Red:* old hook
  denies with a pointer to the capture.
- **AC-C2** On a fixture where the host is mentioned once under `references/`, the hook emits the deny naming that file
  (positive control — must pass before and after).
- **AC-C3** With `ARIA_EF_BUDGET_S=0` the hook allows without completing the scan (budget check inside the loop).
- **AC-C4** On the author's corpus, the four probe hosts complete in < 1 s each.
- **AC-C5** `usage-metrics.sh` and the hook read the curated-dir list from `config.sh` (one definition; a test fails if a
  second literal copy reappears in either file).
- **AC-D1** Both gate skills instruct reading `$CLAUDE_EFFORT` and forbid inferring; a test asserts the instruction text
  in the canonical skills. **`[EFFORT-PRE]`:** before relying on it, a dispatched subagent runs
  `printf '%s' "${CLAUDE_EFFORT:-unset}"` — the docs name Bash subprocesses and hooks, not subagents. If it reads `unset`
  there, the instruction still degrades honestly to `unrecorded`; record the result either way.
- **AC-D2** Backfill on a fixture (fake transcripts + logs) proposes exactly the expected fills; `--apply` changes only the
  `effort:` line (diff deletes = number of filled lines); ambiguous and unmatched files untouched; re-running is a no-op.
- **AC-D3** Run on the author's corpus in dry-run first; the proposed counts match this spec's measurement (579 fills,
  33 corrections among matched self-reported values) or the difference is explained.
- **AC-all** Existing suites stay green (`plugin-claude-code/tests` run.sh, `tests/repros`, port idempotence, codex port
  suite); Gate B (skill budget — the audit-usage description is unchanged) and Gate D pass.

## Out of scope

- `/preflight`'s frontmatter (no `effort:`/`verdict:` contract yet — separate item).
- Adding `effort:` to logs that predate the field.
- Publishing `docs/value-analysis.md` (Mike: not now).
- Releasing — this spec ends at merged-to-local-main; versioning/release is a separate decision.
