---
title: Subagent Knowledge Capture
status: Draft
date: 2026-05-31
target: plugin-claude-code (aria-knowledge)
ports_in_scope: claude-code only (codex / cursor / antigravity deferred)
---

# Subagent Knowledge Capture

## Problem

ARIA's knowledge-capture lifecycle assumes the knowledge it wants to capture lives in
a transcript that `/extract` (or the `PreCompact` archive hook) can read. That assumption
holds for the **main session** but breaks for **subagents** (Task-dispatched agents):

- A subagent runs in an isolated context window.
- Only its **final message** returns to the parent. Its full transcript — including
  non-obvious discoveries, dead-ends ("tried X, failed because Z"), and decisions made
  autonomously inside the run — is discarded the moment it returns.
- `/extract` in the parent can therefore only mine what the subagent chose to surface in
  its return message. The most durable, hard-won knowledge (the journey, not the
  conclusion) is gone before the parent regains control.

There is currently an **inbound** hook (`TaskCreated` → `task-context-check.sh`, feeds
matching knowledge into a subagent at dispatch) but **no outbound** capture when a
subagent finishes. This spec closes that asymmetry.

## Why a subagent cannot self-extract

A subagent cannot reliably run `/extract` on its own session, for three structural reasons.
This is the premise that forces the capture-then-govern split below:

1. **Timing.** `SubagentStop` fires *after* the subagent has finished responding — the
   subagent is already done and can take no further action. There is no
   "about-to-be-compacted" moment for it to act on the way a live session has before compaction.
2. **Not interactive.** A subagent has no user dialogue and should not write to intake
   backlogs unsupervised mid-task — that would bypass ARIA's human-in-the-loop governance
   (ADR-002).
3. **Separation of concerns.** Capture (cheap, reliable) belongs at the boundary; synthesis
   (judgment-heavy, governed) belongs in a context that can do it properly — the parent's
   `/extract` or `/audit-knowledge`.

## Goals

- Capture the full transcript of **heavyweight** subagent runs before it is lost, into a
  governed intake folder, non-destructively.
- Nudge **routine** subagents to surface durable findings in their return message so the
  parent's existing `/extract` catches them — without archiving their (mostly low-signal)
  transcripts.
- Preserve ARIA's capture → govern → promote model: nothing auto-promotes; humans decide
  at `/extract` or `/audit-knowledge` time.

## Non-goals

- No automatic inline nudge to the parent session when a capture lands (see Constraint C1).
- No port to codex / cursor / antigravity in this iteration (see "Future ports").
- No change to the existing `TaskCreated` inbound-context behavior (but see "Side finding").

## Verified background (Claude Code hooks)

Confirmed against `https://code.claude.com/docs/en/hooks` on 2026-05-31:

| Hook | Fires | `agent_type` matcher | `additionalContext` | Notes |
|------|-------|:---:|:---:|-------|
| `SubagentStart` | when a subagent is spawned | yes | **yes** (grouped with SessionStart/Setup, "at the start of the conversation") | Injection target (subagent vs parent) implied but **not confirmed** → validation gate V1 |
| `SubagentStop` | when a subagent finishes | yes | **no** (only `decision` / `continue` / exit code) | Archive is a filesystem side-effect; cannot nudge parent inline |
| `TaskCreated` | when a task is created via `TaskCreate` | not documented | **no** per docs | Existing `task-context-check.sh` emits `additionalContext` here — see Side finding |

Common input fields available to both subagent hooks: `session_id`, `transcript_path`,
`cwd`, `permission_mode`, `hook_event_name`, plus `agent_id` and `agent_type` when firing
inside a subagent call.

**Validated empirically 2026-05-31 (live probe — see plan Task 1 V1 result).** The actual
`SubagentStop` payload carries **two** transcript fields — and the distinction is
load-bearing:

- `transcript_path` → the **parent session's** transcript (e.g. `.../<session-id>.jsonl`).
- `agent_transcript_path` → the **subagent's own** transcript (e.g.
  `.../<session-id>/subagents/agent-<agent_id>.jsonl`). **This is the one to archive.**

It also carries `last_assistant_message` (the subagent's final message), `stop_hook_active`,
`effort`, and `permission_mode`. The subagent transcript file **persists on disk** after the
subagent ends (with an `agent-<id>.meta.json` sidecar). `SubagentStart` injected
`additionalContext` was confirmed to reach the **subagent's** context, and both hooks fired
on a **mid-session** `settings.local.json` edit (no restart needed). `agent_type` for the
built-in general agent is literally `general-purpose`.

## Design

### A-side — `SubagentStop` archive hook

New script `bin/subagent-stop-capture.sh`, registered on `SubagentStop`.

1. Parse `session_id`, `agent_transcript_path`, `agent_id`, `agent_type` from stdin JSON
   (reuse the `grep -o … | sed` parse pattern from `pre-compact-check.sh`). **Use
   `agent_transcript_path` (the subagent's transcript), NOT `transcript_path` (the parent
   session's) — verified 2026-05-31.**
2. Exit 0 silently if any of: not configured, `KT_CONFIG_ERROR` set, knowledge folder
   missing, `KT_AUTO_CAPTURE = false`, `KT_SUBAGENT_CAPTURE = false`, or `agent_type` is
   **not** in `KT_SUBAGENT_CAPTURE_TYPES`.
3. Copy the subagent transcript to:
   ```
   {knowledge_folder}/intake/subagent-captures/{YYYY-MM-DD}_{parent-session-8}_{agent_type}_{agent_id-8}.md
   ```
   where `parent-session-8` is the first 8 chars of `session_id` and `agent_id-8` the
   first 8 of `agent_id`. The `agent_type` token makes provenance self-evident on disk.
4. Emit nothing on stdout (`SubagentStop` does not support `additionalContext`; a bare
   exit 0 is the correct no-op).

Guarded so a missing/unreadable `agent_transcript_path` exits 0 without error (match
`pre-compact-check.sh` robustness).

### B-side — `SubagentStart` self-report hook

New script `bin/subagent-start-selfreport.sh`, registered on `SubagentStart`.

1. Parse `agent_type` from stdin JSON.
2. Exit 0 silently on the same config/folder guards, or if `agent_type` is **not** in
   `KT_SUBAGENT_SELFREPORT_TYPES`.
3. Emit `hookSpecificOutput.additionalContext` with a concise instruction, e.g.:
   > "Before you return, briefly surface any durable findings worth persisting —
   > non-obvious discoveries, dead-ends you ruled out (and why), and decisions you made.
   > Put them in your final message so they aren't lost when this subagent ends."
4. JSON shape mirrors `pre-compact-check.sh`'s emission and `kt_json_escape` usage.

B is **gated behind validation V1** (below). If injection lands in the parent rather than
the subagent, B is descoped to a documented dispatch convention; A ships regardless.

### Retention & governance — sticky-until-extracted

Subagent captures have a **different lifecycle** from pre-compact snapshots, which is why
they get their own folder:

- Pre-compact snapshots are *derived copies* of Claude Code's canonical session `.jsonl`,
  so `/audit-knowledge` may ledger-clear (delete body, keep pointer) freely.
- Subagent captures are **body-preserved until an extraction explicitly processes them**.
  They are never cleared on sight. This removes any dependency on whether a subagent's
  `transcript_path` is persisted under `~/.claude/projects/` — we hold the body until used.
- A capture is eligible for ledger-clear **only after** the parent's `/extract` or
  `/audit-knowledge` has reviewed it.

### Config schema (`aria-knowledge.local.md`, additive per ADR-002)

New keys, parsed by `config.sh` into `KT_*` vars:

| Key | `KT_` var | Default |
|-----|-----------|---------|
| `subagent_capture` | `KT_SUBAGENT_CAPTURE` | `true` (also gated by existing `auto_capture`) |
| `subagent_capture_types` | `KT_SUBAGENT_CAPTURE_TYPES` | `general-purpose, Plan, feature-dev:code-architect, feature-dev:code-explorer, feature-dev:code-reviewer` |
| `subagent_selfreport_types` | `KT_SUBAGENT_SELFREPORT_TYPES` | `Explore` |

Lists are comma-separated agent-type names matched case-sensitively against the `agent_type`
field from the hook input. A type in neither list is silently ignored by both hooks.
Documented in `CONFIG.md`.

**Default-list caveat:** the matcher keys on `agent_type` (e.g. `general-purpose`, `Explore`,
`Plan`, or a plugin agent's namespaced name), **not** on skill names — so the defaults must be
real agent-type strings, not skills like `debug` or `deep-research` (those run inline in the
main session, not as subagents). The exact runtime string for plugin agents
(e.g. `feature-dev:code-architect` vs `code-architect`) should be confirmed empirically; the
V1 validation hook can log a sample `agent_type` to lock the format before defaults are
finalized.

### Audit + extract integration

- **`/audit-knowledge`**: add a step after the existing Step 2d (Pre-Compact Captures) that
  scans `intake/subagent-captures/` for `.md` files; if none, skip silently. If present,
  report count + size and offer **Digest** (default, via `digest-transcript.sh`) /
  **Detailed** / **Skip**. Reviewed items append to the appropriate backlog, then
  ledger-clear to `archive/audit-{date}/subagent-captures/REMOVED.md` (mirror the existing
  REMOVED.md ledger schema). **No "Clear without review" option** — sticky retention means
  bodies are not discarded without extraction.
- **`/extract`**: add an opportunistic sweep — scan `intake/subagent-captures/` for **all**
  pending captures, fold any findings into the synthesis buckets, and ledger-clear only the
  captures it actually processed; leave the rest for `/audit-knowledge`.
  **Why not filter to the current session:** a skill (which `/extract` is) does not receive
  `session_id` from the runtime — `save-transcript.sh:21-28` documents this and falls back to
  the most-recently-modified `.jsonl` for exactly that reason. So `/extract` cannot reliably
  match the `{parent-session-8}` filename prefix to "this session." The prefix stays valuable
  for provenance and audit listing, but it is **not** a skill-side filter. Sweeping all pending
  captures is safe because they are sticky and governed regardless of which session produced
  them; nothing is double-processed (ledger-clear removes a capture once folded in).

### `/setup` folder repair

Add `intake/subagent-captures/` (with `.gitkeep`) to the plugin-managed folder list so
`/setup` creates and repairs it. Ship `template/intake/subagent-captures/.gitkeep`.

### Validation gate V1 (run during implementation, before B ships)

The docs imply but do not confirm that `SubagentStart`'s `additionalContext` injects into
the subagent's context (vs the parent's). Before shipping B:

1. Register a throwaway `SubagentStart` hook that injects a unique marker string.
2. Dispatch a trivial subagent and inspect its transcript.
3. **Pass** = marker appears in the subagent's context → ship B as designed.
   **Fail** = marker appears only in the parent → descope B to a documented dispatch
   convention (orchestrator includes the self-report ask in the dispatch prompt); A is
   unaffected.

## Implementation sequencing (ship units)

A-side and B-side are **separable ship units** with independent risk profiles — they are
bound by a shared goal, not by an atomic release:

- **Ship unit 1 (A-side, no blockers):** plugin.json `SubagentStop` registration,
  `subagent-stop-capture.sh`, `config.sh` keys, `template/.gitkeep`, `/audit-knowledge`
  scan step, `/setup` repair, `CONFIG.md` + `CHANGELOG.md`, and the `/extract` sweep-all
  pickup. Fully validated; can ship first.
- **Ship unit 2 (B-side, gated):** validation gate V1 runs first; `SubagentStart`
  registration + `subagent-start-selfreport.sh` ship only on a V1 pass, else descope to the
  dispatch-convention fallback.

## Constraints & risks

- **C1 — no inline parent nudge.** `SubagentStop` cannot emit `additionalContext`, so the
  parent is not automatically told a capture is waiting. Parent-side pickup is opportunistic
  (whenever the parent runs `/extract`, including via `/wrapup` / `/handoff`); `/audit-knowledge`
  is the guaranteed backstop. Sticky retention guarantees nothing is lost in the interim.
  A guaranteed nudge would need a separate channel (e.g. a `SessionStart`/next-prompt count of
  pending captures) — out of scope here, noted as a future option.
- **R1 — capture volume.** Heavyweight agents can still be frequent. Default type list is
  conservative; `subagent_capture_types` is tunable. Sticky retention plus no auto-clear means
  the folder can grow until an audit — acceptable, and visible at audit time.
- **R2 — injection direction (B).** Mitigated by validation gate V1.

## Side finding (out of scope, flag only)

The existing `task-context-check.sh` emits `hookSpecificOutput.additionalContext` on
`TaskCreated`, which the current docs list as **not** supporting `additionalContext`. This
inbound context-injection may be a silent no-op. Worth a separate verification; not part of
this feature.

## Files touched

- `plugin-claude-code/.claude-plugin/plugin.json` — register `SubagentStart` + `SubagentStop` hooks; version bump.
- `plugin-claude-code/bin/subagent-stop-capture.sh` — new (A-side).
- `plugin-claude-code/bin/subagent-start-selfreport.sh` — new (B-side).
- `plugin-claude-code/bin/config.sh` — parse 3 new keys.
- `plugin-claude-code/template/intake/subagent-captures/.gitkeep` — new.
- `plugin-claude-code/skills/audit-knowledge/SKILL.md` — new scan step + REMOVED.md ledger.
- `plugin-claude-code/skills/extract/SKILL.md` — current-session sweep.
- `plugin-claude-code/skills/setup/SKILL.md` — folder-repair list.
- `plugin-claude-code/CONFIG.md` — document the 3 new keys.
- `CHANGELOG.md` — release note.

## Acceptance criteria

1. A heavyweight subagent finishing produces a file in `intake/subagent-captures/` with the
   documented name; a routine subagent does not.
2. A subagent whose `agent_type` is in neither list produces no capture and no injection.
3. With `subagent_capture: false` (or `auto_capture: false`), no captures are written.
4. `/audit-knowledge` surfaces pending subagent captures, digests them, and ledger-clears
   reviewed ones to the archive; offers no bare-clear.
5. `/extract` folds pending subagent captures into its buckets and ledger-clears only the
   ones it processed.
6. `/setup` creates `intake/subagent-captures/` on a fresh knowledge folder.
7. Validation V1 has a recorded pass/fail result; B ships or descopes accordingly.

## Future ports

Once proven on plugin-claude-code, port to codex / cursor / antigravity per the standard
canonical-first workflow, verifying each runtime actually fires `SubagentStart` /
`SubagentStop` (Cursor/Antigravity/Codex hook-event support is not assumed).
