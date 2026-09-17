# A1 — demote-then-consume at resume

**Date:** 2026-09-17 · **Ruled by:** Mike (option A1; then *"no new post or pre edit hook checks —
the only hooks for this should be on session start ideally"*) · **Status:** PLAN — gated, not executed

## The defect, measured

`kt_ss_ledger_mark_consumed` rewrites only lines matching `^### `. The active prompt lives under
`## Next session prompt` and has **no `###` header**, so calling it on a live prompt matches zero
lines, rewrites nothing, and returns 0.

Measured this session on an isolated replica:

| arm | expected | observed |
|---|---|---|
| `token_locate` on a live token | `sid\|at\|unconsumed\|active` | exact match |
| `mark_consumed` on that active prompt | header flips | **rc=0, file byte-identical** |
| positive control: same call on a `###` entry | header flips | flipped |

Corpus corroboration: one real ledger (`proj-a/SESSION.md`) holds **142 entries, 0 consumed,
142 unconsumed**.
Consumption has never once been recorded. `kt_ss_ledger_prune` reaps only a word-bounded
`consumed`, so nothing has ever been prunable — which is why the file reached 636,898 chars and
why 53 stale handoffs are still offered as live.

## ⛔ Hook constraint — Mike's ruling, 2026-09-17

**No new pre-edit or post-edit hook checks. Session start is the only sanctioned hook surface.**

This is satisfied without adding any hook at all. The SessionStart hook
(`bin/session-start-check.sh`) does not consume anything itself — it **emits a directive**, and the
agent performs the consumption when it finds an `aria-handoff:` token in the pasted opener. So the
change is: one new library function, one directive-text change inside an existing SessionStart
hook, and one always-on rules file aligned. No hook is added, and no hook gains a new check.

⛔ **`bin/post-edit-check.sh` IS OUT OF SCOPE AND MUST NOT BE EDITED.** Its lines 99-105 call
`kt_ss_ledger_mark_consumed` and are inert against an active prompt. Do **not** repair them and do
**not** delete them:

- Repairing is forbidden by the ruling above, and was independently KILLED by this plan's
  `/prospect` — making that call work would demote-and-consume a handoff on **any** session's
  first edit in the project, including a session that never read the prompt. It is harmless today
  only because the function it calls is a no-op. (Pattern: `latent-behaviour-activation`.)
- Deleting is **not provably behaviour-preserving**: the call no-ops against the *active* prompt,
  but would still mark a `###` entry in `## Pending handoffs` that shares the front-matter sid and
  is still `unconsumed`. That path is reachable. Removing it is therefore an unvalidated behaviour
  change, not a dead-code cleanup, and it is left for a separate ruling.

## The change

### New library functions (`bin/lib-session-state.sh`)

**`kt_ss_read_active_token <root>`** — print the `aria-handoff:` token's `sid|at` from inside the
active prompt's fence, empty if absent. Required because no existing reader returns it:
`kt_ss_read_active_sid` reads **only** the front matter (awk on `^sessionId:` inside the
front-matter fence), which is exactly the value that is wrong when the two disagree.

**`kt_ss_ledger_consume_active <root> <by> <now>`**:

1. Locate the `## Next session prompt` block (to the next column-0 `## ` outside a fence).
   `kt_ss_ledger_token_locate` already implements this walk — mirror it, do not reinvent it.
2. Empty, absent, or body is just `(session in progress)` → return 0. Silent, safe no-op.
3. Resolve identity: **the token wins over the front matter**, per the handoff SKILL ruling
   (2026-09-15). Load-bearing — on one real ledger today the token says `10cf229b@11:00:01Z` while
   the front matter says `4c3e190c@11:06:37Z`, because a later session's first edit stamped its own
   identity over the header. Reading the front matter attributes the handoff to the wrong session
   permanently. Fall back to the front matter only when no token is present (pre-token prompts).
4. `kt_ss_ledger_add` to demote the block into `## Pending handoffs` at full fidelity.
5. `kt_ss_ledger_mark_consumed` with the **token's** `(sid, at)` — the exact 5-arg form, never the
   sid-alone form, because one sid legitimately carries two timestamps.
6. Clear the active block, leaving the `## Next session prompt` heading present and empty.

### Directive change (`bin/session-start-check.sh`) — text only, no new check

In the SESSION STATE message, replace "mark it consumed via `kt_ss_ledger_mark_consumed`" with a
call to `kt_ss_ledger_consume_active`, and state that an `|active` result must go through that
function because `mark_consumed` alone cannot reach an active prompt.

### Always-on digest alignment (`rules/aria-rules.md`)

Measured 2026-09-17: the plugin's shipped `rules/aria-rules.md` contains **zero** occurrences of
`aria-handoff`, while `bin/session-start-check.sh` contains the token-aware directive. Both load in
the same session, so a resuming agent receives **two different resume procedures** — the digest's
pre-token one ("if the opening message included the word 'handoff', execute that prompt directly")
and the hook's token-aware one. Align the digest to the hook. This is a rules-text file, not a
hook, so it is inside the ruling's constraint.

## Acceptance criteria

- **AC1** On a ledger with an active prompt, `consume_active` moves it to `## Pending handoffs`
  with status `consumed <ts> by <by>`, and `## Next session prompt` is left empty.
- **AC2** Identity written is the **token's**, proven by a fixture where token and front matter
  deliberately disagree. Must go RED if the front matter is read instead.
- **AC3** On an empty active block, and on a `(session in progress)` marker, `consume_active` is a
  byte-for-byte no-op.
- **AC4** Prompt body survives demotion byte-identically, including a body containing a column-0
  `## ` line and nested fences.
- **AC5** After `consume_active`, `kt_ss_ledger_prune` reaps the entry — the end-to-end property
  that has never once held. This is the success signal for the whole change.
- **AC6** *(killed — see the hook constraint above; number retired, not renumbered, so the kill
  stays visible in the record.)*
- **AC7** A pre-token prompt (no `aria-handoff:` line) still consumes correctly via the
  front-matter fallback. Guards the grandfathering path.
- **AC8** `rules/aria-rules.md` and `bin/session-start-check.sh` describe the same resume
  procedure. Falsifier: a token-aware assertion present in one and absent from the other.
- **AC9** `bin/post-edit-check.sh` is byte-unchanged. `git diff --stat` must show it absent.

Every AC gets a mutation: the guard must be seen RED for the right reason before it is cited.

## Explicitly out of scope

- `bin/post-edit-check.sh` — see the hook constraint. Byte-unchanged, asserted by AC9.
- Retiring the 53 existing stale entries — task B, decided separately.
- Back-filling `consumed` on historical entries. They were never consumed by this mechanism and
  inventing the record would be a fabricated measurement.

## Resolved during the gate

- **OQ1 (clear the active block?) — RESOLVED: clear it.** `kt_ss_ledger_token_locate`'s active
  branch prints the literal string `unconsumed`
  (`if (sec == "ACTIVE") print fsid "|" fat "|unconsumed|active"`). The active slot is
  **structurally incapable** of reporting a consumed prompt, so a prompt left there is re-offered
  forever no matter what is written elsewhere. Residual crash risk is mitigated:
  `kt_ss_mark_inprogress` rewrites only front-matter keys, so `currentFocus` / `nextAction` still
  describe the work, and the full body survives in `## Pending handoffs`.
