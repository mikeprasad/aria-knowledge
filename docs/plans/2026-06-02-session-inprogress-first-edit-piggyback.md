# Plan — SESSION.md `in-progress` via first-edit piggyback (v2.23.0)

## Problem
`session_state: true` is enabled and the SessionStart hook runs, but `lastEvent: in-progress` is **never reliably written**. The v2.22.0 design emits an instruction-as-output telling Claude to mark in-progress once the project resolves — a soft, unenforced directive buried in a ~4.7k-char SessionStart message that Claude routinely skips (proven live: an active aria-atlas session never marked its own SESSION.md). `/handoff` and `/wrapup` write reliably (explicit skill runs); only the automatic *in-progress* mark fails. Result: atlas never shows "in session".

## Goal
Write `lastEvent: in-progress` **deterministically** (by a hook, not Claude's compliance) when a session actively edits a project, with **no new per-turn hook** and **no context/token output**. Detect the project from the first **edited file path** (works even when cwd is `~/Projects` root, which is Mike's workflow — cwd-based detection can't).

## Approach
Host the write in the **existing** `bin/post-edit-check.sh` (PostToolUse `Edit|Write`):
- Runs *after* a successful edit → cannot interfere with the Rule 22 pre-edit deny path.
- Already parses `FILE_PATH` from the tool input and sources `config.sh`.
- Fires on every edit, but the write is **guarded to once per (session, project)** via a `/tmp` ledger → after the first edit in a project, it's a single `grep` early-exit. Zero output into the conversation.

### New helper: `bin/lib-session-state.sh`
- `kt_ss_find_root FILE_PATH` — walk up from `dirname(FILE_PATH)` to the nearest ancestor containing `CLAUDE.md` or `PROGRESS.md`; echo it. Stop at `$HOME`/`/`; echo empty if none. (Matches the producer's "project root = nearest dir with CLAUDE.md/PROGRESS.md".)
- `kt_ss_mark_inprogress ROOT SESSION_ID` — light-touch write `ROOT/SESSION.md`:
  - **Exists:** refresh frontmatter keys `lastEvent: in-progress`, `at: <UTC now>`, `branch`, `headCommit`, `sessionId`; **PRESERVE** `currentFocus`/`nextAction`/`by` and the **entire body** (incl. `## Next session prompt`). If header unparseable, prepend a fresh header, keep the rest below.
  - **Absent:** create minimal in-progress SESSION.md (`currentFocus`/`nextAction` empty, minimal body), `by:` from config author tag if available.
  - **Gitignore:** if ROOT is a git repo and `SESSION.md` isn't already ignored, append `SESSION.md` to `.gitignore`. **Never `git add`** SESSION.md.
  - All ops fail-safe (`|| true`); the hook must never error or block.

### Edit: `bin/post-edit-check.sh`
After the existing scope-check decision (output JSON unchanged), gated on `KT_SESSION_STATE = true`:
1. `SESSION_ID` from `INPUT`.
2. `LEDGER=/tmp/aria-session-inprogress-${SESSION_ID}` (lines = already-marked roots).
3. `ROOT=$(kt_ss_find_root "$FILE_PATH")`; if non-empty and not already in `LEDGER`: `kt_ss_mark_inprogress`, append ROOT to ledger. (Per-(session,project) → multi-project sessions mark each project once.)

### Edit: `bin/session-start-check.sh`
- **Trim** the in-progress-write half of the v2.22.0 SESSION STATE instruction (step 2). **Keep** the resume-offer half (step 1) — SessionStart must still offer "resume from saved prompt?" before the first turn (the only place that can). The deterministic write now lives in PostToolUse.
- Add `aria-session-inprogress-*` to the existing stale-ledger sweep (>1 day).

## Non-goals / accepted limits
- **Read-only sessions** (no edits) won't mark in-progress — acceptable: no edit ≈ not actively building; atlas shows the base status.
- **Other ports** (codex/cursor/antigravity/cowork): Code-only (cowork is skills-only, no PostToolUse). Tracked-drift; note in CHANGELOG scope.

## Files
- new `bin/lib-session-state.sh`
- edit `bin/post-edit-check.sh`, `bin/session-start-check.sh`
- edit `.claude-plugin/plugin.json` (→ 2.23.0), `CHANGELOG.md`
- new `tests/` cases for `lib-session-state` wired into `tests/run.sh`

## Risks
1. **Body-clobber on refresh** — the frontmatter rewrite must preserve the body + any `## Next session prompt` (handoff prompts). → test refresh-preserve explicitly.
2. **Cross-port drift** — leave other ports unchanged; document scope.
3. **Hook latency** — write is one small file; fail-safe; PostToolUse not on the deny path.
4. **Stale ledgers** — swept by session-start-check (>1 day), matching `aria-active-*`.

## Acceptance
- Edit a file in a project (session_state on) → `ROOT/SESSION.md` becomes `in-progress`, once, preserving existing body.
- Re-edit same project/session → no rewrite (ledger).
- Edit a second project same session → that one also marked.
- Rule 22 pre-edit behavior + scope-check output unchanged.
- `tests/run.sh` green.
