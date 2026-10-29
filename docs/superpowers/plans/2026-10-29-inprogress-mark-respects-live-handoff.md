# The in-progress mark must not take over a live handoff — plan

Date: 2026-10-29 (UTC). Reported by session `879f0754`; forwarded by Mike as a defect to fix.

## Defect

`post-edit-check.sh` calls `kt_ss_mark_inprogress` on a session's first edit in a project. That
function rewrites five front-matter keys (`lastEvent`, `at`, `branch`, `headCommit`, `sessionId`)
and passes the body through. When the body's `## Next session prompt` holds another session's
unconsumed handoff, the front matter stops describing the prompt underneath it.

Measured consequence, from the `879f0754` transcript (2026-10-29T00:29Z):

- `kt_ss_ledger_token_locate proj-a "aria-handoff: proj-a/5ce12827-…@2026-10-28T23:12:55Z"` returned
  `879f0754-…|2026-10-28T23:16:12Z|unconsumed|active`. The token text matched, but the identity
  reported was the hook's stamp (879f0754's own first edit, 3 minutes after the handoff).
- The session had to restore the front matter by hand from `git show HEAD:SESSION.md` before the
  token resolved to `5ce12827…|23:12:55Z`.
- The same overwrite hit a worktree's copy of the same `SESSION.md` (stashed in that repo).

Already known and worked around, never fixed: `tests/repros/session-state.sh` block O
characterizes the overwrite, `kt_ss_read_active_token`'s comment records a measured token/front-
matter disagreement, `kt_ss_ledger_consume_active` reads token-first, and `/wrapup` + `/handoff`
tell the agent to annotate a "HOOK ARTIFACT" sid. Two readers were never moved to token-first:
`kt_ss_ledger_token_locate` (ACTIVE branch) and `kt_ss_ledger_candidates` (active row).

## Fix — two halves

**1. Writer (the cause).** `kt_ss_mark_inprogress` leaves the front matter untouched when the
active slot holds a live prompt. "Live" = the trimmed `## Next session prompt` block is non-empty
and is not the fresh `(session in progress)` marker — the same predicate `consume_active` uses
today. One helper, `kt_ss_active_prompt_live ROOT`, holds the boundary walk and the predicate;
`consume_active` is rewired to call it, so the two can never disagree about where the active block
ends or what counts as empty. The body and the `.gitignore` handling are unchanged.

Consequence, chosen: while an unconsumed active handoff exists, the project reads `lastEvent:
handoff` to aria-atlas even if an unrelated session is editing there. That is the truthful state —
the prompt is still waiting. Once a resuming session consumes it (`consume_active` clears the
slot), the next session's first edit marks the project in progress as before.

**2. Readers (stored-data residue).** Files already stamped stay stamped, and older installs keep
stamping until reinstalled. So `token_locate`'s ACTIVE branch and `ledger_candidates`' active row
report the identity from the active block's own `aria-handoff:` token when one exists, and fall back
to front matter only for pre-token prompts. This matches `consume_active`.

## Alternatives rejected

- **Readers only.** Resolves the token, but front matter keeps misattributing: `/wrapup` demotes the
  prompt under the wrong sid and the staleness check reads the hook's `at`. Leaves the cause.
- **Demote the prompt into Pending at edit time, then stamp.** A ledger mutation from an edit hook —
  the shape Mike ruled out on 2026-09-17 ("no new post or pre edit hook checks"). The fix above adds
  no check and no write; it makes an existing write do less.
- **Record the editing session in a new key** (e.g. `editingSession:`). Changes the SESSION.md
  contract owned by aria-atlas (vendored fixtures, block H). Larger than the defect.

## Changes from the /prospect gate (PROCEED-WITH-CHANGES)

Log: `knowledge/logs/prospect/2026-10-29-file-inprogress-mark-respects-live-handoff.md`.

- **C1 — `consume_active` has ZERO committed tests** (grep over every tests dir). Add a regression arm
  (live prompt → demoted + consumed + slot cleared; `(session in progress)` body → byte no-op) and
  see it green on the CURRENT code before rewiring it onto the helper.
- **C2 — known bound, decided.** The hook marks once per (session, root). A session that consumes a
  prompt after its first edit leaves `lastEvent: handoff` + the consumed sid in front matter until
  another session's first edit. Not retried per edit (per-edit work, against the 2026-09-17 ruling);
  the resume offer reads the emptied prompt block, so nothing is re-offered.
- **C3 — antigravity is generated** (`build.sh` copies canonical `scripts/` into `bin/`); regenerate,
  never hand-edit.

## Tests (`tests/repros/session-state.sh`), red before green

- **O inverted** from characterization to guard: an existing `sessionId`/`at`/`lastEvent` over a live
  prompt is NOT rewritten (O1), body survives (O2), and positive controls — an empty active slot and
  a `(session in progress)` marker ARE refreshed (O3, O4), so a "never write" mutation fails.
- **D amended:** its fixture held a live prompt in the active slot and asserted the flip. The stored
  prompt moves under `## Pending handoffs`, so D keeps its refresh + body-passthrough coverage.
- **U new arm:** front matter names a different sid/at than the active token → `token_locate`
  reports the token's.
- **T new arm:** same disagreement → `ledger_candidates`' active row reports the token's.
- Block Q (per-port keys + one bare `{ print }`) must stay green.

## Scope

All four libraries carrying these functions, kept byte-identical where they are today:
`plugin-claude-code/scripts`, `plugin-antigravity/bin`, `plugin-cursor-template/scripts/aria`,
`plugin-openai-codex/bin`. Full repro suite before commit. Commit locally; no push or release
without Mike.

Out of scope, flagged: the `/wrapup` and `/handoff` prose in four ports that calls the overwrite
"routine". Its instruction (do not gate on `sessionId`) stays correct because of residue; only its
stated mechanism goes stale.
