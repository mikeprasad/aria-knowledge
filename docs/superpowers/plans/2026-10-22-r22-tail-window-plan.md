# Rule 22 tail window — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When an edit's own transcript line is not on disk after a 2 s wait, `pre-edit-check.sh` judges the transcript already written (allow/deny) instead of failing open after 40 s.

**Architecture:** The existing backward window loop is reused unchanged: in tail mode the target index is set to the end of the file with no same-message prefix, so both modes run the same loop. A per-session/agent anchor file holds the previous checked edit's `tool_use_id`; in tail mode, an anchor that is not yet on disk returns the existing loud `unknown`.

**Deviation from the spec's wording (same properties, smaller mechanism):** D2 asks to refactor the backward loop into a shared function; setting the target index to end-of-file makes both modes run the one existing loop, which removes drift by construction with no refactor. D3 says the window starts at the anchor; instead the walk keeps stopping at the nearest Edit/Write on disk (the true boundary whenever the previous edit has landed), and the anchor is used only to detect that it has not landed, returning `unknown`. AC3's property — a marker that authorised the previous edit never authorises this one — is what T3 tests.

**Tech Stack:** POSIX sh hook with an inline python3 program; repro suites in `tests/repros/*.sh` (run by `tests/run.sh`).

**Spec:** `docs/superpowers/specs/2026-10-22-r22-tail-window-when-own-line-absent-spec.md` (prospected: `knowledge/logs/prospect/2026-10-22-file-r22-tail-window-when-own-line-absent.md`, PROCEED-WITH-CHANGES, changes applied).

## Global Constraints

- Hooks stay POSIX `sh` + inline `python3`; no new dependencies.
- Default `ARIA_R22_FLUSH_WAIT_MS` = **2000** — *AMENDED to 5000 after the branch review (spec AC2 amendment); R3 and H4 follow*; the env override keeps working. Hook timeout in `plugin.json` stays **45**.
- `unknown` (loud allow) remains for: transcript missing/unreadable, python failure, anchor recorded but not on disk.
- New state file: `${TMPDIR:-/tmp}/aria-r22-lastedit-${SESSION_KEY}${AGENT_SUFFIX}`, atomic write (tmp + `mv`), Claude Code branch only (`STEP_INDEX` empty), skipped when `SESSION_KEY` is empty.
- Keep `RULE 22 ORDERING —` verbatim in `session-start-check.sh` (`test-aria-rules-digest.sh` asserts it).
- `plugin-antigravity/` is **regenerated** with `plugin-antigravity/build.sh`, never hand-edited.
- Public repo: run `plugin-claude-code/scripts/check-public-hygiene.sh` after each commit; no private identifiers (use `proj-a` style placeholders).
- Record `BASE=52426bb` (HEAD before Task 1) and use it, never `HEAD~N`, for the old-hook run.
- Work in the real checkout on `main` (a `/tmp` worktree fails unrelated suites). Commit with explicit paths (`git commit -F - -- <paths>`, heredoc message, no backticks in `-m`) — a parallel session may share the tree. No push, tag or release.

## Review Focus

1. **Retry after a deny** — the model re-issues the edit with a new `tool_use_id`; the anchor names the denied edit, whose line is on disk → normal verdict, not `unknown`.
2. **New user turn** — the previous edit was last turn; the window stops at the real user message, so a marker from last turn never authorises (tail turn-boundary test, Task 1).
3. **Rotated/compacted transcript** — the anchor names an id not in the file → `unknown` (loud), never a false allow (Task 2 test T-anchor-missing).
4. **Two edits in one response, neither on disk** — the second edit's anchor (the first) is not on disk → `unknown` for it, never a verdict from a window that reaches the first edit's marker (Task 2 test T-anchor-unflushed).
5. **Subagent vs parent anchors** — an anchor recorded by the parent is never consulted for a subagent edit and vice versa (Task 2 test T-anchor-per-agent).

---

### Task 1: Tail-mode verdict and 2 s default wait

**Files:**
- Modify: `plugin-claude-code/scripts/pre-edit-check.sh:301-323` (wait default; not-found branch), comment blocks `:25-30` and `:296-307`
- Modify: `tests/repros/r22-tool-input-marker-and-flush.sh` (H2 → H2a/H2b, new H4, new H5)
- Modify: `tests/repros/4-8-thinking-and-failopen.sh` (Case E → missing transcript; new E2)
- Modify: `tests/repros/r22-circuit-breaker.sh` (test 3 → missing transcript)
- Modify: `tests/repros/r22-carrier-side-channel.sh` (W1 sleep 2.5 → 1.0; R3 → cap == 2000)

**Interfaces:**
- Produces: python program prints `yes` / `no` / `unknown` exactly as today; in tail mode it never prints `unknown` for a readable transcript (until Task 2 adds the anchor case).

- [ ] **Step 1: Write the failing tests**

In `r22-tool-input-marker-and-flush.sh` (reuse `variant`, `late`, `check`, `timed`):
  - `H2a-never-flushed-marker-on-disk-allows` — `never.jsonl` (carrier minus last line) → `allow`
  - `H2b-never-flushed-no-marker-denies` — `plain.jsonl` minus last line → `deny`
  - `H4-tail-verdict-within-wait` — `H2b` fixture with the default wait unset (`env -u ARIA_R22_FLUSH_WAIT_MS`): verdict `deny` and elapsed < 4000 ms
  - `H5-tail-turn-boundary-denies` — carrier fixture minus last line, with a real user message line (`{"type":"user","message":{"role":"user","content":"next"}}`) inserted after the carrier Bash → `deny`
  - `H6-tail-scope-line-denies` — plain minus last line, Bash command set to `"[Rule 22 · Scope] PASS — x"` → `deny`
  - keep `H3` unchanged (differential timing still proves the wait).
In `4-8-thinking-and-failopen.sh`:
  - `E-missing-transcript-failopen-loud` — `run_warn_case` with a `transcript_path` that does not exist
  - `E2-id-absent-no-marker-denies` — existing `transcript-id-absent.jsonl`, `toolu_query_missing` → `deny`
In `r22-circuit-breaker.sh` test 3: invoke with a non-existent transcript path; assertions unchanged (sysmsg, not deny, no counter file).
In `r22-carrier-side-channel.sh`: `W1` sleeps `1.0`; `R3` asserts `cap == 2000` (rename `R3-default-cap-2000-under-timeout`).

- [ ] **Step 2: Run against the current hook — declare before running**

Run: `sh tests/repros/r22-tool-input-marker-and-flush.sh; sh tests/repros/4-8-thinking-and-failopen.sh; sh tests/repros/r22-circuit-breaker.sh; sh tests/repros/r22-carrier-side-channel.sh`
Expected RED, each for its named reason: H2a/H2b/H5/H6 → `unknown`; H4 → `unknown` after ~40 s; E2 → allow+warn; R3 → `cap=[40000]`. Expected GREEN already: E (missing transcript), breaker 3, W1 (1.0 s < 40 s). Any other result → stop and explain before Step 3.

- [ ] **Step 3: Implement**

`wait_ms` default `"2000"` (both places). In the not-found branch replace `print("unknown"); sys.exit(0)` with tail mode: `target_line_idx = len(lines)`, `target_content_idx = 0`, and guard the precise-path prefix read (`target_evt = json.loads(lines[target_line_idx])`) so it runs only when the target was found. The backward loop then starts at the last line on disk. Rewrite the two comment blocks to the measured write model (Claude Code 2.1.308: a first-tool edit's line lands after its own hook returns; spec §1).

- [ ] **Step 4: Run to verify**

Same command as Step 2. Expected: all four suites `0 failed`, bare exit 0 each.

- [ ] **Step 5: Mutation-verify**

Revert only the tail-mode lines (restore from a byte backup in the session scratchpad, then `cmp`): H2a/H2b/H4/H5/H6/E2 go red. Restore the `max(wait_ms, 0)` deadline to `0`: H4 stays green, H3 goes red. Record both.

- [ ] **Step 6: Commit**

```bash
git commit -F - -- plugin-claude-code/scripts/pre-edit-check.sh tests/repros/r22-tool-input-marker-and-flush.sh tests/repros/4-8-thinking-and-failopen.sh tests/repros/r22-circuit-breaker.sh tests/repros/r22-carrier-side-channel.sh <<'EOF'
fix(hooks): Rule 22 judges the written transcript when an edit's own line is absent
EOF
```

### Task 2: Previous-edit anchor

**Files:**
- Modify: `plugin-claude-code/scripts/pre-edit-check.sh` (beside `CARRIER_STATE` setup `:94-102`; tail branch from Task 1)
- Create: `tests/repros/r22-tail-anchor.sh`

**Interfaces:**
- Consumes: tail mode from Task 1.
- Produces: `ANCHOR_STATE` path; env `PREV_ANCHOR` passed to the python program; tail mode prints `unknown` when `PREV_ANCHOR` is non-empty, differs from `TOOL_USE_ID`, and no assistant `tool_use` block with that id is on disk by the shared deadline.

- [ ] **Step 1: Write the failing tests** in `r22-tail-anchor.sh` (fixtures derived from `tests/fixtures/transcript-cc21280-real-base.jsonl` as in the flush suite; scratch `TMPDIR`; `ARIA_R22_FLUSH_WAIT_MS=300`):
  - `T1-anchor-written` — after one check, `$TMPDIR/aria-r22-lastedit-<sid>` contains the checked `tool_use_id`
  - `T2-anchor-on-disk-normal` — anchor = `toolu_fx_1` (on disk), plain minus last line → `deny`
  - `T3-anchor-unflushed-unknown` — anchor = `toolu_fx_9` (absent), carrier minus last line → `unknown` (not `allow`: proves the anchor stops a window that would reach the carrier)
  - `T4-anchor-is-self-ignored` — anchor = `toolu_fx_3` (the current id), carrier minus last line → `allow`
  - `T5-anchor-per-agent` — anchor written for the parent key only; edit input carries `agent_id` → anchor ignored (`allow` on carrier-minus-last)
  - `T6-precise-path-ignores-anchor` — anchor = `toolu_fx_9`, full plain fixture (own line found) → `deny`

- [ ] **Step 2: Run against Task 1's hook — declare before running**
Run: `sh tests/repros/r22-tail-anchor.sh`. Expected RED: T1 (no file), T3 (`allow`). Expected GREEN: T2, T4, T5, T6.

- [ ] **Step 3: Implement** — after `CARRIER_STATE=` (same `if`): `ANCHOR_STATE="${TMPDIR:-/tmp}/aria-r22-lastedit-${SESSION_KEY}${AGENT_SUFFIX}"`; read `PREV_ANCHOR` from it (empty if absent); then write `TOOL_USE_ID` atomically when non-empty. Pass `PREV_ANCHOR` into the python env. In tail mode, before the backward loop: if the anchor condition holds, poll for its `tool_use` line until the existing `deadline`; still absent → `print("unknown")`.

- [ ] **Step 4: Run** `sh tests/repros/r22-tail-anchor.sh` and the four Task 1 suites. Expected: all `0 failed`.

- [ ] **Step 5: Mutation-verify** — drop the anchor check: T3 goes red with `allow`. Drop the self-id exclusion: T4 goes red with `unknown`. Key the anchor without `AGENT_SUFFIX`: T5 goes red.

- [ ] **Step 6: Commit** — `git add tests/repros/r22-tail-anchor.sh` first (`git commit -- <path>` rejects untracked paths), then `git commit -F - -- plugin-claude-code/scripts/pre-edit-check.sh tests/repros/r22-tail-anchor.sh`, message `fix(hooks): Rule 22 tail mode refuses a window whose previous edit is not on disk`.

### Task 3: Docs, antigravity regeneration, full gates

**Files:**
- Modify: `plugin-claude-code/template/rules/change-decision-framework.md:174` (the v2.54.0 paragraph's last sentence)
- Modify: same paragraph in `plugin-openai-codex/template/rules/`, `plugin-claude-cowork/template/rules/`, `plugin-cursor-template/knowledge/rules/` copies
- Modify: `plugin-claude-code/rules/aria-rules.md:104` and `plugin-claude-code/scripts/session-start-check.sh:222` ("Visible text still counts, but may wait up to 40 s …" sentence)
- Regenerated: `plugin-antigravity/**` via `./plugin-antigravity/build.sh`

- [ ] **Step 1:** Replace the 40 s sentence on every surface with: visible text counts only when it is already in the written transcript (an earlier response); the heredoc carrier is the reliable path; agents without Bash are judged from their own per-call transcript. Keep `RULE 22 ORDERING —`.
- [ ] **Step 2:** `/usr/bin/grep -rn -e 'up to 40 s' -e 'FLUSH_WAIT_MS", "40000' plugin-claude-code plugin-antigravity plugin-openai-codex plugin-claude-cowork plugin-cursor-template '--include=*.md' '--include=*.sh'` → expected: no hits. (A bare `40000` needle false-hits `ARIA_EMIT_RUNAWAY=40000` in `test-aria-rules-digest.sh:647`.)
- [ ] **Step 3:** `./plugin-antigravity/build.sh`, then `cmp plugin-claude-code/scripts/pre-edit-check.sh plugin-antigravity/bin/pre-edit-check.sh` → expected identical; run the port idempotence suite.
- [ ] **Step 4:** Full gates, bare exit codes read separately: `sh tests/run.sh`, `sh plugin-claude-code/tests/run.sh`, antigravity port tests. Expected: 0 failed each.
- [ ] **Step 5 (AC9 old-hook check):** the suites hardcode `HOOK` from `REPO_ROOT`, so build a scratch mirror: copy `tests/` and `plugin-claude-code/scripts/` into the session scratchpad, overwrite the mirror's `pre-edit-check.sh` with `git show 52426bb:plugin-claude-code/scripts/pre-edit-check.sh`, and run the six r22/4-8 suites there. Expected to fail exactly **H2a, H2b, H4, H5, H6, E2, R3, T1, T2, T4, T5** (traced per test: the old hook returns `unknown` whenever the own line is absent, so T3 — which expects `unknown` — passes). Any other set → stop and explain.
- [ ] **Step 6:** Commit docs + regenerated port by explicit paths; run `check-public-hygiene.sh`.

### Task 4: Historical replay (AC10) and release prep

**Files:**
- Create (scratchpad, not shipped): `replay-tail.py`
- Modify: `CHANGELOG.md` (`## 2.57.3`), `plugin-claude-code/.claude-plugin/plugin.json` (2.57.3), `plugin-antigravity/plugin.json` (hand-bump 2.57.3), `CLAUDE.md` footer

- [ ] **Step 1 (dry-run first):** for a recorded fail-open, write the transcript prefix up to (not including) the edit's own `tool_use` line to the scratchpad and run the final hook with a fake `session_id`, scratch `TMPDIR`, no anchor. Dry-run on probe B2 (session 7c872c1c, `toolu_…tYGMUU3i`) → expected `deny`; and on a heredoc-authorised edit replayed without its carrier → expected `allow`. Both must match before Step 2.
- [ ] **Step 2:** run over the fail-opens dated ≥ 2026-10-10 in the last 250 transcripts; report allow/deny/unknown counts and, for every allow, the marker line that authorised it. State the bound: no anchor and no carrier were reconstructed.
- [ ] **Step 3:** bump versions, CHANGELOG `## 2.57.3` (cause with Claude Code 2.1.308 named, the fix, the AC10 numbers, AC11 owed), footer paragraph; `./plugin-antigravity/build.sh` to sync `version.txt`. Commit by explicit paths.
- [ ] **Step 4:** stop. Push, tag, GitHub release and the AC11 live probe need Mike (install + fresh session).
