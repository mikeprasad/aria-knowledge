# Opus 4.8 Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the aria-knowledge Claude Code and Cowork ports correct and resilient on Opus 4.8 by guarding the Rule 22 hook against the model-transition failure mode that already broke it once (4.6→4.7), fixing a planning-path classification drift, and de-versioning stale "Opus 4.6/4.7" references that ship to users.

**Architecture:** Two classes of change. (1) **Deterministic** — shell-hook regression fixtures + a one-line glob fix + markdown de-versioning, all verifiable via `tests/run.sh` and `grep`. (2) **Empirical** — a manual verification checklist for behaviors that can only be observed in a live Opus 4.8 runtime (PreCompact firing, whether 4.8 emits the Rule 22 marker as visible text vs. thinking, Cowork prose-only enforcement). The deterministic work converts the review's HIGH/MEDIUM "verify before trusting" findings into CI-catchable guards so the next model bump fails a test instead of deadlocking in the field.

**Tech Stack:** POSIX `sh` hook scripts (`plugin-claude-code/bin/`), embedded `python3` transcript parser, JSONL transcript fixtures, markdown skill/template content. Existing test harness: `tests/run.sh` → `tests/repros/*.sh` → `tests/fixtures/*.jsonl`.

**Scope note:** Per the request, this plan targets `plugin-claude-code/` (canonical) and `plugin-claude-cowork/`. Edits to canonical skills/template propagate to the cursor/codex/antigravity ports via their build scripts; re-syncing those is Task 8, marked optional-but-drift-incurring-if-skipped.

**Prospect verdict (2026-05-29):** PROCEED-WITH-CHANGES. Pre-mortem at `~/Projects/knowledge/logs/prospect/2026-05-29-file-opus-4-8-readiness.md`. One required change applied below: Task 5 Step 4 was line-scoped after the evidence pass falsified its byte-identity assumption (CC and Cowork rule files intentionally diverge: `/setup` vs `/aria-setup`). Tasks 6 & 7 intentionally DEFERRED.

**Decision required (do not silently resolve):** Task 1 locks the *current* contract — the Rule 22 marker must appear in a **visible text block**, and a marker that lands only in a **thinking block** is treated as non-compliant (deny). Whether Opus 4.8 should instead get a thinking-block fallback scan is a genuine tradeoff (auditability vs. deadlock-resistance) called out in Task 1 Step 6. The executor must surface it, not decide it.

---

## File Structure

**New files:**
- `tests/fixtures/transcript-thinking-only-marker.jsonl` — marker present only in a `thinking` block, then a `tool_use` Edit. Encodes the Opus 4.8 risk shape.
- `tests/fixtures/transcript-id-absent.jsonl` — valid transcript that does not contain the queried `tool_use_id`. Exercises the fail-open (`unknown` → allow) safety path.
- `tests/repros/4-8-thinking-and-failopen.sh` — regression suite mirroring `tests/repros/4-7-split-message.sh`, asserting deny-on-thinking-only and allow-on-id-absent.

**Modified files:**
- `plugin-claude-code/bin/pre-edit-check.sh:44-46` — broaden planning-path glob to include `docs/superpowers/plans` / `docs/superpowers/specs`.
- `plugin-claude-code/skills/help/SKILL.md:64-81` — de-version the Model Recommendations table.
- `plugin-claude-code/bin/session-start-check.sh:270-273` — de-version the injected MEMORY PATHWAY message; also comment lines `9`, `213`, `270`.
- `plugin-claude-code/bin/pre-edit-check.sh:9-15,106` — de-version code comments (4.7 → "recent Claude").
- `plugin-claude-code/template/rules/working-rules.md:254,256` — reword present-tense `Why:` to be model-generation-agnostic; keep `Origin:` historical.
- `plugin-claude-code/template/rules/change-decision-framework.md:212` — same de-versioning (historical phrasing already correct; light touch).
- `plugin-claude-cowork/template/rules/working-rules.md` + `plugin-claude-cowork/template/rules/change-decision-framework.md` — mirror Task 5 edits (shared schema surface).
- `plugin-claude-code/skills/help/SKILL.md` (codemap row) + `plugin-claude-code/skills/codemap/SKILL.md` — soften "1M context minimum" framing (Task 6, optional).
- `plugin-claude-code/.claude-plugin/plugin.json` + `plugin-claude-cowork/.claude-plugin/plugin.json` + `CHANGELOG.md` — version bump (Task 8).

---

## Task 1: Regression guard for marker-in-thinking and fail-open

**Why first:** This is the HIGH finding. The hook broke on the last model transition (v2.10.5 deadlock under 4.7's split-message harness, see `tests/repros/4-7-split-message.sh` header). A fixture suite turns "hope 4.8 behaves" into a test that fails loudly if behavior or schema drifts.

**Empirically confirmed 2026-05-29 (Opus 4.8):** piping a transcript with the `[Rule 22]` marker present only in a `thinking` block returns `"permissionDecision":"deny"` — the failure mode is reproduced, not hypothetical. The safe path (marker in a visible `text` block) was exercised live across this planning session's edits and allowed correctly every time. The risk is therefore entirely about *where Opus 4.8 chooses to place the marker*; this guard locks the contract regardless of that choice.

**Files:**
- Create: `tests/fixtures/transcript-thinking-only-marker.jsonl`
- Create: `tests/fixtures/transcript-id-absent.jsonl`
- Create: `tests/repros/4-8-thinking-and-failopen.sh`
- Test: `tests/run.sh` (existing runner, auto-discovers the new repro)

- [ ] **Step 1: Write the thinking-only fixture**

Create `tests/fixtures/transcript-thinking-only-marker.jsonl` with the marker in a `thinking` block (not `text`), then the Edit in the next assistant message:

```jsonl
{"type":"user","message":{"role":"user","content":"Please edit /tmp/test.txt"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"thinking","thinking":"[Rule 22] Low Impact — test change to /tmp/test.txt. Change — append one line. Solutions — (1) append [chosen]. Execute — Edit tool."}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_thinking_only","name":"Edit","input":{"file_path":"/tmp/test.txt","old_string":"a","new_string":"b"}}]}}
```

- [ ] **Step 2: Write the id-absent (fail-open) fixture**

Create `tests/fixtures/transcript-id-absent.jsonl` — a well-formed transcript whose assistant tool_use id does NOT match the id the test will query:

```jsonl
{"type":"user","message":{"role":"user","content":"Please edit /tmp/test.txt"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Working on it."}]}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_some_other_id","name":"Edit","input":{"file_path":"/tmp/test.txt","old_string":"a","new_string":"b"}}]}}
```

- [ ] **Step 3: Write the repro suite**

Create `tests/repros/4-8-thinking-and-failopen.sh` mirroring the structure of `tests/repros/4-7-split-message.sh`:

```sh
#!/bin/sh
# 4-8-thinking-and-failopen.sh — Opus 4.8 readiness regression.
#
# Locks two contracts that a model/harness bump could silently break:
#   D. thinking-only marker — the [Rule 22] marker appears ONLY in a thinking
#      block, never a visible text block. Contract: this is NON-compliant, so
#      the hook must DENY. Rationale: the marker is an AUDITABLE, user-visible
#      artifact; allowing a thinking-only marker would defeat its purpose.
#      (If Opus 4.8 is found to route the marker into thinking by default, the
#      FIX is a SessionStart instruction nudge or a deliberate fallback — NOT
#      silently flipping this expectation. See plan Task 1 Step 6.)
#   E. id-absent — queried tool_use_id is not in the transcript. Contract:
#      parser yields "unknown" and the hook FAILS OPEN (allow). Guards the
#      "hook error never blocks an edit" safety property.
#
# Run from any directory; resolves its own paths.

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/plugin-claude-code/bin/pre-edit-check.sh"
FIXTURES="$REPO_ROOT/tests/fixtures"

PASS=0
FAIL=0

run_case() {
  case_name="$1"
  fixture="$2"
  tool_use_id="$3"
  expect="$4"  # "allow" or "deny"

  input=$(printf '{"file_path":"/tmp/test.txt","transcript_path":"%s","tool_use_id":"%s"}' "$fixture" "$tool_use_id")
  output=$(printf '%s' "$input" | sh "$HOOK" 2>&1)
  exit_code=$?

  actual="allow"
  if printf '%s' "$output" | grep -q '"permissionDecision":"deny"'; then
    actual="deny"
  fi

  if [ "$actual" = "$expect" ] && [ "$exit_code" -eq 0 ]; then
    printf "PASS  %s (expected=%s actual=%s exit=%d)\n" "$case_name" "$expect" "$actual" "$exit_code"
    PASS=$((PASS + 1))
  else
    printf "FAIL  %s (expected=%s actual=%s exit=%d)\n" "$case_name" "$expect" "$actual" "$exit_code"
    printf "      output: %s\n" "$output"
    FAIL=$((FAIL + 1))
  fi
}

run_case "D-thinking-only-marker-denies" "$FIXTURES/transcript-thinking-only-marker.jsonl" "toolu_thinking_only" "deny"
run_case "E-id-absent-failopen-allows"   "$FIXTURES/transcript-id-absent.jsonl"            "toolu_query_missing" "allow"

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 4: Run the new suite to verify it documents current behavior**

Run: `sh tests/repros/4-8-thinking-and-failopen.sh`
Expected: `2 passed, 0 failed`. (Case D deny confirms thinking-only markers are rejected; Case E allow confirms fail-open.)

- [ ] **Step 5: Run the full suite to confirm no regression**

Run: `sh tests/run.sh`
Expected: all suites pass, including the pre-existing `4-7-split-message.sh`. Final line: `N suite(s) passed, 0 suite(s) failed`.

- [ ] **Step 6: Surface the fallback decision to the maintainer (no edit)**

Output to the user, do not auto-resolve: "Opus 4.8 readiness — Case D locks the marker-must-be-visible-text contract. If live observation (Task 7 Step 2) shows Opus 4.8 routes the Rule 22 marker into thinking by default, the right fix is a SessionStart instruction reinforcing 'emit as text, not thinking' — NOT a thinking-block fallback scan, which would make the marker non-auditable. Confirm this stance or override it before shipping."

- [ ] **Step 7: Commit**

```bash
git add tests/fixtures/transcript-thinking-only-marker.jsonl tests/fixtures/transcript-id-absent.jsonl tests/repros/4-8-thinking-and-failopen.sh
git commit -m "test(hooks): add Opus 4.8 marker-in-thinking + fail-open regression guards"
```

---

## Task 2: Fix planning-path glob drift

**Why:** The writing-plans convention and this repo's own plans live at `docs/superpowers/plans/`, but the hook's planning glob is `*/docs/specs/*|*/docs/plans/*` ([pre-edit-check.sh:45](../../plugin-claude-code/bin/pre-edit-check.sh)). It does not match `docs/superpowers/plans/`, so plan-doc writes are misclassified as full-impact edits and demand the wrong (full) Rule 22 variant. (Confirmed live: writing this very plan triggered the full-variant deny path.)

**Files:**
- Modify: `plugin-claude-code/bin/pre-edit-check.sh:44-46`
- Test: `tests/repros/4-8-thinking-and-failopen.sh` (extend) or a new planning-classification case

- [ ] **Step 1: Write a failing classification test**

Add a fixture `tests/fixtures/transcript-no-marker-planning.jsonl` (no marker at all, single Edit to a plan path) and a case to the Task 1 repro that feeds `file_path` = `/x/docs/superpowers/plans/p.md` and asserts the deny message names the **Planning** variant:

```sh
run_planning_case() {
  fixture="$1"; tool_use_id="$2"; file_path="$3"; expect_substr="$4"
  input=$(printf '{"file_path":"%s","transcript_path":"%s","tool_use_id":"%s"}' "$file_path" "$fixture" "$tool_use_id")
  output=$(printf '%s' "$input" | sh "$HOOK" 2>&1)
  if printf '%s' "$output" | grep -q "$expect_substr"; then
    printf "PASS  planning-classification (found '%s')\n" "$expect_substr"; PASS=$((PASS + 1))
  else
    printf "FAIL  planning-classification (missing '%s')\n      output: %s\n" "$expect_substr" "$output"; FAIL=$((FAIL + 1))
  fi
}
run_planning_case "$FIXTURES/transcript-no-marker-planning.jsonl" "toolu_plan_edit" "/x/docs/superpowers/plans/p.md" "Rule 22 · Planning"
```

The matching fixture `tests/fixtures/transcript-no-marker-planning.jsonl`:

```jsonl
{"type":"user","message":{"role":"user","content":"Write the plan"}}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_plan_edit","name":"Write","input":{"file_path":"/x/docs/superpowers/plans/p.md"}}]}}
```

- [ ] **Step 2: Run to verify it fails**

Run: `sh tests/repros/4-8-thinking-and-failopen.sh`
Expected: the planning-classification case FAILS — current glob yields the full-variant message, not "Rule 22 · Planning".

- [ ] **Step 3: Broaden the glob**

In `plugin-claude-code/bin/pre-edit-check.sh`, change:

```sh
case "$FILE_PATH" in
  */docs/specs/*|*/docs/plans/*) IS_PLANNING=true ;;
esac
```

to:

```sh
case "$FILE_PATH" in
  */docs/specs/*|*/docs/plans/*|*/docs/superpowers/specs/*|*/docs/superpowers/plans/*) IS_PLANNING=true ;;
esac
```

- [ ] **Step 4: Run to verify it passes**

Run: `sh tests/repros/4-8-thinking-and-failopen.sh`
Expected: planning-classification case PASSES. Then `sh tests/run.sh` → all suites pass.

- [ ] **Step 5: Commit**

```bash
git add plugin-claude-code/bin/pre-edit-check.sh tests/fixtures/transcript-no-marker-planning.jsonl tests/repros/4-8-thinking-and-failopen.sh
git commit -m "fix(hooks): recognize docs/superpowers/plans as a Rule 22 planning path"
```

---

## Task 3: De-version the /help Model Recommendations table (Claude Code)

**Why:** `plugin-claude-code/skills/help/SKILL.md:70-77` recommends "Opus 4.6 (1M context)" in 5 rows — two Opus generations stale (current is 4.8) and the "(1M context)" qualifier no longer differentiates (current Opus ships a 1M variant by default). Sonnet 4.6 references are still current — leave them. Bumping the number just re-stales next release; de-version to capability tiers instead.

**Files:**
- Modify: `plugin-claude-code/skills/help/SKILL.md:64-81`

- [ ] **Step 1: Replace versioned model names with tiers**

Replace each "Opus 4.6 (1M context)" with "Highest-capability Opus" and "Sonnet 4.6" with "Sonnet (mid-tier)". Replace the `/codemap create` row's "Opus 4.6 (1M context) minimum" with "Highest-capability Opus (large-context variant preferred)". Keep the Haiku line and the "honest test" paragraph unchanged. Add one sentence under the table: "Always pick the latest release within each tier — ARIA pins capability tiers, not version numbers, so this guidance survives model updates."

- [ ] **Step 2: Verify no stale version strings remain**

Run: `grep -nE "Opus 4\.6|Opus 4\.7|\(1M context\)" plugin-claude-code/skills/help/SKILL.md`
Expected: no output (exit 1).

- [ ] **Step 3: Verify Sonnet references untouched**

Run: `grep -c "Sonnet (mid-tier)" plugin-claude-code/skills/help/SKILL.md`
Expected: ≥ 1 (the two structured-work and low-effort rows now read as tier).

- [ ] **Step 4: Commit**

```bash
git add plugin-claude-code/skills/help/SKILL.md
git commit -m "docs(help): de-version model recommendations to capability tiers"
```

---

## Task 4: De-version the injected SessionStart message and comments

**Why:** `session-start-check.sh:273` injects "File-system memory is enhanced in 4.7" into every session — on Opus 4.8 that feeds the model a stale claim about a prior model. Comments at lines 9, 213, 270 and `pre-edit-check.sh:9-15,106` also hardcode "Opus 4.7".

**Files:**
- Modify: `plugin-claude-code/bin/session-start-check.sh` (line 273 message; comments 9, 213, 270)
- Modify: `plugin-claude-code/bin/pre-edit-check.sh` (comments 9-15, 106)

- [ ] **Step 1: De-version the injected message**

In `session-start-check.sh`, change the MEMORY PATHWAY message clause `File-system memory is enhanced in 4.7; route it through ARIA to keep the knowledge tree curated.` to `Recent Claude models have enhanced file-system memory; route it through ARIA to keep the knowledge tree curated.`

- [ ] **Step 2: De-version the comments**

In both scripts, replace standalone "Opus 4.7" / "4.7's" in comments with "recent Claude models" / "recent models'". Leave version-tagged change-history references (e.g., "v2.10.6") intact — those are accurate.

- [ ] **Step 3: Verify**

Run: `grep -nE "4\.7|Opus 4" plugin-claude-code/bin/session-start-check.sh plugin-claude-code/bin/pre-edit-check.sh`
Expected: no output (exit 1).

- [ ] **Step 4: Syntax-check the scripts (no behavior change)**

Run: `sh -n plugin-claude-code/bin/session-start-check.sh && sh -n plugin-claude-code/bin/pre-edit-check.sh && echo OK`
Expected: `OK`.

- [ ] **Step 5: Re-run the hook suite (guards against an accidental logic edit)**

Run: `sh tests/run.sh`
Expected: all suites pass.

- [ ] **Step 6: Commit**

```bash
git add plugin-claude-code/bin/session-start-check.sh plugin-claude-code/bin/pre-edit-check.sh
git commit -m "chore(hooks): de-version stale Opus 4.7 references in injected message + comments"
```

---

## Task 5: De-version version-stamped rationale in template rules (both ports)

**Why:** `working-rules.md:254` phrases a rule's `Why:` in present tense tied to "Claude Opus 4.7's literal instruction-following" — reads as describing the current model wrongly on 4.8. `change-decision-framework.md:212` references "Claude 4.7" historically (correct phrasing, light touch). These ship in BOTH ports (identical files), so edit both.

**Files:**
- Modify: `plugin-claude-code/template/rules/working-rules.md:254,256`
- Modify: `plugin-claude-code/template/rules/change-decision-framework.md:212`
- Modify: `plugin-claude-cowork/template/rules/working-rules.md` (same lines)
- Modify: `plugin-claude-cowork/template/rules/change-decision-framework.md` (same line)

- [ ] **Step 1: Reword the present-tense Why (CC)**

In `plugin-claude-code/template/rules/working-rules.md`, change `Under Claude Opus 4.7's literal instruction-following, silent resolution...` to `Under modern Claude models' literal instruction-following, silent resolution...`. Leave the `Origin:` line's "v2.10.6 release; corroborated by 2026-04-16 Anthropic best-practices guidance on 4.7's literal instruction adherence" — that is a dated historical citation and is accurate.

- [ ] **Step 2: Light-touch the framework doc (CC)**

In `plugin-claude-code/template/rules/change-decision-framework.md:212`, change `under Claude 4.7` to `under recent Claude models`. The surrounding sentence is already historical ("surfaced repeatedly in v2.10.1–v2.10.4 sessions") so no other change needed.

- [ ] **Step 3: Mirror both edits to the Cowork port**

Apply the identical two edits to `plugin-claude-cowork/template/rules/working-rules.md` and `plugin-claude-cowork/template/rules/change-decision-framework.md`.

- [ ] **Step 4: Verify the edited lines in both ports (line-scoped — NOT full-file diff)**

The two ports' rule files are **NOT** byte-identical — they intentionally diverge (Cowork uses `/aria-setup` where CC uses `/setup`; verified 2026-05-29). Do **not** assert full-file identity. Verify only that the reworded lines changed in BOTH ports, and that the intentional divergence is preserved:

```sh
# (a) stale phrasing gone from both working-rules.md files:
grep -L "Opus 4.7's literal" plugin-claude-code/template/rules/working-rules.md plugin-claude-cowork/template/rules/working-rules.md
# expected: BOTH paths printed (grep -L lists files that do NOT contain the pattern)

# (b) new phrasing present in both working-rules.md files:
grep -l "modern Claude models. literal" plugin-claude-code/template/rules/working-rules.md plugin-claude-cowork/template/rules/working-rules.md
# expected: BOTH paths printed

# (c) framework doc reworded in both:
grep -L "under Claude 4.7" plugin-claude-code/template/rules/change-decision-framework.md plugin-claude-cowork/template/rules/change-decision-framework.md
# expected: BOTH paths printed

# (d) intentional divergence preserved (sanity): CC has /setup, Cowork has /aria-setup in the managed-header comment
grep -c "/aria-setup" plugin-claude-cowork/template/rules/working-rules.md   # expected: >= 1
grep -c "diffs this file" plugin-claude-code/template/rules/working-rules.md  # expected: >= 1 (CC keeps /setup)
```
Expected: (a)(b)(c) each list both file paths; (d) confirms the pre-existing `/setup` vs `/aria-setup` divergence is intact. If any check fails, the edit missed a port — fix and re-run.

- [ ] **Step 5: Verify the present-tense stale phrasing is gone**

Run: `grep -nE "Opus 4\.7's literal|Claude 4\.7" plugin-claude-code/template/rules/*.md plugin-claude-cowork/template/rules/*.md`
Expected: no output (exit 1).

- [ ] **Step 6: Commit**

```bash
git add plugin-claude-code/template/rules/working-rules.md plugin-claude-code/template/rules/change-decision-framework.md plugin-claude-cowork/template/rules/working-rules.md plugin-claude-cowork/template/rules/change-decision-framework.md
git commit -m "docs(rules): de-version present-tense 4.7 rationale; keep historical origins"
```

---

## Task 6 (OPTIONAL — flag, don't auto-run): New-capability copy updates

**Why:** Upside, not a defect. If 1M context is now the default Opus variant, the `/codemap` anti-truncation framing over-warns. Low value, low risk; include only if the maintainer wants it. Marked optional so prospect can DEFER it cleanly.

**Files:**
- Modify: `plugin-claude-code/skills/codemap/SKILL.md` (any "1M context minimum" / truncation-warning copy)

- [ ] **Step 1: Locate the framing**

Run: `grep -niE "1m context|truncat|large context|context window" plugin-claude-code/skills/codemap/SKILL.md`
Record line numbers. If no matches, this task is a no-op — close it.

- [ ] **Step 2: Soften the copy**

Where the skill says a large-context model is *required to avoid truncation*, change to *recommended for large repos*. Do not remove chunking logic — only the model-version gating language.

- [ ] **Step 3: Verify + commit**

Run: `grep -niE "required|minimum" plugin-claude-code/skills/codemap/SKILL.md` and confirm no remaining hard model-gating.
```bash
git add plugin-claude-code/skills/codemap/SKILL.md
git commit -m "docs(codemap): soften large-context-model gating to a recommendation"
```

---

## Task 7: Manual verification checklist (NOT CI-automatable)

**Why:** These behaviors depend on a live Opus 4.8 runtime and cannot be asserted by `tests/run.sh`. Run them by hand on 4.8 and record results in the commit message or a follow-up note. This task has no code edits — it is a procedure.

- [ ] **Step 1: PreCompact fires on 4.8.** In a configured project on Opus 4.8, drive a session long enough to trigger auto-compaction. Confirm a snapshot lands in `~/Projects/knowledge/intake/pre-compact-captures/<date>_<sid>.md`. If none appears, the rolling-compaction model may not emit `PreCompact` — record this; the `/snapshot` skill becomes the reliable capture path and the SessionStart "persists via PreCompact anyway" reassurance (line 221) must be softened in a follow-up.

- [ ] **Step 2: Marker-in-text behavior on 4.8.** Make a trivial real edit in a configured repo. Confirm the `[Rule 22]` marker emits as **visible text** (not only thinking) and the edit is allowed. If the edit is denied with the marker only in thinking, the Task 1 Step 6 decision is forced — apply the SessionStart instruction reinforcement.

- [ ] **Step 3: Cowork prose-only enforcement on 4.8.** In a Cowork session on 4.8, make an edit-equivalent action and confirm 4.8 still emits the Rule 22 block when only *instructed* to (Cowork has no hook backstop). If it skips, file a follow-up to strengthen the embedded instruction.

- [ ] **Step 4: Record results.** Append a short results block to this plan file under a `## Verification Results (YYYY-MM-DD, Opus 4.8)` heading and commit it.

---

## Task 8: Version bump, CHANGELOG, downstream port re-sync

**Why:** Tasks 1-5 edit shipped surfaces (hooks, skills, template) → release-worthy per the repo's "bump version on release-worthy changes" rule.

**Files:**
- Modify: `plugin-claude-code/.claude-plugin/plugin.json` (2.20.2 → 2.20.3)
- Modify: `plugin-claude-cowork/.claude-plugin/plugin.json` (1.1.3 → 1.1.4)
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Bump canonical + cowork versions**

Set `plugin-claude-code/.claude-plugin/plugin.json` `"version": "2.20.3"` and `plugin-claude-cowork/.claude-plugin/plugin.json` `"version": "1.1.4"`.

- [ ] **Step 2: Add CHANGELOG entry**

Prepend a `## v2.20.3 / cowork v1.1.4 — 2026-05-29` entry summarizing: Opus 4.8 readiness — marker-in-thinking + fail-open regression guards, planning-path glob fix, model-recommendation + injected-message + template-rule de-versioning.

- [ ] **Step 3 (downstream ports — drift if skipped): re-sync cursor / codex / antigravity**

These ports mirror canonical skills/template. Re-run their sync/build scripts so the de-versioned content propagates:
```bash
python3 plugin-cursor-template/scripts/port-skills-to-mdc.py && ./release-cursor.sh
./release-codex.sh
./plugin-antigravity/build.sh && ./release-antigravity.sh
```
Bump each port's version sidecar to `2.20.3-*` first. If the maintainer wants to keep this PR scoped to CC+Cowork (per the plan's scope note), DEFER this step to a follow-up and record the intentional drift.

- [ ] **Step 4: Build + smoke the canonical zip**

Run: `./release.sh` and confirm the artifact builds without error.

- [ ] **Step 5: Commit**

```bash
git add plugin-claude-code/.claude-plugin/plugin.json plugin-claude-cowork/.claude-plugin/plugin.json CHANGELOG.md
git commit -m "chore(release): v2.20.3 / cowork v1.1.4 — Opus 4.8 readiness"
```

---

## Self-Review Checklist (run before handing off)

1. **Spec coverage:** Every review finding maps to a task — HIGH marker-in-thinking → Task 1; planning-glob drift → Task 2; stale /help table → Task 3; stale injected message → Task 4; stale template rules → Task 5; PreCompact + live-behavior + Cowork → Task 7; version/release → Task 8; new-capability upside → Task 6.
2. **Placeholder scan:** No TBD/TODO; every code step shows real content; every command states expected output.
3. **Cross-port:** Task 5 Step 4 verifies the *edited lines* in both ports (line-scoped, not full-file diff — the files intentionally diverge); Task 8 Step 3 handles downstream drift explicitly.
4. **Honest test boundary:** Deterministic tasks (1-6, 8) are CI-verifiable; empirical behaviors are isolated in Task 7 and labeled non-automatable.
