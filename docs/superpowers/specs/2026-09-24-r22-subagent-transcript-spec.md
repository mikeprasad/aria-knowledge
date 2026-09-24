# Rule 22 gate — read the subagent's own transcript; key the breaker per agent

**Date:** 2026-09-24 · **Status:** DRAFT (SPPPE gate 1) · **Target:** aria-knowledge v2.54.1 (patch, Claude Code branch only)
**Ruled by Mike (2026-09-24):** "A yes full release" — fix the 2.54.0 subagent regression, full SPPPE, full release.

## 1. Problem (measured live, session 57eacd57, CC 2.1.280, after installing 2.54.0)

- A `doc-updater` subagent (no Bash tool) edited with a visible-text `[Rule 22]` marker. Its pre-edit hook ran **41,171 ms** (the full 40 s wait) and fail-opened (`could not verify`).
- That subagent's Write `tool_use_id` is **absent from the parent transcript** and present only in `…/<session_id>/subagents/agent-aae351bbc49a03015.jsonl`; both marker text blocks were persisted there. The subagent's records carry the **parent's** `sessionId`.
- ⇒ Inside a subagent the hook's `transcript_path` is the **parent** session's file, which never contains a subagent's calls. Every subagent edit without a recorded carrier has always failed open; 2.54.0's longer wait turned a 1.5 s stall into a **40 s stall**.
- The two competing explanations were separated by measurement: a watcher on `subagents/` saw a subagent's three calls reach disk **0.11–0.13 s** after creation, progressively — so the file is written per response, not at subagent completion, and reading it would work.
- The hook's `agent_id` equals the id in the subagent transcript filename (live: recorder key `.agent-a9d69593ddbcc4f71` for agent `a9d69593ddbcc4f71`, transcript `agent-a9d69593ddbcc4f71.jsonl`). Subagents share the parent's `prompt_id`.
- **Same class (Rule 38):** the deny-rate breaker file is keyed on `session_id` only, so a subagent's denials count toward — and can open — the parent session's breaker.

## 2. Acceptance criteria

- **S1** Subagent edit (input has `agent_id`, `transcript_path` = parent file lacking the id) whose own transcript has a text marker above the edit → **allow**, in well under the wait (< 3 s with a 5 s cap).
- **S2** Same, subagent transcript with no marker → **deny**.
- **S3** `agent_id` present but no subagent file at the derived path → falls back to `transcript_path` unchanged (a marker there still allows).
- **S4** Main-thread edits (no `agent_id`) behave exactly as in 2.54.0 (existing suites green, unchanged).
- **S5** A hostile `agent_id` (`../../x`) cannot address a path outside `…/<session>/subagents/` (sanitised to `A-Za-z0-9._-`, no `/`).
- **S6** Breakers keyed per agent — **all three** (gate-2 change, Rule 38): the Rule 22 breaker, the preflight commit-gate breaker (`aria-preflight-denies-*`) and the external-fetch breaker (`aria-extfetch-denies-*`). Three denials inside a subagent open none of the parent's. One helper, `bin/lib-state-key.sh` (`kt_state_key <stdin-json>` → `<sid>` or `<sid>.agent-<aid>`, agent_id parsed with json and sanitised), used by all three. ⚠ Deliberately NOT agent-keyed: the preflight marker ("a preflight ran this session") and the fetch cooldown ("already asked for this key") — session-level facts a subagent should inherit.
- **S7** Every new control mutation-verified; the previous code fails exactly the predicted set.
- **S8 (live, post-install):** `doc-updater` edit with a visible-text marker → allowed with **no** `could not verify` record and a hook duration of seconds, not 40.

## 3. Design

In `pre-edit-check.sh`, Claude Code branch, after `AGENT_KEY` is known:
```
if [ -n "$AGENT_KEY" ] && [ -n "$TRANSCRIPT" ]; then
  SUB="$(dirname "$TRANSCRIPT")/$(basename "$TRANSCRIPT" .jsonl)/subagents/agent-${AGENT_KEY}.jsonl"
  [ -f "$SUB" ] && TRANSCRIPT="$SUB"
fi
```
- If a harness version ever passes the subagent's own path as `transcript_path`, the derived path (`…/agent-X/subagents/agent-X.jsonl`) does not exist and the original is kept — correct in both cases.
- Breaker: `BREAKER_STATE` gains the same `.agent-<AGENT_KEY>` suffix as the carrier file. Main-thread key unchanged, so existing counters keep working.
- The carrier side channel is untouched (already agent-keyed and verified live).

## 4. Alternatives

- **Shorten the wait for subagents** — rejected: hides the stall, keeps every subagent edit unverified.
- **Exempt subagents from the gate** — rejected: an unenforced class of edits.
- **Read the subagent file only (no fallback)** — rejected: breaks if the harness ever passes the subagent path directly.
- **Leave the breaker session-wide** — rejected under Rule 38: same parent/subagent conflation, and a subagent can switch the parent's enforcement off.

## 5. Risks

- **R1** Subagent transcript directory layout is observed, not documented. Mitigation: fallback (S3) and S8 live.
- **R2** A subagent's first edit before its file exists — the file starts with the subagent's prompt line, written at start (every observed subagent transcript begins with it). Fallback covers the gap either way.

## 6. Verification
Fixture = a real (sanitised) subagent transcript from this session laid out at `<dir>/<sid>/subagents/agent-<aid>.jsonl` beside a parent file lacking the id; S1–S6 + mutations; full suites; port idempotence; gate D; S8 after reinstall.
