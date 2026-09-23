# Rule 22 pre-edit gate — tool-input marker channel (A1) + transcript flush poll (C)

**Date:** 2026-09-23 · **Target:** `plugin-claude-code/bin/pre-edit-check.sh` (Claude Code branch only) · **Version:** 2.53.3
**Ruled by Mike (2026-09-23):** A1 (accept the marker in a tool call's input) and C (fix the flush race). Do NOT file upstream.

## Measured problem (this session, 40–150 local transcripts)

1. **Claude Code 2.1.280 stopped persisting most assistant `text` blocks.** Same days, same model: 2.1.278 responses carry a text block ~85% of the time and "thinking but no text" 0%; 2.1.280 drops to 24–31% text and ~50% thinking-only. Live repro (session 57eacd57, response `…a2etNjKe`): a `[Rule 22]` marker emitted as visible prose directly above a `Write` was recorded as `thinking("") → thinking(305 chars, a paraphrase of the prose, NO marker) → tool_use:Write`, and the hook denied. The hook reads the file correctly; the marker is not in it.
2. **The hook usually runs before its own `tool_use` line is on disk.** 1,640 `could not verify` fail-opens vs 70 denials over 40 sessions, on 2.1.278 AND 2.1.280. Replaying the real hook against the final transcripts for 30 sampled cases: 30/30 now resolve, **15/30 would deny**. Hook-start minus tool_use-creation: not-found p50 0.010 s / p90 0.021 s (n=1,863); found p50 3.3 s (n=133). ⇒ the line lands asynchronously within seconds; a short bounded wait catches it.

## Criteria (checkable)

- **AC1** A marker at the start of a line inside a string input of a NON-Edit/Write `tool_use` in the window ⇒ allow. (test: G1)
- **AC2** A marker inside an **Edit/Write** input (i.e. file content) does NOT authorise — the edit cannot self-authorise. (test: G2 deny)
- **AC3** A marker merely *mentioned* mid-line in a tool input (e.g. `grep '[Rule 22]' f`) does NOT authorise. (test: G3 deny)
- **AC4** Window boundary unchanged: a tool-input marker BEFORE the previous Edit/Write does not carry over. (test: G4 deny)
- **AC5** Thinking-only marker still denies (existing D). Text-block marker still allows (existing suites).
- **AC6** Target `tool_use` line appended by another process ~300 ms after the hook starts ⇒ a real verdict (allow/deny), not `unknown`. (test: H1, two-sided: compliant fixture → allow, non-compliant → deny)
- **AC7** Line never appears ⇒ still loud fail-open after the bounded wait; wait is bounded (test asserts wall time < cap + 1 s). (existing E, run with a small cap)
- **AC8** Every new test is mutation-verified red for the right reason before being cited.

## Solutions considered

- **Marker channel:** (a) tool-input marker, line-start anchored, non-Edit/Write tools only — **chosen**; (b) accept marker in thinking — **rejected, provably defective**: the persisted thinking is a paraphrase and dropped the token in the live repro; (c) marker inside Edit input — rejected, no free field, and file content would self-authorise; (d) unanchored tool-input match — rejected, any `grep` for the marker would authorise (AC3).
- **Flush race:** (a) bounded poll re-reading the transcript, default 1500 ms, 50 ms interval, env override `ARIA_R22_FLUSH_WAIT_MS` — **chosen**; (b) evaluate the transcript tail as if the tool_use were appended — rejected: in the same race the preceding text/tool lines of the current response may also be unflushed, which manufactures false denials (the reported symptom); (c) do nothing — rejected, ~50% of fail-opens are non-compliant edits passing.
- No new temporary instrument: the harness already persists every fail-open as a `hook_success` attachment with `durationMs`, so the post-install measurement is "count of `could not verify` per edit" and their durations. Re-runnable: `scratchpad/race.py` pattern.

## Steps

1. Tests first (`tests/repros/r22-tool-input-marker-and-flush.sh` + fixtures): G1–G4, H1 (allow + deny arms), E with small cap. Run: G1/H1 must FAIL on current code for the right reason.
2. Implement in the Claude Code branch of the embedded python: (i) poll loop around the target search; (ii) collect string values from non-Edit/Write `tool_use.input` in the same window walk; match `(?m)^\s*` + MARKER on those only.
3. Docs: deny message, `template/rules/change-decision-framework.md` Ordering, `rules/aria-rules.md` RULE 22 ORDERING, `bin/session-start-check.sh` message — name the recommended carrier (`cat <<'R22'` heredoc whose first line is the marker) and why (2.1.280).
4. Mutation-verify each new control; full `tests/run.sh` + `plugin-claude-code/tests/run.sh` bare exit 0.
5. CHANGELOG 2.53.3 + version bump. Commit locally. **No push, no release, no install** — install is Mike's step (auto mode blocks self-modifying the governing hook).

## Out of scope (named)

- Other ports (antigravity/codex/cursor): different transcripts, not affected by 2.1.280.
- Parallel edits in one API response each needing their own marker (45 of 70 denials) — the per-edit rule is a recorded v2.10.6 decision, unchanged.
- Upstream report — Mike ruled not to file.
