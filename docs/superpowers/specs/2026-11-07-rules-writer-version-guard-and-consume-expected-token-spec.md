# Spec — rules writer refuses an older digest (I-2) · consume_active takes the expected token (I-4) · release zips survive worktree removal (I-5)

**Date:** 2026-11-07 · **Target:** patch release 2.57.8 · **Base:** `478fe4e`
**Ideas:** `knowledge/intake/ideas/2026-10-31-aria-knowledge-rules-writer-refuses-older-digest.md`,
`knowledge/intake/ideas/2026-11-07-aria-knowledge-consume-active-takes-the-expected-token.md`;
I-5 from the maintainer, 2026-11-07.
**Revision 2** (same day): `/prospect` falsified the first D1 (registry as the version oracle) and
I-5 was added. Log: `knowledge/logs/prospect/2026-11-07-file-rules-writer-guard-consume-token-release-worktree.md`.

All three are the same shape: an operation that is correct when one actor runs, and silently loses
something when two do (two sessions, two plugin installs, a worktree and its main checkout). None
raises; each was found by reading the result afterwards.

---

## I-2 — `kt_ensure_rules_files` overwrites newer rules with older ones

### Problem

`plugin-claude-code/scripts/session-start-check.sh` `kt_ensure_rules_files` copies the bundled digest
over `~/.claude/rules/aria-rules.md` whenever the bytes differ (`cmp -s` then `cp`). It never asks
which side is newer. A session started before an upgrade keeps running the old plugin's hook, and
every one of its SessionStart fires (compaction included) puts the old digest back. Measured
2026-10-30: session `ed2d35e2` on the 2.57.4 cache overwrote the 2.57.5 digest. The same is true of
the U-rules arm: an old generator re-renders `aria-user-rules.md` in its old format.

**Two installs can run at once.** Measured 2026-11-07: the CLI registry
(`~/.claude/plugins/installed_plugins.json`) names aria-knowledge **2.57.5**, while the desktop app's
local-agent copy (`~/Library/Application Support/Claude/local-agent-mode-sessions/…/rpm/plugin_*`)
is **2.57.6** (updated 2026-10-30). Both run this hook against the same `~/.claude/rules/`.

Only the Claude Code port defines this writer (census 2026-11-07: one definition, plus the archived
copy; Antigravity's setup skill states it).

### Decisions

- **D1 (revised) — Stamp the installed files with the writing plugin's version, and never replace a
  file stamped with a newer version.** The writer prepends one line,
  `<!-- aria-knowledge <version> -->`, read at write time from
  `$SCRIPT_DIR/../.claude-plugin/plugin.json`. Before replacing an installed file it reads that
  file's stamp; if the stamp names a strictly newer version than its own, it leaves the file alone.
  The stamp is computed at write time, so there is no release step to keep in sync.
  - *Rejected (was D1): compare with the registry's newest registered version.* Falsified by the
    measurement above: the desktop copy is not in the registry. With 2.57.6 on the desktop and 2.57.5
    registered, the 2.57.5 CLI session counts as "current" and keeps writing its older digest back,
    so the flip-flop continues.
  - *Rejected: compare `installPath` with the running root.* Same blind spot, stricter.
  - *Cost accepted: a deliberate downgrade.* After the user installs an older version everywhere,
    the newer stamp keeps the newer rules in place. The hook says so on every start (D5), and
    deleting `~/.claude/rules/aria-rules.md` lets the next session write. A silent flip-flop between
    two live installs is the worse failure; a downgrade is a deliberate, visible act.
- ~~**D2 — Parse the registry.**~~ **KILLED** with the first D1. No JSON parsing is needed.
- **D3 — Unknown means write (today's behaviour).** An installed file with no stamp (written by
  2.57.7 or older, or by hand), an unreadable `plugin.json`, or a version that does not parse → the
  guard does not fire. It refuses only on positive evidence of a newer writer. ⚠ Stated bound: a
  pre-2.57.8 session has no guard and still overwrites; the fix holds once every running session is
  2.57.8 or newer.
- **D4 — Absent files are written.** Some rules beat none, and a newer session replaces them.
- **D5 — Say so in the hook output, on the model channel.** When the guard leaves a file that would
  otherwise have changed, add one line before `ARIA CONFIG`:
  `ARIA RULES NOT REFRESHED — <file(s)> were written by aria-knowledge <theirs>, newer than this session's <mine>, so they were left in place. If you meant to downgrade, delete them and start a new session; otherwise tell the user to restart this session so its hooks match the installed plugin.`
  Model channel, because the measured failure fires on `source=compact`, where the hook drops the user
  banner by design (`emit()`, first line). No line when nothing would have changed.
- **D6 — Both arms.** The U-rules file gets the same stamp and the same guard (closes the class,
  Rule 38).
- **D6a — The checksums behind `ARIA RULES REFRESHED` ignore a leading stamp line.** Otherwise every
  version bump would announce "rules changed" even when no rule did.
- **D6b — Two tests that assert the installed digest is byte-identical to the bundled one** —
  `plugin-claude-code/tests/test-aria-rules-digest.sh:613` and
  `tests/repros/session-start-single-emitter.sh:178` — change to: line 1 is the stamp naming
  `plugin.json`'s version, and the rest is byte-identical to the bundled file.
- Not relied on: whether Claude Code strips the HTML comment before loading. Either way it is one
  line and carries no instruction.

### Acceptance

- **A1** Installed digest stamped with a newer version and differing → bytes unchanged, a `NOT
  REFRESHED` line, no `REFRESHED` line. RED on `478fe4e` (overwritten).
- **A2** Same for `aria-user-rules.md`. RED on `478fe4e`.
- **A3 (positive)** Installed stamp older than, or equal to, `plugin.json`, content differs → replaced,
  new stamp names `plugin.json`'s version, `REFRESHED` line present.
- **A4 (positive)** Installed digest unstamped (pre-2.57.8) → replaced and stamped.
- **A5** Absent → written and stamped, no `NOT REFRESHED` line.
- **A6** Only the stamp differs (same rules, older stamp) → stamp updated, no `REFRESHED` line (D6a).
- **A7** Newer stamp and otherwise identical → no `NOT REFRESHED` line.
- **A8** Version compare is numeric per field: `2.57.10` is newer than `2.57.9`.

---

## I-4 — `kt_ss_ledger_consume_active` consumes whatever is active

### Problem

The resume flow is two calls: `kt_ss_ledger_token_locate <root> <token>` then
`kt_ss_ledger_consume_active <root> <by> <now>`. Between them a model turn passes, and several
sessions write the same `SESSION.md`. `consume_active` takes no token, so if a peer wrote a new active
prompt in that window, the resuming session demotes and consumes the peer's live handoff and returns
0. Measured twice (backlog ~line 13222, and another project, 2026-11-06 20:56–20:57Z). The read-back
shows a consumed entry — just the wrong one.

`consume_active` is byte-identical in Claude Code, Codex and Cursor (diffed 2026-11-07), and
Antigravity's copy is generated from Claude Code's. No script calls it; its callers are the SESSION
STATE directive (Claude Code digest, Antigravity digest, Codex and Cursor inline session-start
messages) and the tests.

### Decisions

- **D7 — New signature: `kt_ss_ledger_consume_active <root> <by> <now> <token>`.** `<token>` is the
  same string passed to `token_locate` (with or without the `aria-handoff:` prefix). The function
  parses `<sid>@<at>` from it with the parse `kt_ss_read_active_token` uses, and consumes only when
  the active slot's own token (its first `aria-handoff:` line) names that same sid and at.
  - **Required, not optional.** An optional token leaves every un-updated caller on the old silent
    path, so the class stays open. Required makes an old caller fail loudly (exit 1).
  - **Compare the slot's own token, not `index($0, tok)`.** A new peer prompt can quote the old token
    in its prose; `token_locate`'s substring match would call that active.
  - **No front-matter fallback.** A tokenless prompt cannot be the one the caller located by token.
- **D8 — Exit 0 means "consumed the expected prompt", and nothing else.**
  - `1` — token missing or not parseable as `<…>/<sid>@<at>`. File untouched.
  - `2` — the active slot does not hold that token (no `SESSION.md`, empty slot, in-progress marker,
    empty fence, tokenless prompt, different token). File untouched. stderr names the expected token
    and what the slot holds.
  - `3` — the demote did not land (today this returns 0 silently; same class). Slot untouched.
  - The final clear re-checks the slot's token inside the same awk pass that rewrites the file and
    skips the `mv` on a mismatch (exit 2). This narrows the window from a model turn to one file read.
  - **Stated residual:** no `SESSION.md` writer takes a lock; a peer rewriting the whole file between
    the demote and the clear can still lose one side's write. That is every ledger writer's
    last-writer-wins class, out of scope here.
- **D9 — The directive says what to do on a refusal.** Pass the token; on a non-zero exit, re-run
  `token_locate` with the same token and act on the new result (`|pending` → `mark_consumed` with the
  exact at; empty, archived or terminal → surface and stop); never consume whatever is now active.
  Same text in all four directive copies.

### Acceptance

- **B1** Slot holds token B; call with A → exit 2, file byte-identical. RED on `478fe4e`.
- **B2** No token → exit 1, file byte-identical. RED on `478fe4e`.
- **B3 (positive)** Slot holds A; call with A, with and without the `aria-handoff:` prefix → exit 0,
  demoted under A, consumed, slot cleared.
- **B4** Slot's prose quotes A but its own first token is B; call with A → exit 2.
- **B5** In-progress marker / empty fence / no file, with a token → exit 2, byte-identical.
- **B6** All four directive copies name the fourth argument and the refusal instruction.

---

## I-5 — removing a release worktree deletes the built zips

### Problem

Releases are sometimes built in a separate worktree (2.57.7 was). The built artifacts are ignored
files — `aria-knowledge-*.zip` at the root (`.gitignore:9`) and `plugin-claude-cowork/*.plugin`
(`plugin-claude-cowork/.gitignore:2`). `git worktree remove` refuses only when there are untracked or
modified tracked files (`man git-worktree`, git 2.51.0); ignored files are neither, so they are
deleted without a prompt. `RELEASING.md` has no worktree section and no copy-out step (grep:
no match). No release script creates or removes a worktree (grep over `release*.sh`,
`publish-release.sh`, `plugin-claude-cowork/release.sh`, `plugin-antigravity/build.sh`: no match).

### Decisions

- **D10 — `RELEASING.md` gains a "Releasing from a worktree" section.** Its steps run in order, and
  the copy-out and its check come before removal: build, publish, copy the artifacts to the main
  checkout, verify each copy, then remove the worktree.
- **D11 — A helper does the last three steps as one command:
  `./release-worktree-finish.sh <worktree>`.** It finds the main checkout from
  `git -C <worktree> rev-parse --git-common-dir`, refuses if `<worktree>` *is* the main checkout,
  copies every `aria-knowledge-*.zip` at the worktree root and every `plugin-claude-cowork/*.plugin`
  to the same path in the main checkout, `cmp`s each copy, and only if all match runs
  `git worktree remove <worktree>` (never `--force`). On any failed copy or `cmp` it exits non-zero
  and leaves the worktree in place. If it finds no artifacts it says so and still does not remove
  the worktree without `--no-artifacts`, so an empty glob cannot pass for a successful copy.
  - *Rejected: the doc step alone.* That relies on someone remembering the copy before an
    irreversible delete, which is the failure being fixed. The helper makes "copy then remove" one
    command and refuses rather than deleting.
  - *Rejected: a pre-removal git hook.* Git has no hook for `worktree remove`.
  - Today no script removes a worktree, so the "make the script copy or refuse" clause applies to
    this helper, which is the only one that does.

### Acceptance

- **C1 (the hazard, control)** In a scratch repo, an ignored zip in a worktree is gone after a plain
  `git worktree remove`. This proves the test can see the loss.
- **C2 (positive)** The helper copies it to the main checkout byte-identical and removes the worktree.
- **C3** Destination unwritable → helper exits non-zero, worktree and zip still present.
- **C4** No artifacts → helper exits non-zero and the worktree stays; `--no-artifacts` removes it.
- **C5** Helper pointed at the main checkout → refuses.
- **C6 (live)** On a scratch worktree of this repo with real built zips, the zips survive in the main
  checkout after the helper removes the worktree.

---

## Out of scope

- A lock around `SESSION.md` writers (residual in D8).
- The pre-existing port-ledger drift on the 2.57.6 `/handoff`/`/wrapup` wording; re-baselined only
  after the touched surfaces are checked, as part of the release's port-parity step.
