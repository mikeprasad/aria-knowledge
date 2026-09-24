# Rule 22 gate — record the carrier at PreToolUse; transcript as a waiting fallback

**Date:** 2026-09-24 · **Status:** DRAFT (SPPPE gate 1) · **Target:** aria-knowledge v2.54.0 (Claude Code branch only)
**Ruled by Mike (2026-09-24):** options 2 + 1 — carrier recorded at its own PreToolUse is the primary path; visible-text markers remain accepted via the transcript with a wait long enough to cover a streaming response.

## 1. Problem (measured 2026-09-24, session 57eacd57 + 40 recent sessions)

- **Claude Code writes a response to the transcript all at once, when the model finishes streaming it**, while each tool call — and its PreToolUse hook — runs during streaming. Controlled batch: 5 calls created +0.00 → +2.93 s all reached disk at +3.06 s. An edit's hook therefore cannot see its own line, or any marker above it in the same response, until the model finishes the rest of the response.
- **Scale:** of 2,031 Edit/Write calls, **20%** are not the last call of their response; for those, streaming remaining after the edit is p50 3.1 s · p90 9.1 s · p99 20.1 s · max 30.9 s, and **82% exceed** v2.53.3's 1.5 s wait ⇒ **~16% of all edits still fail open** on v2.53.3.
- **The hook's inputs** (docs, code.claude.com/docs/en/hooks): `session_id`, `prompt_id`, `transcript_path`, `tool_name`, `tool_input`, `tool_use_id`; `agent_id`/`agent_type` inside subagents. **No assistant prose.** `Edit`, `Write`, `Bash` **run sequentially** (docs, agent-loop "Parallel tool execution"; corroborated by probe timings). Command-hook default timeout is 10 min; the plugin sets 5 s.
- **Bash-less editors exist:** `doc-updater` (Read, Write, Edit, Grep, Glob) and `plugin-dev:agent-creator` (Write, Read). In subagent transcripts on 2.1.280 only **5%** of responses are thinking-only (1,765 responses / 106 transcripts), so visible text mostly survives there — the text channel is a viable fallback for them.

## 2. Goals and acceptance criteria

- **AC1** An edit preceded — in the same session, same agent, same prompt — by a Bash call whose input has a line-start `[Rule 22…]` marker is **allowed without reading the transcript**, even when its own tool_use line is not yet on disk.
- **AC2 (ADR 062, per-edit):** one carrier call authorises exactly **one** edit. A second edit with no new carrier falls through to the transcript path (and is denied if nothing else authorises it).
- **AC3 (turn scope):** a carrier recorded under a different `prompt_id` does not authorise, and is discarded.
- **AC4 (isolation):** a carrier in session A never authorises an edit in session B; a carrier in the parent never authorises an edit in a subagent, nor the reverse.
- **AC5 (anchoring — unchanged from 2.53.3):** a mid-line mention (`grep '[Rule 22]' f`) records nothing.
- **AC6 (fallback):** with no recorded carrier, the transcript path runs as today but waits up to **40 s** (`ARIA_R22_FLUSH_WAIT_MS`, default 40000) for the edit's own line; the plugin's hook timeout for `pre-edit-check.sh` becomes **45 s**. A text marker above an early edit in a batch is therefore found once the response is written.
- **AC7 (fail-closed boundaries):** if the edit's input carries **no `prompt_id`**, the side channel is not consulted (the transcript path decides). If the recorder cannot write, it stays silent and exits 0 — it must never block a Bash call.
- **AC8** Every new control mutation-verified red for its named reason; the old hook run against the final suite fails exactly the predicted controls.
- **AC9 (live, post-install):** a batch of `carrier, edit, carrier, edit, sleep 3` yields **zero** `could not verify` records and both edits allowed; a batch with a missing carrier yields a deny for that edit; the recorded state file carries a non-empty `prompt_id`; and a Bash-less subagent (`doc-updater`) editing with a visible-text marker is allowed via the transcript fallback. ⚠ This change adds a hook REGISTRATION and changes a timeout, so AC9 runs only after install **and** `/reload-plugins` (or a restart) — unlike 2.53.3's script-only change.

## 3. Design

**Recorder — new `bin/pre-bash-r22-carrier.sh`**, appended to the existing `PreToolUse` `Bash` hook list (runs in parallel with the three existing Bash hooks; it only writes state).
- **Fast path:** if the raw stdin does not contain the bytes `[Rule 22`, exit 0 immediately — every Bash call pays this hook, and a python start-up on each would be a real cost for no benefit.
- Otherwise parse stdin with python (json), read `session_id`, `prompt_id`, `agent_id`, `tool_use_id`, and every string value in `tool_input`.
- If any string matches `(?m)^[ \t]*\[Rule 22(\s·\s[^\]]+)?\]` → atomically write (tmp + `mv`) `${TMPDIR:-/tmp}/aria-r22-carrier-<session_key>[.<agent_key>]` containing one JSON object `{prompt_id, tool_use_id, recorded_at}`. Key sanitisation identical to the breaker's (`tr -cd 'A-Za-z0-9._-'`).
- A second carrier before the next edit **overwrites** (still one credit — ADR 062).
- No stdout, always exit 0; any exception → silent exit 0.

**Consumer — `pre-edit-check.sh`, Claude Code branch only** (the antigravity `step_index` branch is untouched):
1. Resolve the same key from the edit's `session_id` / `agent_id`. If a state file exists: read it and **delete it unconditionally** (consume or discard). If the edit has a non-empty `prompt_id` and it equals the recorded one → `COMPLIANT=yes` (breaker reset exactly as today).
2. Otherwise run the existing transcript detector (text blocks + line-start tool-input markers) with the wait raised to 40 s.
3. All remaining behaviour — path classification, signals, breaker, loud fail-open on `unknown`, deny message — unchanged.

**Why consumption is unconditional:** ADR 062 counts *edits*, not *successful* edits. The transcript window already resets at any Edit/Write tool_use whatever its outcome; deleting on every edit check is the same boundary.

## 4. Semantics preserved (ADR 036 / 062)

| Rule | Transcript semantics (today) | Side channel |
|---|---|---|
| marker precedes the edit | marker line above the tool_use | carrier's hook completes before the edit's hook (sequential execution) |
| same turn | window stops at a real user message | `prompt_id` equality |
| one marker per edit | window resets at every Edit/Write | state deleted at every edit check |
| a denied carrier still counts | its tool_use is in the transcript regardless | PreToolUse runs before permission; recorded regardless |

## 5. Alternatives considered

- **Carrier-only (option 3)** — rejected: Bash-less editing agents (`doc-updater`, `agent-creator`) could never pass; repeated denials would likely open the session breaker.
- **Long wait only (option 1)** — kept as the fallback, rejected as the sole mechanism: it keeps every edit dependent on the transcript write model, which has broken this hook three times (4.7 split messages, 2.1.280 text drop, stream-end write), and delays early edits by the remaining stream time.
- **Deny when unverifiable** — rejected: reinstates a retry on ~16% of edits.
- **Credit N edits per carrier with N markers** — rejected: more permissive than today (the transcript window resets after the first edit) and contrary to ADR 062.
- **Clear state on `UserPromptSubmit`** — not needed while `prompt_id` is present; AC7 makes its absence fail closed instead. Revisit only if AC9 shows `prompt_id` missing.

## 6. Risks

- **R1 `prompt_id` absent or differently scoped on this harness** (documented, not yet seen live). Mitigation: AC7 fail-closed + AC9 live check; the recorded file shows the value.
- **R2 subagent `session_id`/`agent_id` shape** unverified live. Mitigation: key includes `agent_id` when present; AC4 tested with fixtures; AC9 extended to one subagent edit if feasible.
- **R3 45 s hook timeout** lets a pathological long response stall one edit ≤ 40 s. Accepted: measured max 30.9 s; only affects edits with no recorded carrier. ⛔ Docs: a PreToolUse hook cancelled at its timeout "doesn't block the tool call" and its output is discarded — so a timeout is a **silent** fail-open. The 40 s cap must stay under the 45 s timeout so the hook always reaches its own **loud** fail-open first; never raise one without the other.
- **R6 system-triggered turns** (e.g. a task notification) may keep the previous `prompt_id`, while the transcript window resets at any non-tool-result user line — so the side channel can be slightly more permissive there. Accepted and stated; a second boundary mechanism is not justified without evidence it occurs.
- **R4 parallel Bash hooks** — the recorder shares the matcher with three others; it writes only its own file.
- **R5 stale file across a crash** — bounded by `prompt_id` mismatch (discarded on the next edit check).

## 7. Out of scope

Codex / Cursor / Cowork ports (different runtimes); the breaker's session-level keying for subagents; `tools/bash-discipline-check.py` (workspace, recording-only); `digest-transcript.sh` Insight capture on 2.1.280 (separate idea file).

## 8. Verification

Fixture suite for recorder + consumer (AC1–AC7), existing 12-control repro still green, full suites, port idempotence, gate D, mutation per control (AC8), live AC9 after Mike installs.
