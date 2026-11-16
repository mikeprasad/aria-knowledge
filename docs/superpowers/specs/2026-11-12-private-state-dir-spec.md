---
status: DRAFT — /prospect gate 1 PROCEED-WITH-CHANGES (G1-1…G1-4, log knowledge/logs/prospect/2026-11-12-file-private-state-dir-spec.md); awaiting plan
date: 2026-11-12
owner: Mike (rulings 2026-11-12: "Close it in 2.58.0" — the predictable-name overwrite class is in scope; "Private state dir" — the fix shape)
supersedes: the per-site guarding design in the Task 3c census brief (kt_replace_file at 41 sites, never built) and plan Task 4 (codex-hook.py /tmp names)
follows: docs/superpowers/specs/2026-11-11-ledger-framing-and-safe-create-spec.md (Task 3, shipped at e24934f)
---

# One private per-user state directory for all aria hook state

## 1. Problem

Hooks and two skills keep state under predictable names in shared `/tmp` and in `$TMPDIR`
(cooldowns, denial counters, the surfacing ledger, Rule 22 carrier records and anchors, preflight
markers, caches, a debug log). Task 3 guarded the creates and appends. The Task 3c census found the
rest: 41 overwrite sites in six idioms, and three live holes: a FIFO planted at the preflight breaker
name hangs the commit hook; a planted counter at the Rule 22 breaker name switches Rule 22 to
DEGRADED (allow); a planted carrier record carrying the turn's `prompt_id` authorises an edit. It also
measured that `mv -f TMP NAME` moves TMP *into* a directory link, so rename-based fixes are wrong for
directory links. Guarding each site leaves the class open to the next site written. Mike's ruling:
remove the class. Every state name lives in one directory that only the user can write, so a
foreign plant is impossible by construction.

**Threat model.** Another local user (or a process running as one) who can create entries in `/tmp`
and knows or guesses a session id. Out of scope: a process running as the same user (it can already
edit the plugin and the settings).

## 2. Measured on this machine (macOS, 2026-11-12) and unmeasured

| Fact | Result |
|---|---|
| `$TMPDIR` in the model's Bash, the CLI `claude` process, the desktop Claude app, the terminal | all the same per-user dir, mode `drwx------`, owned by the user |
| `getconf DARWIN_USER_TEMP_DIR`; Python `os.confstr(65537)` | equal to `$TMPDIR` (Python has no symbolic name for it; the integer works) |
| launchd-spawned Finder, Dock, cfprefsd | **`TMPDIR` unset** in their environment → the resolver must not assume it is set |
| `/tmp` | a link to `private/tmp`, mode `drwxrwxrwt` (sticky) |
| Candidate resolver cost per hook run (bash / sh, load ~7) | +3.6 ms / +4.1 ms over a bare shell start (200 runs each) |
| Resolver red arms (scratch dir) | link at the dir, mode 755, a regular file at the name, uncreatable parent → all refused; a fresh dir → accepted |
| `CLAUDE_SESSION_ID` in the model's Bash (Claude Code) | **unset**; `CLAUDE_CODE_SESSION_ID` is set. The `/preflight` recording line uses the unset one, yet 14 sid-named markers exist on disk, so either an older release exported it or models substituted by hand — not resolved here |
| aria files in `$TMPDIR` that no sweep covers | e.g. 243 `aria-r22-lastedit-*`, 181 `aria-r22-carrier-*` (today's sweeps only cover the `/tmp` ledger and inprogress names and `.aria-new.*`) |
| Codex suite leak | fake-id `/tmp/aria-session-inprogress-codex-session-tmp*` files present |

**Unmeasured:** Linux (all of it); `$TMPDIR` inside Codex, Cursor and Antigravity hooks (none installed
here); whether Claude Code's Bash sandbox rewrites `$TMPDIR` for the model's commands (if it does, the
model and the hooks resolve different directories — §5 makes the hook's resolution authoritative for
reads); a real launchd or cron run of the plugin's own jobs.

## 3. Decisions

### D1 — Location: one resolver, one ordered base list, no fallthrough on failure

`kt_state_dir` (POSIX sh, in `lib-state-key.sh`, all four shell ports) and `aria_state_dir()`
(Python, `codex-hook.py`) implement the same contract:

1. Base = the first **set, non-empty** value of: `KT_STATE_BASE` (test-only) → `XDG_RUNTIME_DIR` →
   `TMPDIR` → on Darwin `getconf DARWIN_USER_TEMP_DIR` (Python: `os.confstr(65537)`) → `/tmp`.
2. Dir = `<base, trailing / stripped>/aria-knowledge-<uid>`.
3. If it is absent: `mkdir -m 700` (Python: `os.mkdir(d, 0o700)`; `EEXIST` is not an error).
4. Verify once: is a directory, is **not** a link, owner is the current uid, and the permission bits
   are exactly `700` (sh: `[ -d ] && [ ! -L ] && [ -O ]` plus `ls -ldn` starts `drwx------`;
   Python: one `os.lstat`, `S_ISDIR`, `st_uid == getuid()`, `S_IMODE == 0o700`).
5. Pass → print the path, exit 0. Fail at any step → print nothing, exit 1. **Never try the next
   base after a failure**: falling through would let whoever breaks the first choice pick our
   directory, and two processes could disagree about where state lives.

Why this is safe after a single check: the parent is either private (macOS `$TMPDIR`,
`XDG_RUNTIME_DIR`) or sticky (`/tmp`), so no other user can rename or replace our directory between
the check and later use. Inside a `0700` directory no other user can create, link or FIFO an entry.

**Invariant the location must meet:** the directory is shared by every process that descends from
one harness process (its hooks and its model's shell). It need not be shared across harnesses,
reboots or logins — every name in it is keyed on a session, an agent or a content checksum.

Alternatives rejected:
- *Subdir of `$TMPDIR` only (no list).* Fails where `TMPDIR` is unset (measured for launchd-spawned
  processes) and on Linux, where it is usually unset or `/tmp`.
- *`$HOME/.cache/aria-knowledge` (or `$XDG_CACHE_HOME`) as the Linux fallback.* Not squattable, but it
  survives reboots (state accumulates; needs its own sweep), can sit on a network home (latency
  against a ~150 ms hook budget), and puts volatile state in the user's config tree. A squatted
  `/tmp/aria-knowledge-<uid>` only denies service, and D3 makes that safe and visible.
- *Fall through to the next base on failure.* Rejected above.
- *`chmod 700` an owned dir with wrong bits instead of refusing.* A group- or other-writable dir may
  already hold planted entries; tightening the mode does not remove them.
- *A per-session dir.* More directories, more sweeps, and the shared caches (surfacing index, prompt
  config) lose their reuse across sessions. No security gain over a per-user `0700` dir.

### D2 — The one check, and what Task 3's helpers still do

Each hook resolves once per run (+~4 ms measured) and then uses plain `>`, `>>`, `cat` and
`mv -f` inside the directory. No new per-site guards; 3c's `kt_replace_file` is **not built**.

`kt_create_new` / `kt_is_ours` (11 lib copies) and Codex `ledger_is_ours` **stay**, with their
existing call sites, because Rule 13 removes only what is truly redundant and they still protect:
names reached through a path not yet routed through the resolver during the transition; a future
regression that writes outside the directory (the census in D6 is the primary guard, these are the
second); and our own mistakes inside the directory (a hook that created a directory or FIFO where a
file belongs). Their comments that say "the ledger's /tmp name is predictable" are reworded to name
the state directory. Removing them is a separate, later decision.

### D3 — Fail safe per hook when there is no state directory

Every consumer checks the resolver's exit status. No state ⇒ no state is read or written, and:

| State family | Behaviour without the directory |
|---|---|
| Rule 22 denial breaker | Cannot count, never trips: a missing marker **still denies**. The breaker never degrades into allowing. |
| Rule 22 carrier records, last-edit anchor | Not recorded or read; the gate decides from the transcript alone (tail mode). |
| Preflight denial breaker, preflight marker | Marker reads as absent; the breaker never trips; the commit gate keeps its no-marker behaviour. |
| External-fetch cooldown and breaker | Allow (the gate is advisory and already fails open; without a cooldown it would deny forever). |
| bash-cd, codemap and task-context cooldowns; usage warn bands | Emit nothing (a reminder with no cooldown would repeat on every call). |
| Surfacing ledger, surfacing and prompt-config caches | Surface nothing (no dedupe would re-inject the same files every prompt). |
| SESSION.md in-progress cache | Mark anyway (the write is idempotent; costs one SESSION.md read per edit). |
| r22-bypass, preflight-skipped recordings; cursor debug log | Skip. |
| Cursor pending capture/claim; Antigravity model-last and surfaced/logged markers | Skip (inject nothing; log nothing). |
| `/preflight` and `/extract`/`/audit knowledge` skill writes (§5) | The skill says the state directory is unavailable and why, and does not write elsewhere. |

SessionStart (claude-code) adds one user-facing `systemMessage` line when the resolver fails:
`ARIA: private state directory unavailable (<reason>) — hooks are running without state.` The reason
is one of `not created`, `not a directory`, `is a link`, `not owned by you`, `mode not 700`.

### D4 — Contract change: every reader and writer of every moved name

All names keep their file names and move into `<state dir>/`:

| Family | Today | Readers/writers (ports) |
|---|---|---|
| `aria-active-<sid>`, `aria-session-inprogress-<key>`, `aria-bashcd-*`, `aria-codemap-*`, `aria-context-*`, `aria-usage-warn-*` | `/tmp` | shell ports C X U G; Codex Python (`aria-active-`, `aria-context-`, `aria-codex-codemap-*`, `aria-session-inprogress-codex-*`) |
| `aria-extfetch[-denies]-*`, `aria-preflight[-denies,-skipped,-repo]-*`, `aria-r22-{bypass,carrier,denies,lastedit}-*` | `${TMPDIR:-/tmp}` | C X U G (carrier Python inside C's `pre-bash-r22-carrier.sh` and G) |
| `aria-surface-*.tsv`, `aria-surface-hook.log`, `aria-prompt-config.*.cache`, `aria-cursor-*`, `aria-ag-*` | `${KT_SURFACE_CACHE_DIR:-$TMPDIR}` | 11 lib copies; cursor capture/inject; Antigravity `pre-invocation-aria.sh` |
| `aria-hook-debug.log` | `/tmp` | cursor (4 scripts via `aria_hook_dbg`) |
| `aria-digest-<file>` | `/tmp` (skill text) | `/extract`, `/audit knowledge` in C X G + cursor `.mdc` |
| `aria-r22-bypass-<sid>` (read), `aria-active-<sid>` (named) | `${TMPDIR:-/tmp}`, `/tmp` (skill text) | `/handoff`, `/wrapup` read the bypass ledger; `/setup` names the session ledger — C X G + cursor `.mdc` (G1-1: omitted from the first draft of this table) |

`mktemp` scratch names (`aria-match-*.XXXXXX`, `aria-ss-vblk.XXXXXX`) are unpredictable and stay
where they are. Out of class and untouched: `$HOME/.claude/*` (receipts, statusline state),
`$HOME/.gemini/antigravity/*`, project-dir files, the PM marker in the knowledge folder.

`KT_SURFACE_CACHE_DIR` is retired as a location (its default was `$TMPDIR`; it was used only by
tests); tests set `KT_STATE_BASE`. `KT_HOOK_DEBUG_LOG` stays a test-only override. Planned-not-built
`KT_TMP_STATE_ROOT` is dropped.

### D5 — How the model learns the paths, without growing the digest

The digest (`plugin-claude-code/rules/aria-rules.md`, 26,198 B, Mike's bound) says today, in ARIA
ACTIVE CONTEXT: `Skip paths in /tmp/aria-active-$CLAUDE_CODE_SESSION_ID; never use \`ls -t\` over
that glob (wrong session).` (105 B). The hook knows the session id, so it can name the whole path:

- **Read side.** The `ARIA CONFIG` line (claude-code `session-start-check.sh`, the only emitter,
  measured) gains `state_dir=<dir> ledger=<dir>/aria-active-<sid>` (`none` when D3 applies), on
  every SessionStart source including `compact` and `clear`. The digest clause becomes
  `Skip paths in the file named by \`ledger=\` in \`ARIA CONFIG\`.` (59 B, −46 B; no glob to warn
  about). `/prospect` and `/retrospect` (C X G, cursor `.mdc`) point to the same field. (G1-1)
  Every port whose hooks write the ledger states `state_dir=` / `ledger=` in its own session-start
  value line, named `ARIA CONFIG` in each so one skill sentence serves all ports: claude-code in its
  existing line; Codex and Cursor `session-start-check.sh` and Antigravity's PreInvocation
  session-start message each append a separate `ARIA CONFIG — state_dir=… ledger=…` line, keyed on
  the id that port's own ledger writer uses. A runtime with no such line (Cowork) has no hook that
  writes a ledger, so "none or absent ⇒ skip nothing" holds there.
- **Write side.** A new CLI, `scripts/aria-state.sh path <name>` (C X U G), prints
  `<state dir>/<name>` or exits 1 with the D3 reason. `/preflight` runs
  `"$(… path "aria-preflight-${CLAUDE_CODE_SESSION_ID:-${CODEX_THREAD_ID:-}}")"` (empty id ⇒ refuse,
  fixing the unset-variable defect in §2); `/extract` and `/audit knowledge` name their digest
  outputs the same way. The skill compares the printed directory with `state_dir=` when present and
  says so if they differ (the Bash-sandbox case in §2).
- `/auto` and `/statusline` prose that names the marker or the warn files is reworded to "the state
  directory". Cowork `prospect`/`retrospect` describe canonical's ledger path and are reworded too;
  Cowork never reads it.

Rejected: a new `ARIA LEDGER` line plus a digest section to explain it (grows the digest); exporting
`ARIA_STATE_DIR` through `CLAUDE_ENV_FILE` (Claude Code only, a write into a harness-owned file, and
the skills would still need another path in the other ports); hard-coding a path in skill text
(per-user, unknowable).

### D6 — Migration, legacy sweeps, the census

- **Sweeps.** A new sweep removes files older than 24 h inside the state dir (SessionStart, C X U;
  Antigravity housekeeping). The existing `/tmp` sweeps of `aria-active-*`, `aria-session-inprogress-*`
  and `.aria-new.*`, plus a new one-release sweep of the old `$TMPDIR` names (`aria-r22-*`,
  `aria-extfetch*`, `aria-preflight*`, `aria-surface-*`, `aria-prompt-config.*`, `aria-cursor-*`,
  `aria-ag-*`, `-user <uid>`, older than 24 h), stay **for 2.58.0 only**. Removal trigger (Rule 37):
  marker `LEGACY-TMP-SWEEP-2.58`, removed in the first release after 2.58.0, with
  `KT_TMP_SWEEP_ROOT`.
- **Old and new plugin at once on one machine.** Every name is keyed per session, agent or checksum,
  so two sessions never shared state; nothing breaks between a 2.57.x session and a 2.58.0 session
  except duplicate caches (cost only). A **session that switches version mid-run** (a directory
  marketplace re-reads scripts) loses its state once: the ledger restarts (files re-surface once),
  breaker counts restart at 0 (more denials before a trip, never fewer), the fetch cooldown restarts
  (one extra advisory deny per site), a preflight marker written by the old skill is not seen (rerun
  `/preflight`), and carriers recorded before the switch fall back to tail mode.
- **Census test.** `tests/repros/safe-create-census.sh` changes purpose: it FAILS on any literal
  `/tmp/aria-`, `${TMPDIR…}/aria-` or `KT_SURFACE_CACHE_DIR` path in a hook script, a lib, `codex-hook.py`,
  or a SKILL.md/`.mdc` shell block, outside `mktemp` templates and the marked legacy sweeps; plus a
  parity check that the four `kt_state_dir` copies are identical. CC0 controls plant one of each and
  require exactly those reported; a zero-examined run fails. Task 3's CC1–CC5 stay.

### D7 — Codex Python

`codex-hook.py` gains `aria_state_dir()` (D1, ported; the base list and refusal rules are identical,
pinned by a cross-port test). Its four names move into the directory: `aria-context-<key>`,
`aria-active-<key>`, `aria-codex-codemap-<session>-<digest>`, `aria-session-inprogress-codex-<key>`.
~~Plain `open`/`write_text` inside the directory; `O_NOFOLLOW`/`fstat` are not added (the directory
check covers them)~~ ⚠ **AMENDED 2026-11-12 (shipped rule, Task 5 ruling C1):** Codex reads and writes
state only through `state_read` / `state_write`, which open with `O_NOFOLLOW | O_NONBLOCK` and let
`fstat` decide (a regular file is used, anything else is skipped), and create files `0600`. The shell
ports read only regular files and skip a non-file. Why the original text was wrong: a plain `open` on
a FIFO planted at a state name hung the hook for 30 s, and the directory check cannot rule that out —
our own mistake inside the directory can leave a non-file there (D2). `ledger_is_ours` stays (D2). D3 behaviour applies (no dir ⇒ no cooldown, no
ledger, no surfacing; inprogress marks anyway).

Carried from the old Task 4: the three text-mode `subprocess.run` calls without an encoding
(`run_legacy_capture`, `git_value`, the retrospect `rev-list --count`) gain
`encoding="utf-8", errors="replace"`, and their callers catch `ValueError` and `OSError` (a lone
surrogate or a non-UTF-8 locale raised `UnicodeEncodeError` and crashed the hook, as already fixed at
the surfacing call). The Codex suite sets `KT_STATE_BASE` to a scratch dir and asserts `/tmp` gains no
`aria-*` entry during the run (it leaks fake-id inprogress files today, measured).

## 4. Acceptance criteria

1. Every hook in C X U G H and `codex-hook.py` resolves state only through `kt_state_dir` /
   `aria_state_dir`; the D6 census is green and its CC0 plants are all reported.
2. Red-first arms (shell and Python, each port that has the hook): a directory not ours, a link at
   the directory, mode 755, a regular file at the name, an uncreatable parent → resolver exits 1,
   and each D3 row behaves as stated. In particular a planted counter can no longer reach the Rule 22
   or preflight breaker, and with no state dir an unmarked edit is still **denied**.
3. Foreign-entry impossibility is argued, not tested (needs a second uid): mode `0700` owned by the
   user ⇒ only that uid (and root) can create entries. The test asserts the mode and owner, which
   are what the argument depends on.
4. Every port resolves the same directory for the same environment (one test drives all five
   implementations with a fixed `KT_STATE_BASE`, with `XDG_RUNTIME_DIR` set, and with only `TMPDIR`).
5. Resolver latency: p95 added time per hook run ≤ 10 ms at the test machine's load, measured by the
   suite against a bare shell start.
6. `ARIA CONFIG` carries `state_dir=` and `ledger=` on startup, compact and clear; the digest clause is
   replaced and the digest is smaller than before (the exact size test, if any, is updated to the
   new measured size).
7. `/preflight`'s recorded marker satisfies the commit gate in a live Claude Code session (I-check after
   install), and refuses to write with an empty session id.
8. No test writes the real `/tmp` or `$TMPDIR` (`plugin-suite-leaves-real-tmpdir-alone.sh` plus a
   before/after count of `aria-*` in both).
9. All five gates bare exit 0; PORT-LEDGER re-baselined one port per edit; Cowork tree changes only in
   the two reworded skills.

## 5. Risks

- **Model and hooks disagree on the directory** (a sandbox or a harness that rewrites `TMPDIR` for the
  model's shell). Reads are safe (the hook names the path); writes are caught by the D5 comparison.
  Unmeasured; I-check in a sandboxed session.
- **Linux `/tmp/aria-knowledge-<uid>` squatted by another user** → permanent degraded mode until it
  is removed. Safe by D3 and visible at SessionStart; an admin removes it.
- **`TMPDIR` cleanup by macOS** (files unused for days) removes state mid-session: same effect as the
  mid-run version switch (§D6), all fail safe.
- **Breaker never trips without state** ⇒ a user whose state dir is broken and whose markers are not
  detected is denied until they fix the dir. Accepted by Mike's rule; the SessionStart line names
  the fix.
- Behaviour change for anyone who set `KT_SURFACE_CACHE_DIR` outside tests (none known).

## 6. Port parity, PORT-LEDGER, CHANGELOG

- Canonical first: `lib-state-key.sh` (+`kt_state_dir`), `aria-state.sh` (new), every hook, the
  session-start line and sweeps, skills; then `plugin-antigravity/build.sh`; hand-port codex shell,
  cursor scripts, Antigravity `bin/antigravity/pre-invocation-aria.sh`, `codex-hook.py`; regenerate
  cursor `.mdc`; hand-edit cursor `QUICKSTART.md`.
- PORT-LEDGER: re-baseline each tracked surface that changes (the skills named in D5, and the two lib
  surfaces), one port per `--update`, `port-drift-check.sh` after each.
- CHANGELOG 2.58.0: all hook state moves to one private per-user directory (location rule, D3
  degraded behaviours); `ARIA CONFIG` gains `state_dir=`/`ledger=`; `/preflight` takes the session id
  from `CLAUDE_CODE_SESSION_ID`; new `aria-state.sh`; `KT_SURFACE_CACHE_DIR` retired; legacy `/tmp` and
  `$TMPDIR` sweeps for one release; Codex encoding fixes; known limit: a mid-run version switch
  restarts state once.

## 7. Open for Mike

1. Whether the Cowork rewording ships as Cowork 1.8.3 with 2.58.0 or rides unreleased (Cowork never
   reads the path; it is accuracy only).
2. Whether the 26,198 B digest bound is a ceiling (this shrinks it by 46 B) or an exact pin.

## 8. 2.58.0 additions — Mike's rulings 2026-11-15

Ledger: `knowledge/logs/auto/2026-11-13-aria-2580-private-state-dir-judgments.md` (J1, J2, J3, all
REVISIT). These three join the release; Task 10 waits for them.

### D8 — Antigravity's Rule 22 gate reads the deny the check prints (J2 → A1)

**Measured 2026-11-15:** the canonical `pre-edit-check.sh` always exits 0. An unmarked edit prints
`{"hookSpecificOutput":{…"permissionDecision":"deny"…}}`; a marked edit prints nothing.
`plugin-antigravity/bin/antigravity/pre-edit-aria.sh` reads only the exit code (`2>&1` into one
variable, non-zero ⇒ deny), so both become `allow`. Rule 22 has never blocked an Antigravity edit
since `b524c6a`, while `PORTING.md` says "Documented + fail-closed".

The wrapper decides from the check's **stdout**, captured apart from stderr:

| Check result | Wrapper decision |
|---|---|
| stdout holds `permissionDecision` = `deny` | `deny`, reason = `permissionDecisionReason` |
| stdout holds a `systemMessage` (could-not-verify or degraded mode) | `allow`, reason = that message |
| exit 0, stdout empty | `allow` |
| exit non-zero, or stdout not parseable JSON | `deny` with a fixed reason naming the failure (fail closed, as `PORTING.md` states) |

Parse with `jq` (the wrapper already requires it).

**What D8 does NOT establish (prospect 2026-11-15):** that Rule 22 now blocks unmarked edits in a
real Antigravity session. The canonical reader parses a JSONL transcript (`step_index`,
`source:"MODEL"`), while Antigravity's conversations on this machine are protobuf
(`~/.gemini/antigravity/conversations/*.pb`). If the hook's `transcriptPath` names that file the
reader returns "could not verify" and D8 correctly maps it to allow-with-warning. No real payload has
ever been captured (the one-shot probe was consumed by a bats run, see D8a). The CHANGELOG states
the mechanism and names the live check as owed; it does not claim enforcement.

Rejected: grepping stdout for the word `deny`
(the reason text the model reads can contain it); making the canonical script exit non-zero on deny
(Claude Code reads stderr on exit 2 and the canonical contract is shared by three ports).
The one-shot first-run probe block is unchanged.

### D8a — Antigravity tests never touch the real home directory

`test-pre-edit-aria.bats` and `test-post-edit-aria.bats` run the wrappers without setting `HOME`, so
they write the real `~/.gemini/antigravity/` (measured: a 376-line `aria-knowledge-scope-check.log`
last written by this arc's test runs on 2026-11-14, and a `.aria-probe-fired` flag written on
2026-05-24 by `test-pre-edit-aria.bats` — the probe's log carries `BATS_TEST_FILENAME`). Same class as
AC8, one directory over (Rule 38): both suites export `HOME` to their scratch dir, and a census arm
fails on any Antigravity bats file that runs a wrapper without it. The real files already written
are Mike's to remove (outside the repo); removing the probe flag re-arms the real-payload capture.

### D9 — One session-key rule, applied to the same bytes (J1 → "make them agree")

The shell (`kt_session_key`, every shell port) takes the **first textual** `"<field>" : "<value>"` in
the raw JSON, `[^"]*` value, then the accept set. Codex's Python (`session_key`) takes the
**decoded** value from `json.loads`. They disagree on (a) a `\uXXXX` escape of an allowed character
(shell rejects, Python accepts) and (b) a duplicated key (shell takes the first, `json.loads` the
last). Closing the class: Python extracts the field from the **raw stdin text** with the shell's
rule (same field order `session_id`, `turn_id`; same whitespace tolerance; first textual match;
value up to the next `"`), then applies `session_key_check`. Every Python caller that keys state
passes the raw text. Rejected: a JSON-escape decoder in POSIX sh (large, new parsing surface in a
deny gate); "Python rejects any backslash" alone (closes (a), leaves (b)). The CHANGELOG known-limit
line for the escape gap is removed.

### D10 — Split retention: proof files 30 days, everything else 24 h (J3 → O1)

"Finished" cannot be measured on three of four ports (Codex, Cursor, Antigravity register no session
end; Claude Code's `SessionEnd` is best-effort, 1.5 s budget, not documented to fire on a kill). The
bound that holds everywhere is how long a session can still be resumed: Claude Code deletes a
transcript after `cleanupPeriodDays`, default 30 (docs, `code.claude.com/docs/en/claude-directory`;
that a deleted transcript cannot be resumed is implied, not stated).

- **Proof files — kept 30 days (`-mmin +43200`):** `aria-preflight-<sid>`,
  `aria-preflight-skipped-*`, `aria-preflight-repo-*`, `aria-r22-bypass-*`, `aria-active-*`,
  `aria-ag-surfaced-*`. `aria-preflight-denies-*` is a counter, NOT proof — excluded by name.
- **Everything else — 24 h (`-mmin +1440`),** unchanged.
- **One definition:** a function `kt_state_sweep` in `lib-state-key.sh` (every shell port's copy)
  holds both lists and runs the one `find`; the four sweeping scripts (C X U session-start,
  Antigravity `pre-invocation-aria.sh`) call it instead of their inline `find`. Same safety shape
  as today: top level only, `-type f`, never follows links, only after `kt_state_resolve` succeeded.
- **Stated limit:** on macOS the directory is inside the system temp folder, which macOS may clear
  on its own (§5, unmeasured), so 30 days is the most aria keeps, not a guarantee. A preflight from
  weeks ago is weak evidence anyway; the bound is retention, not validity.
- The CHANGELOG known-limit line for the 24-hour cross-session sweep is rewritten to this rule.
- The legacy `/tmp` and `$TMPDIR` sweeps (`LEGACY-TMP-SWEEP-2.58`) are unchanged.

### Acceptance criteria (additions)

10. **D8, red first:** an Antigravity bats/repro arm feeds the wrapper an unmarked edit and asserts
    `"decision":"deny"` — red on `354cb82`; a marked edit asserts `allow`; a check that exits
    non-zero and one that prints non-JSON each assert `deny`; a `systemMessage` result asserts
    `allow` carrying the message. Every arm runs with `HOME` in scratch. The CHANGELOG placeholder at
    line 90 becomes a fix entry that claims the wrapper's decision only and names the live
    Antigravity check as owed; `PORTING.md` gains one line saying aria's detection is unverified in
    a live session.
11. **D9:** the cross-port test (M8 in `tests/repros/state-dir-model-facing.sh`) gains cases — an id
    written with a `\u` escape, a duplicated `session_id`, `"session_id" : "x"` spacing — and shell
    and Python give the same key or the same rejection for each; the escape and duplicate cases are
    red on `354cb82`.
12. **D10:** the sweep arms plant each proof name and a churn name at 2 days and at 31 days old:
    proof at 2 days kept, proof at 31 days removed, churn at 2 days removed, `aria-preflight-denies-*`
    at 2 days removed; red on `354cb82` for "proof at 2 days kept". A census arm fails if any of the
    four sweeping scripts still carries its own in-dir `find` instead of `kt_state_sweep`. The
    existing arm that plants `aria-active-indir-old` at OLD and expects it removed FLIPS under D10
    (a proof name younger than 30 days is kept): rewrite it deliberately, labelled as a D10 change,
    with a churn name in its place for the removal half.
13. All five gates bare exit 0 after each; PORT-LEDGER re-baselined per port; public-hygiene clean.
14. **D8a:** a census arm lists every `plugin-antigravity/tests/*.bats` that invokes a
    `bin/antigravity/*-aria.sh` wrapper and fails on any without a scratch `HOME`; red on `354cb82`
    naming `test-pre-edit-aria.bats` and `test-post-edit-aria.bats`; a full Antigravity bats run
    leaves the real `~/.gemini/antigravity/` file list and mtimes unchanged (before/after listing).
