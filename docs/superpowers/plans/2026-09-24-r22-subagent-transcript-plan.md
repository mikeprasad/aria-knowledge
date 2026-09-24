# Plan — v2.54.1: subagent transcript + per-agent breakers (SPPPE gate 3)

**Spec:** `docs/superpowers/specs/2026-09-24-r22-subagent-transcript-spec.md` (gate 2 PROCEED-WITH-CHANGES, applied). **Ends:** full release (push, annotated tag, GH release, aliases, artifact check); Mike reinstalls + reloads; S8 live.

**Design refinement (keeps S4 byte-identical):** the helper returns only an agent SUFFIX, never a whole key. `kt_agent_suffix <stdin-json>` → `.agent-<sanitised agent_id>` or empty (json-parsed; `A-Za-z0-9._-`). Each hook appends it to the key it already builds, so every main-thread key and every existing fallback (transcript basename, `$$`, raw `SESSION_ID`) is unchanged.

## T1 — Tests first
**New `tests/repros/r22-subagent-transcript.sh`.** Fixture from REAL bytes: this session's `subagents/agent-aae351bbc49a03015.jsonl` (doc-updater: two text-marker blocks + one Write), sanitised like `transcript-cc21280-real-base.jsonl` → `tests/fixtures/subagent-cc21280-real.jsonl`. Laid out at `<tmp>/<sid>/subagents/agent-<aid>.jsonl`; parent `<tmp>/<sid>.jsonl` = the existing main-thread base fixture (does not contain the subagent's id).
Fixture is scrubbed (user prompt, attachments, thinking and Write content → placeholders); run `check-public-hygiene.sh` after — public repo.
- **S1** edit input `{session_id, agent_id, transcript_path=<parent>, tool_use_id=<subagent Write id>}`, cap 5000 → allow **and no `could not verify` text** (the old code also allows, by failing open — the text is the discriminator; duration recorded, not asserted).
- **S2** same with the subagent fixture's marker text removed → deny.
- **S3** `agent_id` whose subagent file does not exist; `transcript_path` = a file containing the target + a marker → allow (fallback).
- **S5** an `agent_id` whose UNSANITISED path resolves to a decoy holding the target + a marker, while the sanitised path does not exist → the hook falls back to `transcript_path` (target, no marker) → **deny**. Green on old code; red under the unsanitised mutation.
**Extend `tests/repros/r22-carrier-side-channel.sh`** — **C12**: record + edit with hostile `agent_id` `a/b..c` → allow. The recorder keeps its own Python sanitiser; this is what makes drift between the two copies go red.
- **S6a** Rule 22 breaker: 3 denials as agent A in session S → the 4th agent-A edit degrades; a parent edit in S right after is still DENIED (not degraded).
**Extend `plugin-claude-code/tests/test-preflight-gate.sh`** — [10b]: 3 commit denials with `agent_id` in session pf12 → parent commit in pf12 still denies; agent's 4th degrades.
**Extend `plugin-claude-code/tests/test-external-fetch-gate.sh`** — AC12b: 3 denials as an agent in s25 (three distinct registrable domains, per AC12's own warning) → clear cooldowns, keep counters → parent fetch of a covered domain still denied; the agent's counter file is the `.agent-` one.
Declare expected reds on current code before running.

## T2 — `bin/lib-state-key.sh` (new)
`kt_agent_suffix` as above; POSIX sh (all consumers are `#!/bin/sh`); a shell fast path returns empty without spawning python when the input has no `"agent_id"` key (every main-thread call); `printf '%s'` into python, never `echo`.

**Gate 4 (prospect `knowledge/logs/prospect/2026-09-24-file-r22-subagent-transcript-plan.md`, PROCEED-WITH-CHANGES).** Old-code predictions, declared before running: S1 RED · S2 RED · S3 green · S5 green · S6a RED · [10b] RED · AC12b RED · C12 green (a guard: parity already holds).

## T3 — Consumers
- `pre-edit-check.sh`: source the lib; `AGENT_SUFFIX=$(kt_agent_suffix "$INPUT")` right after `SESSION_KEY`; breaker key `…-denies-${SESSION_KEY}${AGENT_SUFFIX}`; carrier key `…-carrier-${SESSION_KEY}${AGENT_SUFFIX}` (replaces the 2.54.0 `tr -cd` AGENT_KEY block — same output, one definition); subagent transcript derivation from the suffix (spec §3), before the detector runs.
- `pre-commit-preflight-check.sh`: source the lib by `$(dirname "$0")`; breaker key gains the suffix. Marker and skip-ledger unchanged (session-level, intended).
- `pre-external-fetch-check.sh`: breaker key (`EF_DENY_FILE`) gains the suffix. Cooldown unchanged (session-level, intended).

## T4 — Verify
Mutations with named controls: drop derivation → S1 · derive without `[ -f ]` fallback → S3 · unsanitised agent id → S5 · drop suffix in each of the three breaker keys → S6a / [10b] / AC12b · helper uses echo → hook-json-extraction guard (if it covers libs) else note. Old-code run: predicted reds declared first. Full root + plugin suites; `plugin-antigravity/build.sh` (the lib is copied — antigravity's pre-edit copy sources it) + idempotence; gate D after staging.

## T5 — Release
CHANGELOG 2.54.1; both manifests; ledger `--update antigravity` + `claude-code`; `/preflight`; commit; build; push; annotated tag; GH release; `publish-release.sh --apply`; artifact check (lib present in zip, sourced by all three hooks, suffix in all three breaker keys). Then Mike reinstalls + `/reload-plugins`; S8 live with `doc-updater`.
