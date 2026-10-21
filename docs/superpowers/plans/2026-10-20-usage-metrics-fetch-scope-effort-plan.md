# Usage metrics, fetch-scan scope, gate effort — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix three defects found by the 2026-10-20 value-analysis refresh — `/audit usage` reproduces corrected recipes (B), the external-fetch hook scans transcripts and outlives its timeout (C), gate logs guess or omit `effort:` (D) — and backfill the author's corpus.

**Architecture:** One shared constant (`KT_CONTENT_DIRS` in `config.sh`) defines the curated knowledge dirs for both the fetch hook and the metrics emitter. The metrics emitter gains additive keys parsed with awk from gate-log frontmatter (both YAML forms). Gate skills read the documented `$CLAUDE_EFFORT` instead of guessing; a python backfill tool repairs existing logs from transcript records.

**Tech Stack:** POSIX sh + awk (scripts), python3 `-I` (backfill tool; python3 is already required by `pre-edit-check.sh`), the plugin's sh test harness (`tests/run.sh` + `helpers.sh` `assert_eq`).

**Spec:** `docs/superpowers/specs/2026-10-20-usage-metrics-fetch-scope-effort-spec.md` (branch `docs/value-analysis-2026-10-20`). Prospect: `knowledge/logs/prospect/2026-10-20-file-usage-metrics-fetch-scope-effort-spec.md`.

## Global Constraints

- **Base:** cut the execution worktree from `origin/main` **re-measured at execution start** (`git ls-remote`); at planning it was `0a9dc1e` (v2.56.2). Branch `fix/usage-fetch-effort`, worktree under the session scratchpad. Never work in the shared `aria/aria-knowledge` tree.
- Commit with `git commit -F -` heredocs (no backticks in `-m`); stage named paths; one concern per commit (B, C, D-1, D-2, ports separate).
- **No skill `description:` edits.** claude.ai upload limits (2.56.2): plugin description ≤ 500, skill description ≤ 1024 chars, no `<`/`>`/`[name]` in descriptions. Gate: `tests/repros/claude-ai-upload-limits.sh`.
- New metric keys are **additive**; `PATTERN_COUNT` and `AUDIT_PASSES` keep their names and change value (old values were wrong — spec B).
- `RULES_DIGEST_BYTES` is `unmeasured` (never `0`) when no bundled digest exists; `FIXED_COST_BYTES <n> partial` in that case.
- `effort:` value = output of `printf '%s\n' "${CLAUDE_EFFORT:-unrecorded}"`, copied verbatim; never inferred.
- Backfill marker text exactly: `# from transcript YYYY-MM-DD` and `# corrected from transcript YYYY-MM-DD; was <old>`.
- Curated dirs exactly, in this order: `approaches references projects rules guides decisions`.
- Public repo: Gate D (`plugin-claude-code/scripts/check-public-hygiene.sh`) must pass **after** the last commit (it scans commit messages `origin/main..HEAD`).
- **No push.** Branches stay local; pushing needs Mike's explicit go (standing rule, and he declined the doc push 2026-10-20).

## Review Focus

1. **A gate log with `sourcing_pass:` in inline flow form** (`{ candidates: 3, upgraded_validated: 2, no_movement: 1 }`) — must count exactly like the block form. Pinned in Task 3.
2. **A retrospect log where `bundle_marker` and `outcome` both carry `candidates:` / `no_movement:`** — a flat sum double-counts. Pinned in Task 3.
3. **A port with no bundled rules digest** (codex, cursor) — fixed cost must read `partial`, not a smaller total that looks complete. Pinned in Task 3.
4. **A host mentioned only in `intake/` or `logs/`** — the fetch hook must not cite a transcript capture as a "reference". Pinned in Task 2.
5. **A log the backfill cannot match, or matches ambiguously, or was already backfilled** — untouched, and a second run is a no-op. Pinned in Task 6.

---

### Task 0: Preconditions and baseline (no code)

- [ ] **Step 1:** `git -C <repo> fetch origin && git ls-remote origin refs/heads/main` — record the SHA. Create worktree: `git -C <repo> worktree add -b fix/usage-fetch-effort <scratchpad>/wt-fix origin/main`.
- [ ] **Step 1b: Docs branch.** In the docs worktree: commit this plan and the spec (`git commit -F -`, named paths), then `git rebase origin/main` so the docs branch is based on the same tip as the fix branch. Confirm with `git merge-base --is-ancestor origin/main HEAD`.
- [ ] **Step 2: Baseline suites, bare exit codes, output to files (never piped):** `bash plugin-claude-code/tests/run.sh > base-plugin.out 2>&1; echo $?` · each `tests/repros/*.sh` via its runner (incl. `port-generation-idempotence.sh`, `port-drift-check.sh`, `claude-ai-upload-limits.sh`) · `plugin-openai-codex/tests/run.sh` · `bats plugin-antigravity/tests/`. Record pass/fail counts (planning-time reference: plugin 362/0, repo 49/49). Any pre-existing red is recorded as baseline, not fixed here.
- [ ] **Step 3: `[EFFORT-PRE]`** — dispatch one subagent that runs only `printf '%s' "${CLAUDE_EFFORT:-unset}"` and reports the output. Record it in the D commit message. (`unset` does not block: the instruction degrades to `unrecorded`.)

### Task 1: `KT_CONTENT_DIRS` in `config.sh`

**Files:** Modify `plugin-claude-code/scripts/config.sh` (define next to `KT_CONFIG` near line 5, **outside** the `if [ -f "$KT_CONFIG" ]` block, so it exists with no config file). Test: `plugin-claude-code/tests/test-content-dirs.sh` (new).

**Interfaces:** Produces `KT_CONTENT_DIRS="approaches references projects rules guides decisions"` (space-separated, not user-overridable).

- [ ] **Step 1: Failing test** `test-content-dirs.sh`:
  - `assert_eq "content dirs constant" "approaches references projects rules guides decisions" "$(KT_CONFIG=/nonexistent sh -c '. scripts/config.sh; printf %s "$KT_CONTENT_DIRS"')"`
  - (The single-definition guard for AC-C5 lives in Task 3, which removes the last literal copy — so no commit lands on a known-red test.)
- [ ] **Step 2:** Run `bash tests/run.sh` → the constant assertion FAILS.
- [ ] **Step 3:** Add the constant.
- [ ] **Step 4:** Constant assertion passes; suite green.
- [ ] **Step 5:** Commit `feat(config): one definition of the curated knowledge dirs`.

### Task 2: C — fetch hook scans curated dirs, budget checked per dir

**Files:** Modify `plugin-claude-code/scripts/pre-external-fetch-check.sh` (the `EF_HITS=$( … )` block and the C3 budget check after it). Test: `plugin-claude-code/tests/test-external-fetch-gate.sh` (append sections).

**Interfaces:** Consumes `KT_CONTENT_DIRS`. Behaviour: for each dir in `KT_CONTENT_DIRS` that exists under `$KT_KNOWLEDGE_FOLDER`, `/usr/bin/grep -rlE --include='*.md' "$EF_PATTERN"`; then the memory dirs exactly as today; after **each** directory, if `$(( $(date +%s) - EF_START )) -ge EF_BUDGET_S`, call `ef_allow`. Remove the post-scan budget check (now redundant). Keep `/usr/bin/grep`, `-l`, `LC_ALL=C sort -u`, the max-hits cap.

- [ ] **Step 1: Failing tests** (fixtures under `$EF_TMP`, gate `on`, unique `session_id` per case):
  - **AC-C1:** host string only in `kf/intake/pre-compact-captures/x.md` and `kf/logs/prospect/y.md` → stdout has no `deny` (`assert_eq … 0 "$(ef_has deny "$out")"`).
  - **AC-C2 (positive control, must pass before AND after):** host once in `kf/references/note.md` → stdout contains `deny` and `references/note.md`.
  - **AC-C3 (non-regression, NOT a red-first test):** same fixture as C2 with `ARIA_EF_BUDGET_S=0` → no `deny`. ⚠ This
    passes on the old hook too — its post-scan check also allows when the budget is 0 — so it proves "over budget ⇒
    allow" still holds, not that the check moved inside the loop. Placement is verified by reading the diff and by
    AC-C4's timings.
  - **Ambient cap regression:** host in 9 files under `kf/references/` → no `deny` (unchanged behaviour).
- [ ] **Step 2:** Run → C1 FAILS (old hook denies citing the capture); C2, C3 and the cap test pass (controls).
- [ ] **Step 3:** Implement as in Interfaces.
- [ ] **Step 4:** All four pass; full plugin suite green.
- [ ] **Step 5: Mutation (seen red):** byte-backup the hook, replace the dir loop with the old whole-folder grep → AC-C1 must go red **with the deny message**; restore from the byte backup, `cmp`.
- [ ] **Step 6: AC-C4 on the real corpus:** time the four probe hosts with the real config (`external_fetch_gate` forced `on` via a scratch `KT_CONFIG` copy) → each < 1 s; record times.
- [ ] **Step 7:** Commit `fix(fetch-gate): scan curated knowledge, not transcripts, and bound the scan per directory`.

### Task 3: B — `usage-metrics.sh` keys

**Files:** Modify `plugin-claude-code/scripts/usage-metrics.sh`. Test: `plugin-claude-code/tests/test-usage-metrics.sh` (append).

**Interfaces:** Consumes `KT_CONTENT_DIRS` (replace the literal at line 106). Produces, one per line, `KEY value…`:
`RULES_DIGEST_BYTES <n|unmeasured>` · `USER_RULES_DIGEST_BYTES <n>` · `FIXED_COST_BYTES <n> [partial]` · `PROSPECT_YIELD <runs> <cand> <val> <fals> <nm> <nm_cap> <nm_struct>` · `PROSPECT_YIELD_MONTH <ym> <runs> <cand> <fals> <nm>` · `RETRO_BUNDLE <cand> <verified> <not_in_bundle>` · `RETRO_CLAIMS <cand> <validated> <partial> <invalidated>` · `GATE_MODEL <value> <n>` · `GATE_EFFORT <value> <n>` · `PATTERN_COUNT <n>` (all `rules/*-patterns.md`, headings `^#{2,3} \`?kebab\`?$`) · `PATTERN_LIB <file> <n>` · `AUDIT_PASSES <n>` (max ordinal, fallback `- **Date:**` count) · `AUDIT_DATED_ENTRIES <n>`.
Parsing: one awk program per log reading only the first frontmatter block (`---` … `---`); `sourcing_pass:` block form → indented `key: N` lines until dedent; inline form → split the `{ … }` body on `,` and `:`. Retrospect: `bundle_marker:` / `outcome:` sub-blocks at 2-space indent, keys at 4-space, summed separately. Model values: strip `[1m]`; missing field → `absent`.

- [ ] **Step 1: Failing tests** (fixture logs written with `printf`, each test states its hand-computed expectation):
  - **AC-B1:** `rules/aria-rules.md` fixture of 1,000 bytes beside a copy of the script → `RULES_DIGEST_BYTES 1000`, `FIXED_COST_BYTES <skills+1000>`; same script with no digest → `RULES_DIGEST_BYTES unmeasured` and `FIXED_COST_BYTES … partial`.
  - **AC-B2:** headings 3 + 2 + 1 across `retrospect-patterns.md`, `prospect-patterns.md`, `overbuild-patterns.md` (one `###`, one backticked) → `PATTERN_COUNT 6`.
  - **AC-B3:** audit log containing `12th pass`, `9th pass`, three `## ` headings, two `- **Date:**` lines → `AUDIT_PASSES 12`, `AUDIT_DATED_ENTRIES 2`; a log with no ordinal → `AUDIT_PASSES 2`.
  - **AC-B4:** two prospect logs — one block form (cand 5, val 3, fals 1, nm 1, cap 0, struct 1), one inline form (cand 3, val 2, nm 1) → `PROSPECT_YIELD 2 8 5 1 2 0 1`; a verdict-less log with a sourcing block is excluded. Retrospect nested fixture (bundle cand 4 / verified 3 / not 1; outcome cand 2 / valid 1 / partial 1 / invalid 0) → `RETRO_BUNDLE 4 3 1`, `RETRO_CLAIMS 2 1 1 0`.
  - `GATE_MODEL claude-opus-5-5 1` from `model: claude-opus-5-5[1m]`; `GATE_MODEL absent 1` for a log without the field.
  - **`HOME` isolation (the harness isolates `TMPDIR`, not `HOME`):** every new invocation runs with `HOME="$UM_TMP/home"`. `USER_RULES_DIGEST_BYTES 0` with no file; `USER_RULES_DIGEST_BYTES 250` after writing a 250-byte `$UM_TMP/home/.claude/rules/aria-user-rules.md`.
  - **Single-definition guard (AC-C5):** assert both files exist, then `grep -c 'approaches references'` on `scripts/usage-metrics.sh` and on `scripts/pre-external-fetch-check.sh` each prints `0` (read each file's count separately; a missing path also prints nothing).
- [ ] **Step 2:** Run → every new assertion FAILS (keys absent); AC-B2/B3 fail on value; the guard FAILS (usage-metrics.sh still holds the literal).
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** All pass, existing usage-metrics assertions still pass, Task 1's single-definition guard now passes.
- [ ] **Step 5: Mutation:** make the parser block-form-only → AC-B4 red on the inline log (expected `… 2 8 …`, got `1 5 …`); restore from byte backup, `cmp`.
- [ ] **Step 6:** Commit `feat(audit-usage): report errors caught, the real fixed cost, and every pattern library`.

### Task 4: B — `audit-usage` report text

**Files:** Modify `plugin-claude-code/skills/audit-usage/SKILL.md` **body only** (Step 2 sections, Step 4 summary, Rules). Test: `plugin-claude-code/tests/test-audit-usage-skill.sh` (new, text assertions).

- [ ] **Step 1: Failing test (AC-B6):** body contains `FIXED_COST_BYTES`, `PROSPECT_YIELD`, `RETRO_BUNDLE`; does **not** contain `Never assert "improving over time" unless` (the verdict-trend permission); contains the caveat phrase `not plan quality`; the `description:` line is byte-identical to `origin/main` (`git show origin/main:<path> | sed -n '/^description:/p'` vs current).
- [ ] **Step 2:** Run → fails on the new tokens.
- [ ] **Step 3:** Rewrite per spec B: TL;DR = errors caught (falsified premises, per run; fixes absent from bundle) + fixed cost `FIXED_COST_BYTES`÷4 (say "lower bound" when `partial`) + user-rules digest as opt-in; new "Errors caught" section incl. settled and addressable-settled share `(cand−nm)/(cand−nm_struct)` when the split is non-zero; verdict distribution demoted under the caveat "it measures how much the gate finds, not plan quality"; trends only on falsifications/run and premises/run under the existing ≥10/month gate; a conditions line from `GATE_MODEL`/`GATE_EFFORT`.
- [ ] **Step 4:** Test passes; `tests/repros/claude-ai-upload-limits.sh` passes; Gate B (`release.sh` budget) unchanged.
- [ ] **Step 5:** Commit `docs(audit-usage): lead with errors caught; stop reading the verdict rate as quality`.

### Task 5: D-1 — gates read `$CLAUDE_EFFORT`

**Files:** Modify `plugin-claude-code/skills/prospect/SKILL.md` (frontmatter template line `effort:` ~547) and `plugin-claude-code/skills/retrospect/SKILL.md` (~587). Test: `plugin-claude-code/tests/test-gate-effort-field.sh` (new).

- [ ] **Step 1: Failing test (AC-D1):** both skills contain `${CLAUDE_EFFORT:-unrecorded}` and `never infer`; neither contains `e.g. xhigh | high | medium`.
- [ ] **Step 2:** Run → fails.
- [ ] **Step 3:** Replace the field line with: `effort: <output of printf '%s\n' "${CLAUDE_EFFORT:-unrecorded}" — run it, copy verbatim; never infer or guess>` and one sentence after the YAML block saying the same and why (the model cannot see its effort setting; self-reports disagreed with the harness on 24% of matched logs).
- [ ] **Step 4:** Passes; plugin suite green.
- [ ] **Step 5:** Commit `fix(gates): record effort from $CLAUDE_EFFORT, never a guess` (include the `[EFFORT-PRE]` result).

### Task 6: D-2 — `backfill-gate-effort.py`

**Files:** Create `plugin-claude-code/scripts/backfill-gate-effort.py`. Test: `plugin-claude-code/tests/test-backfill-gate-effort.sh` (new; builds fake `knowledge/` + fake `projects/*/*.jsonl` under `$TMPDIR`).

**Interfaces:** `python3 -I backfill-gate-effort.py --knowledge <dir> [--transcripts <glob-root>] [--apply] [--correct-self-reported]`. Defaults: knowledge from `--knowledge` (required), transcripts root `~/.claude/projects`. Scans `*/*.jsonl` and `*/*/subagents/*.jsonl`. Match rule: an assistant record whose `message.content[]` has `type: tool_use`, `name: Write`, `input.file_path` resolving (realpath) to the log; value = that record's top-level `effort`. Exit 0; prints `FILL <path> <value>`, `CORRECT <path> <old> -> <new>`, `AMBIGUOUS <path> <v1,v2>`, `UNMATCHED <path>`, then `SUMMARY fill=N correct=N ambiguous=N unmatched=N`. Rewrites only the first frontmatter `effort:` line; leaves logs with no `effort:` line alone; treats a line already carrying `# from transcript` / `# corrected from transcript` as done.

- [ ] **Step 1: Failing tests:** fixture of 5 logs — (a) `effort: unrecorded`, matched `high`; (b) `unrecorded`, matched twice with `high` and `xhigh`; (c) `unrecorded`, no transcript; (d) `effort: medium`, matched `high`; (e) no `effort:` line, matched.
  - dry-run → `SUMMARY fill=1 correct=0 ambiguous=1 unmatched=1`; no file changed (`cksum` all 5 before/after).
  - `--apply` → (a) line == `effort: high  # from transcript <today>`; (b)(c)(d)(e) byte-identical; `diff` deletions == 1.
  - `--apply --correct-self-reported` on a fresh copy → (d) line == `effort: high  # corrected from transcript <today>; was medium`.
  - second `--apply` run → `SUMMARY fill=0 …`, no change (idempotent).
- [ ] **Step 2:** Run → fails (script absent).
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Passes.
- [ ] **Step 5: Mutation:** drop the ambiguity check → (b) gets written → red; restore, `cmp`.
- [ ] **Step 6:** Commit `feat(tools): backfill gate-log effort from the transcript that wrote it`.

### Task 7: Ports

**Files:** `plugin-openai-codex/bin/{usage-metrics.sh,pre-external-fetch-check.sh,config.sh}` + its `skills/{audit-usage,prospect,retrospect}/SKILL.md`; `plugin-cursor-template/scripts/aria/{usage-metrics.sh,pre-external-fetch-check.sh,config.sh}` + regenerate `.cursor/rules/*.mdc`; `plugin-antigravity/` via `build.sh`; `plugin-claude-cowork/skills/{prospect,retrospect}/SKILL.md`.

- [ ] **Step 1:** `usage-metrics.sh` — byte-identical across claude-code/codex/cursor at base (verified at planning): copy canonical to both. `config.sh` — apply only the `KT_CONTENT_DIRS` hunk to each port's copy (they differ elsewhere).
- [ ] **Step 2:** `pre-external-fetch-check.sh` — **hand-port the hunk** (codex differs only in a `bin/` vs `scripts/` comment at line 55; cursor differs in its header and deny shape). `diff` each port against canonical before and after: the only new differences are the ones that already existed.
- [ ] **Step 3:** Skills — codex: same edits as Tasks 4–5 (no `CLAUDE_EFFORT` in Codex → the `:-unrecorded` fallback is the honest value); cowork: `effort: unrecorded` with "Cowork has no Bash; the effort level is not readable here" (no `$CLAUDE_EFFORT` instruction).
- [ ] **Step 4:** `python3 plugin-cursor-template/scripts/port-skills-to-mdc.py`; `./plugin-antigravity/build.sh`. Assert `plugin-antigravity/bin/backfill-gate-effort.py` does **not** exist.
- [ ] **Step 5:** Port suites: codex `tests/run.sh`, antigravity tests, port idempotence repro, upload-limits repro — all match Task 0 baseline.
- [ ] **Step 6:** Commit `chore(ports): carry the usage-metrics, fetch-scope and effort fixes to every port`.

### Task 8: AC-B5 — metrics vs an independent census (real corpus)

- [ ] **Step 1:** In one shell invocation: run `usage-metrics.sh` against the real knowledge folder, then an independent python census (both `sourcing_pass` forms, nested retrospect blocks, `rules/*-patterns.md` headings). Save both outputs.
- [ ] **Step 2:** Compare `PROSPECT_YIELD`, `RETRO_BUNDLE`, `RETRO_CLAIMS`, `PATTERN_COUNT`, `AUDIT_PASSES` field by field. **Expected: equal.** Any mismatch → stop and explain (one of the two instruments is wrong); do not tune either to agree.

### Task 9: D-2 on the author's corpus (data)

- [ ] **Step 1:** Dry-run against `~/Projects/knowledge`; save output. **Expected (AC-D3):** fill ≈ 579, correct ≈ 33 (planning measurement); explain any difference (logs added since; Bash-written logs unmatched).
- [ ] **Step 2:** `--apply --correct-self-reported`.
- [ ] **Step 3:** Verify: `git -C ~/Projects/knowledge diff --stat` touches only `logs/{prospect,retrospect,preflight}/`; deletions == fills + corrections; re-run dry-run → `fill=0 correct=0`.
- [ ] **Step 4:** Commit in the knowledge repo **only the files named in the tool's `FILL`/`CORRECT` output** — never a `logs/` pathspec: at planning, `git status -s logs/` showed 150 uncommitted changes from other sessions, which a directory pathspec would sweep in. Check `git diff --cached --name-only` is empty first, then `git commit -F - -- <those paths>` with message `chore(logs): backfill gate effort from transcripts (N filled, M corrected)`. Predict the diffstat (files = N+M) before committing and compare.

### Task 10: D-3 — revise `docs/value-analysis.md` (docs branch)

- [ ] **Step 1:** Re-run the census with both `sourcing_pass` forms and **harness effort** (post-backfill frontmatter).
- [ ] **Step 2:** Revise on branch `docs/value-analysis-2026-10-20`: every yield figure (runs, candidates, falsified, settled shares, split); finding #3's matched-effort table and conclusion — rewrite to whatever the corrected data shows, including if the effort explanation fails; the TL;DR and summary lines that quote them; add a one-line note on both corrections (inline form; self-reported effort) to "What changed". Keep `docs/value-analysis.md` the only file in the commit.
- [ ] **Step 3:** Gate D after commit; `/preflight file` on the doc.

### Task 11: Close

- [ ] **Step 1:** Full suites vs Task 0 baseline (bare exits, to files); upload-limits repro; Gate D after the last commit.
- [ ] **Step 2:** Merge `fix/usage-fetch-effort` and `docs/value-analysis-2026-10-20` into **local** `main` (fast-forward/merge, no push). Remove worktrees.
- [ ] **Step 3:** `/retrospect range <base>..fix/usage-fetch-effort`.
- [ ] **Step 4:** Report to Mike: what is merged locally, what a push would publish (code + doc), and the D-3 result.
