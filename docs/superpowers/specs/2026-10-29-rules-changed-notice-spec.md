# Spec — tell the model when a rules file changed at session start

**Date:** 2026-10-29 · **Status:** implemented on branch `changed-rules-notice` (spec + plan prospected; logs in `knowledge/logs/prospect/2026-10-29-file-rules-changed-notice-{spec,plan}.md`) · **Port:** plugin-claude-code only (the only port whose hook writes these files)

## 1. Problem

`session-start-check.sh` keeps two user-scope rules files current:

- `~/.claude/rules/aria-rules.md` — the working rules and standing directives (byte-copied from the bundled digest)
- `~/.claude/rules/aria-user-rules.md` — the user's own rules, rendered from `user-rules.md`

Claude Code loads `~/.claude/rules/` into the session **before** SessionStart hooks run. So when the hook rewrites a file, the session that triggered the rewrite is already holding the previous text. Nothing tells the model.

Measured 2026-10-29 on the first desktop session after installing 2.57.5: its request carried the complete 2.57.4 digest (tail present) and none of the 2.57.5 sections ("PROJECT PICKER", "CODEMAP FIRST" absent), while the file on disk was rewritten in the same second the session started. The session received the new `ARIA PROJECTS` / `ARIA CODEMAPS` value lines with no instruction for them.

How often: the digest changed in 4 of the last 11 releases; `user-rules.md` changed on 6 days in the last 60; and two installs at different versions (CLI and desktop) rewrite the shared file in turn, making every alternating session stale. A rule the user adds is therefore not followed by the next session, silently.

The hook already handles one shape of this — the digest **absent** at session start (first install). It inlines the whole digest into the model context. That copy is about 26 KB plus the user-rules block, and the hook's own comment records that the harness delivers roughly the first 2,000 characters of hook output, so most of it does not arrive.

## 2. Decisions

- `[DECISION] D1` — Detect by content, not by the write call. Record a checksum of each installed file before `kt_ensure_rules_files` runs and compare after. A file counts as **refreshed** when its content after differs from before, including absent → present. Rationale: the writer already compares content; a checksum pair is the same instrument and needs no change to the writer's return contract.
- `[DECISION] D2` — When any file was refreshed, emit one line in `additionalContext`, never in `systemMessage`:
  `ARIA RULES REFRESHED — <path>[ and <path>] changed or were installed at this session's start, after this session loaded its rules, so the copy in your context is the previous version or absent. Read the named file(s) now, before your next tool call, and follow the file wherever the two differ.`
  The line carries its own instruction because the only digest the model holds is the stale one, which cannot describe a line it has never seen. This is a deliberate exception to "values in the hook, behaviour in the digest".
- `[DECISION] D3` (amended after /prospect) — Retire the inline-digest arm entirely. Measured on a live first-install session (2026-10-29): the inline arm emitted 35.3 KB, the harness delivered a ~2 KB preview ending at the Behavioural Foundation, and the model reported the first working rule absent (it sits at character 2,098 of the output). Every arm now points at a readable file instead:
  - absent before, written now → the notice names the installed file;
  - still absent after the ensure step (write failed) → the notice names the **bundled** digest inside the plugin, which always exists, and the source `user-rules.md`.
  The second caller of `kt_user_rules_block` (the inline arm) goes with it.
- `[DECISION] D4` — Placement. On startup/resume/clear the notice is the first line of the model context. On `compact` it follows the compact block, which keeps leading (an existing acceptance criterion; the rules pointer is the part whose loss does damage). Total stays well under the ~2,000-character preview in every arm.
- `[DECISION] D5` — No new hook, no edit-time regeneration. Regenerating the user-rules file when `user-rules.md` is edited would remove the lag for that half, but needs a post-edit hook, which a standing ruling forbids (session-start checks only). Not pursued.

Alternatives rejected:
- **Inline the new digest on change** — the same ~2,000-character preview cut applies, so the part that changed may not arrive.
- **Inline only the diff** — needs a stored previous copy and a diff renderer in shell; fragile, and still unbounded in size.
- **Do nothing** — the lag self-heals in one session, but that session is the one right after a change, when it matters most, and a new user rule is silently not followed.

## 3. Acceptance criteria

Each AC must be seen red against the current hook before the fix.

- **AC1** Changed digest: with an installed digest that differs from the bundled one, a startup run emits the notice naming `aria-rules.md`, as the first line of `additionalContext`, and leaves the installed digest byte-identical to the bundled one.
- **AC2** Unchanged: a second run with nothing changed emits no notice.
- **AC3** Changed user rules: after `user-rules.md` changes in a way that alters the rendering, the notice names `aria-user-rules.md` and not `aria-rules.md`.
- **AC4** Both changed: the notice names both files.
- **AC5** First install (absent → written): the notice names the installed files; the model context does not contain the digest body; total `additionalContext` stays under 2,000 characters.
- **AC6** Write failed (rules directory unwritable): the notice names the bundled digest path and the source `user-rules.md`; the model context does not contain the digest body.
- **AC7** Compact with a change: the compact block still leads, and the notice is present.
- **AC8** The notice never appears in `systemMessage`, and every new arm parses as strict JSON.
- **AC9** Existing suites stay green: the single-emitter repro, the plugin suite, antigravity bats, codex suite. The real `~/.claude/rules` files are unchanged by any test run (the runner guard).
- **AC10** Tests that asserted rule content in the first-install payload are re-pointed to the digest **file**, where the model now reads it, plus an assertion that the notice names that file. The assertion "the delivered prefix reaches the first rule" is deleted, not re-pointed: it built its prefix with `cut -c1-2000`, which truncates each line rather than the payload, so it could never fail (reproduced: first rule at char 2,102 of a 26,242-char payload, still "in the prefix").

## 4. Out of scope

- Cross-session races (two sessions starting in the same instant): the second may see no change while holding a pre-write snapshot. Accepted; the window is sub-second.
- Other ports: Codex and Cursor do not write these files; Antigravity's port is regenerated by `build.sh` and its tests run.

## 5. Verification

Repro arms in `tests/repros/session-start-single-emitter.sh` for AC1–AC8, each run against the old hook first. A live check after release: the first session after installing it shows the notice, reads the file, and its request carries the new digest's tail.
