# One private per-user state directory — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move every predictable-name hook state file (cooldowns, breakers, ledger, carriers, markers, caches, debug logs) out of shared `/tmp` and `$TMPDIR` into one directory only the user can write, so a foreign plant is impossible by construction, with a stated fail-safe for every hook when that directory is unavailable.

**Architecture:** One resolver contract, implemented twice (POSIX sh in `lib-state-key.sh` ×4 ports; Python in `codex-hook.py`), picks the first set base, creates `<base>/aria-knowledge-<uid>` with mode 700 and verifies it once (dir, not a link, ours, exactly 700) — never falling through to another base. Hooks resolve once per run and build every state name with `kt_state_path` / `aria_state_path`; libraries read the resolved directory from the caller. The model learns the paths from a per-port `ARIA CONFIG` value line (`state_dir=` / `ledger=`), and skills write through a new CLI `aria-state.sh path <name>`.

**Tech Stack:** POSIX sh + BWK awk (all four shell ports), bash (Antigravity hand-authored hook), Python 3 (`plugin-openai-codex/bin/codex-hook.py`), bats (Antigravity tests).

**Spec:** `docs/superpowers/specs/2026-11-12-private-state-dir-spec.md` (binding, D1–D7, AC1–AC9). Gate-1 /prospect changes G1-1…G1-4 (log `knowledge/logs/prospect/2026-11-12-file-private-state-dir-spec.md`) are applied below and override the spec where they differ. Inputs: census brief `.superpowers/sdd/2026-11-11-ledger-framing-and-safe-create-plan/task-3c-brief.md` (41 sites, W1–W6, the `mv`-onto-dir-link trap) and that folder's `progress.md`. This plan also absorbs Task 5 and Task 6 of `docs/superpowers/plans/2026-11-11-ledger-framing-and-safe-create-plan.md` (Task 4 there is superseded by T5 here).

## Global Constraints

- Shell is `sh` (bash 3.2 as `/bin/sh` on macOS) or bash for the Antigravity hand-authored hook — never zsh. No bashisms in any `lib-*.sh` (no `local`, no `[[`, no arrays). BWK/POSIX awk only.
- Every directory-dependent command is one parenthesised absolute cd: `(cd "$WT" && <cmd>)`, `$WT` = `<worktree>` (branch `release/2.58.0`, base of this plan `e24934f`). Never a bare `cd`.
- Before every Edit/Write emit the Rule 22 marker through Bash: `cat <<'R22'` / `[Rule 22] LOW|HIGH IMPACT — <what>` / `R22`.
- Byte-identical library sets (edit canonical `plugin-claude-code/scripts/`, `cp` to cursor `scripts/aria/` and codex `bin/`, Antigravity via `build.sh`, then `cksum` every copy): `lib-state-key.sh` ×4 (measured 461636906 at `e24934f`), `lib-prompt-surface.sh` ×3 (C U G), `lib-index-match.sh` ×4, `lib-tracked-artifacts.sh` ×4. `lib-session-state.sh` parity is per function (unchanged by this plan).
- Antigravity generated files (`plugin-antigravity/bin/*.sh`, `skills/`, `rules/`) ONLY via `(cd "$WT" && ./plugin-antigravity/build.sh)`. `plugin-antigravity/bin/antigravity/pre-invocation-aria.sh` is hand-authored (H).
- Cursor `.mdc` ONLY via `(cd "$WT" && python3 plugin-cursor-template/scripts/port-skills-to-mdc.py)`. Run both generators on the clean tree before a task's first edit; if either changes anything, STOP and report (pre-existing drift is never absorbed into a task).
- Never `check-port-drift.sh --update all`. A task that changes a PORT-LEDGER-tracked surface re-baselines it **in that task**, one `--update <port>` at a time after verifying that port, re-running `sh plugin-claude-code/scripts/check-port-drift.sh` after each (ruling of Task 3: gates green per task).
- Tests never touch the real `/tmp`, the real `$TMPDIR` state, `~/.claude/rules` or a real `SESSION.md`. State goes under `KT_STATE_BASE` (a `mktemp -d` scratch dir); sweeps under `KT_TMP_SWEEP_ROOT`; `HOME` isolated for any session-start run; close stdin on any hook run by hand (`</dev/null`).
- To force "no state directory" in a test, set `KT_STATE_BASE` to a scratch dir and create a **regular file** at `$KT_STATE_BASE/aria-knowledge-$(id -u)` (deterministic refusal, reason `not a directory`).
- Digest `plugin-claude-code/rules/aria-rules.md`: bound is a CEILING ≤ 26,198 B (G1-2). Only T4 edits it (−46 B → 26,152 B). The per-rule digest lock (`plugin-claude-code/tests/lib-digest-lock.sh` covers `- **Rule N — ` lines only) must stay green **without relock** — if it goes red, report, do not relock.
- Gate B / Cowork summed descriptions unchanged: `(cd "$WT" && git diff e24934f -- '*SKILL.md' | grep -E '^[-+]description:')` prints nothing. Cowork (`plugin-claude-cowork/`) changes only in `skills/prospect/SKILL.md` and `skills/retrospect/SKILL.md` (T4).
- Public repo: placeholders `proj-a` / `proj-b` only; no home paths, private names or real ids in code, fixtures, commit messages or docs.
- Commit with `git commit -F -` + heredoc; stage named paths only; message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. After every commit: `(cd "$WT" && sh plugin-claude-code/scripts/check-public-hygiene.sh "$WT")` → exit 0 (exit 2 = the gate's self-test failed). No push, no version bump, no release.
- Each guard gets one mutation: back up (`cp f "$SCRATCH/f.bak"`), mutate, run, observe the NAMED arm go red for the NAMED reason, restore with `cp`, `cmp` against the backup.
- **GATES** at the end of every task, each read as a bare exit code (never through a pipe): `sh tests/run.sh` · `sh plugin-claude-code/tests/run.sh` · `sh plugin-openai-codex/tests/run.sh` · `bats plugin-antigravity/tests/` · `sh tests/repros/claude-ai-upload-limits.sh`. If the real-rules guard in `tests/run.sh` fails, check whether another session's SessionStart rewrote `~/.claude/rules` during the run before treating it as a defect.
- Port letters (census): C = claude-code `scripts/` (canonical) · X = codex `bin/` (hand-ported) · U = cursor `scripts/aria/` (hand-ported) · G = antigravity `bin/` (generated) · H = antigravity `bin/antigravity/pre-invocation-aria.sh`.

## Review Focus

1. **`TMPDIR` unset (launchd, cron) on macOS** — the base resolves to `getconf DARWIN_USER_TEMP_DIR`, i.e. the same directory a `TMPDIR`-set process resolves; sh and Python agree. → T1 arm `R_base_tmpdir_unset` (compares bases only; never creates in the real temp dir).
2. **Two hooks creating the directory at the same moment** (first prompt fires several hooks) — both succeed, same path, mode 700. → T1 arm `R_concurrent_create`.
3. **The directory deleted mid-session** (macOS temp cleanup) — the next hook recreates it 0700 and nothing errors. → T1 arm `R_recreate_after_delete`.
4. **A pathological umask** (000 or 077, or 0700 for Python's `os.mkdir`) — the created directory is exactly 0700. → T1 arms `R_umask_000`, `R_umask_077`, `test_state_dir_mode_is_exact_under_umask`.
5. **A session/conversation id containing `/` or equal to `..`** — no file is written outside the state directory (`kt_state_path` / `aria_state_path` refuse the name). → T1 arm `R_name_with_slash_refused`; T5 `test_state_name_with_slash_refused`.

## Task order and why

T1 resolver (no call sites) → T2 the `${TMPDIR}` security families (the three live holes) → T3 the `/tmp` reminder families → T4 surfacing family (shell, all ports) → T5 Codex Python → T6 model-facing (ARIA CONFIG, digest, skills) → T7 census + sweeps → T8 prose / CHANGELOG / emitter sentence (old Task 5) → T9 whole-branch review + /retrospect + STOP.
Families, not ports, set the boundaries: a state name has writers and readers in several ports, and moving one side alone breaks the other side's tests. Codex's shell ledger sites move in T4 with the other shell ledger writers; codex-hook.py's ledger moves in T5 (interim on an unreleased branch: Codex shell and Python ledgers differ for one task — no test pins them together; T5 restores it). The `/preflight` skill writes the marker to the old place until T6 (hook tests plant their own marker; interim only). Census + sweeps come after every writer has moved, so their ban arm is green when they land.

---

### Task 1: Resolver — `kt_state_*` ×4, `aria_state_*` in Python, `aria-state.sh` CLI, test isolation

**Files:**
- Modify: `plugin-claude-code/scripts/lib-state-key.sh` (canonical); `cp` → `plugin-cursor-template/scripts/aria/lib-state-key.sh`, `plugin-openai-codex/bin/lib-state-key.sh`; G via `build.sh`
- Create: `plugin-claude-code/scripts/aria-state.sh`; `cp` → `plugin-openai-codex/bin/aria-state.sh`, `plugin-cursor-template/scripts/aria/aria-state.sh`; G via `build.sh`
- Modify: `plugin-openai-codex/bin/codex-hook.py` (functions only — no call site changes in this task)
- Modify (isolation): `tests/run.sh`, `plugin-claude-code/tests/run.sh`, `plugin-openai-codex/tests/run.sh` (each exports `KT_STATE_BASE=$(mktemp -d …)` with cleanup trap); `setup()` of all 8 `plugin-antigravity/tests/*.bats` (export `KT_STATE_BASE` inside the file's existing scratch dir)
- Create test: `tests/repros/state-dir-resolver.sh`; Modify test: `plugin-openai-codex/tests/test_codex_port.py`

**Interfaces (Produces — used by every later task):**
- `kt_state_base` — prints the chosen base with ALL trailing `/` stripped: first set non-empty of `KT_STATE_BASE` → `XDG_RUNTIME_DIR` → `TMPDIR` → (only if `uname -s` = `Darwin`) `getconf DARWIN_USER_TEMP_DIR` → `/tmp`. Pure: no mkdir. `uname`/`getconf` are forked only when the three variables are unset.
- `kt_state_resolve` — no subshell; sets `KT_STATE_DIR` (path or empty) and `KT_STATE_REASON` (empty or one of exactly `not created`, `not a directory`, `is a link`, `not owned by you`, `mode not 700`); returns 0/1. Dir = `$(kt_state_base)/aria-knowledge-$(id -u)`. If neither `-e` nor `-L`: `mkdir -m 700` (failure ignored, then re-checked). Check order: `-L` → `is a link`; absent → `not created`; not `-d` → `not a directory`; `ls -ldn` field 3 ≠ `id -u` → `not owned by you`; `ls -ldn` field 1 not starting `drwx------` → `mode not 700`. Never tries another base after a failure (D1.5). Owner is compared from `ls -ldn` rather than `[ -O ]` (same fact, POSIX, and the `ls` is needed anyway for the mode).
- `kt_state_dir` — `kt_state_resolve` then prints `$KT_STATE_DIR`; exit 0/1, silent on failure (spec's name).
- `kt_state_path NAME` — prints `$KT_STATE_DIR/NAME`; returns 1 and prints nothing when `KT_STATE_DIR` is empty or NAME is empty, `.`, `..` or contains `/`.
- At source time the lib sets `KT_STATE_DIR=` and `KT_STATE_REASON=` (an inherited value is never trusted; resolution is per process). `kt_agent_suffix` unchanged.
- CLI `aria-state.sh path <name>` — sources the sibling `lib-state-key.sh`; prints the `kt_state_path` result, exit 0; else prints `aria-state: <reason>` (or `aria-state: invalid name`) to stderr, exit 1. Any other usage → usage line on stderr, exit 2.
- Python (`codex-hook.py`): `aria_state_base() -> str`, `aria_state_resolve() -> tuple[Path | None, str]` (reason strings identical to sh), `aria_state_dir() -> Path | None`, `aria_state_path(state_dir: Path | None, name: str) -> Path | None` (same refusals as `kt_state_path`). Darwin base: `os.confstr(65537)` when `sys.platform == "darwin"`. Create with `os.mkdir(d, 0o700)` then, **only when that mkdir succeeded**, `os.chmod(d, 0o700)` (parity with `mkdir -m`, which ignores umask); `FileExistsError` is not an error. Verify with one `os.lstat`: `S_ISLNK` → link, `S_ISDIR`, `st_uid == os.getuid()`, `S_IMODE == 0o700`. All `OSError` → `(None, "not created")` unless a later check names a sharper reason.

- [ ] **Step 1: Generators clean** — run both generators on the clean tree, `git status --porcelain` shows only untracked docs; else STOP.
- [ ] **Step 2: Write failing tests** in `tests/repros/state-dir-resolver.sh` (each arm in its own scratch base; `L=` the canonical lib):
  - `R_fresh`: fresh base → `kt_state_dir` exit 0, prints `$base/aria-knowledge-$(id -u)`, `ls -ldn` shows `drwx------` and uid = `id -u`.
  - `R_link_at_dir`: symlink at the name → a 0700 dir → exit 1, nothing printed, `KT_STATE_REASON` = `is a link`.
  - `R_mode_755`: pre-created dir mode 755 → `mode not 700`; mode stays 755 (no chmod).
  - `R_file_at_name`: regular file → `not a directory`.
  - `R_unwritable_parent`: base mode 500 → `not created` (skip with a printed SKIP when `id -u` = 0).
  - `R_foreign_owner`: `PATH` prefixed with a stub `id` printing `99999` → dir `aria-knowledge-99999` created by us → `not owned by you`. (Real foreign ownership needs a second uid: argued in spec AC3, not tested.)
  - `R_no_fallthrough`: `KT_STATE_BASE` broken (file at name) while `TMPDIR` points at a healthy scratch → exit 1 and NO `aria-knowledge-*` appears under that `TMPDIR`.
  - `R_base_order`: (a) all of `KT_STATE_BASE`, `XDG_RUNTIME_DIR`, `TMPDIR` set to distinct scratch dirs → `KT_STATE_BASE` wins; (b) unset it → `XDG_RUNTIME_DIR`; (c) only `TMPDIR`; (d) `TMPDIR=$s///` → no `//` in the path; (e) empty-string `KT_STATE_BASE=''` is skipped.
  - `R_base_tmpdir_unset` (Review Focus 1, Darwin only, else SKIP): `env -u KT_STATE_BASE -u XDG_RUNTIME_DIR -u TMPDIR` → `kt_state_base` = `getconf DARWIN_USER_TEMP_DIR` with trailing `/` stripped. Base only — never resolves (would create in the real temp dir).
  - `R_concurrent_create` (RF2): 8 background `kt_state_dir` on a fresh base → all exit 0, one distinct path, mode 700.
  - `R_recreate_after_delete` (RF3): resolve, `rm -rf` the dir, resolve → exit 0, mode 700.
  - `R_umask_000`, `R_umask_077` (RF4): `umask 000` / `077` then resolve fresh → `drwx------`.
  - `R_name_with_slash_refused` (RF5): `kt_state_path 'a/../../x'`, `'..'`, `'.'`, `''` → exit 1, no output; `kt_state_path aria-active-x` → `$dir/aria-active-x`.
  - `R_source_resets`: `KT_STATE_DIR=/elsewhere sh -c '. $L; printf %s "$KT_STATE_DIR"'` prints empty.
  - `R_cli`: `aria-state.sh path aria-active-x` → `$dir/aria-active-x`, exit 0; broken base → stderr `aria-state: not a directory`, exit 1, empty stdout; `path 'a/b'` → `aria-state: invalid name`, exit 1; no args → exit 2.
  - `R_parity_sh`: `lib-state-key.sh` ×4 (C X U G) one `cksum`; `aria-state.sh` ×4 one `cksum`.
  - `R_parity_py` (AC4): for env sets (a) `KT_STATE_BASE` only, (b) `XDG_RUNTIME_DIR`+`TMPDIR`, (c) only `TMPDIR` — all scratch — the sh `kt_state_dir` and `python3 -I -c` loading `codex-hook.py` (via `importlib.util`, `ARIA_CODEX_PLUGIN_ROOT` set) printing `aria_state_dir()` produce the same string; and for (d) the Darwin unset case, `kt_state_base` = `aria_state_base()`. Same refusal reason for the file-at-name and mode-755 fixtures.
  - `R_latency` (AC5): a `python3 -I` driver times 100 runs each of `sh -c '. "$L"; kt_state_resolve'` and `sh -c :` on a resolved base; p95(resolver) − p95(bare) ≤ 10 ms; print both p95s.
  - Python in `test_codex_port.py`: `test_state_dir_refuses_link`, `test_state_dir_refuses_mode_755`, `test_state_dir_refuses_file_at_name`, `test_state_dir_refuses_unwritable_parent`, `test_state_dir_refuses_foreign_owner` (monkeypatch `os.getuid` to return uid+1 → `not owned by you`), `test_state_dir_mode_is_exact_under_umask` (`os.umask(0o777)` around a fresh resolve → mode 0o700), `test_state_dir_never_falls_through`, `test_state_path_refuses_slash_dot_empty`.
- [ ] **Step 3: Run red** — `sh tests/repros/state-dir-resolver.sh` → every arm FAILS (functions absent); codex tests FAIL (`AttributeError`). Record any arm that is green now: it tests the wrong thing.
- [ ] **Step 4: Implement** the lib functions, the CLI, the Python functions (spec D1); `cp` the lib and CLI to X and U; `./plugin-antigravity/build.sh`; `cksum` all four of each. Then add `KT_STATE_BASE` to the three runners and the 8 bats `setup()`s (unused until T2; harmless).
- [ ] **Step 5: Run green** — the new repro and `sh plugin-openai-codex/tests/run.sh`.
- [ ] **Step 6: Mutations** (one each): (a) in `kt_state_resolve`, on failure try the next base → `R_no_fallthrough` red; (b) delete the `-L` check → `R_link_at_dir` red with reason not `is a link`; (c) `chmod 700` an existing dir instead of refusing → `R_mode_755` red ("mode stays 755"); (d) drop Python's post-mkdir `chmod` → `test_state_dir_mode_is_exact_under_umask` red; (e) in `kt_state_path` stop refusing `/` → `R_name_with_slash_refused` red.
- [ ] **Step 7: GATES.**
- [ ] **Step 8: Commit** `feat(state): one resolver for a private per-user state directory (sh ×4, Python), aria-state.sh path CLI; suites isolate KT_STATE_BASE` — the 4 libs, 4 CLIs, `codex-hook.py`, 3 runners, 8 bats files, the two tests. Hygiene gate.

---

### Task 2: `${TMPDIR}` security families → state dir (Rule 22, preflight, bypass, external fetch)

Closes the three live holes in the census (planted FIFO at the preflight breaker; planted counter → Rule 22 DEGRADED; planted carrier → compliant).

**Files** (each script sources `lib-state-key.sh` — C pre-edit/preflight/extfetch already do — and calls `kt_state_resolve` once, before its first state read):
- C: `pre-edit-check.sh` (`BREAKER_STATE`, `CARRIER_STATE`, `ANCHOR_STATE` incl. its `.$$` temp), `pre-bash-r22-carrier.sh` (`ARIA_R22_TMP` = `$KT_STATE_DIR`; when resolve fails the hook exits 0 before spawning Python), `pre-bash-write-check.sh` (`aria-r22-bypass-<sid>`), `pre-commit-preflight-check.sh` (`aria-preflight-denies-*`, `aria-preflight-<sid>`, `aria-preflight-skipped-<sid>`), `pre-external-fetch-check.sh` (`aria-extfetch-denies-*`, `aria-extfetch-<sid>-<key>`)
- X: `pre-bash-write-check.sh`, `pre-commit-preflight-check.sh` (also `aria-preflight-repo-<hash>`), `pre-external-fetch-check.sh`
- U: `pre-bash-write-check.sh`, `pre-commit-preflight-check.sh`, `pre-external-fetch-check.sh`
- G: `./plugin-antigravity/build.sh`
- Tests: create `tests/repros/state-dir-hooks-security.sh`; repoint (plant/inspect under `$KT_STATE_BASE/aria-knowledge-$(id -u)/` instead of `${TMPDIR}`): `tests/repros/r22-circuit-breaker.sh`, `r22-carrier-side-channel.sh`, `r22-tail-anchor.sh`, `r22-scope-line-not-a-marker.sh`, `r22-subagent-transcript.sh`, `hook-markers-safe-create.sh`, `bash-write-target-resolution.sh`, `plugin-claude-code/tests/test-preflight-gate.sh`, `test-external-fetch-gate.sh`, `test-safe-create.sh` (only the arms for these names), `plugin-antigravity/tests/test-pre-edit-aria.bats`.

**Interfaces:**
- Consumes: `kt_state_resolve`, `kt_state_path` (T1). All names keep their file names (D4). Existing `kt_create_new`/`kt_is_ours` call sites stay (D2); only their "predictable /tmp name" comments are reworded to name the state directory.
- D3 behaviour without the directory (exact): Rule 22 breaker cannot count and never trips — a missing marker still **denies**; carriers/anchor not recorded or read → tail mode; preflight marker reads absent, breaker never trips, commit gate keeps its no-marker behaviour; external fetch → **allow**; bypass / preflight-skipped recordings → skipped.

- [ ] **Step 1: Write failing arms** in `state-dir-hooks-security.sh`, driven per port that has the hook (pre-edit C G; carrier C; preflight C X U G; extfetch C X U G; bypass C X U G). "Broken" = file at the state name (Global Constraints); old-location plants go in a scratch `TMPDIR`:
  - `S1 r22_no_state_unmarked_edit_denied_x4`: four unmarked edits with broken state → four `deny` decisions; output never contains `DEGRADED`.
  - `S2 r22_old_location_counter_ignored`: healthy state, `9` planted at `$TMPDIR/aria-r22-denies-<key>` → unmarked edit denied, not DEGRADED.
  - `S3 r22_old_location_carrier_ignored`: healthy state, a carrier record carrying the turn's `prompt_id` planted at `$TMPDIR/aria-r22-carrier-<key>` → edit not treated as compliant (deny).
  - `S4 r22_no_state_tail_mode`: broken state → carrier hook exit 0 and the scratch `TMPDIR` listing is unchanged; pre-edit with the marker present in the transcript → allow.
  - `S5 preflight_no_state_breaker_never_trips`: broken state, 5 commits without a marker → 5 identical no-marker responses, none the tripped message.
  - `S6 preflight_old_location_fifo_no_hang`: FIFO at `$TMPDIR/aria-preflight-denies-<sid>` → hook returns within 2 s (background run + bounded wait + kill).
  - `S7 extfetch_no_state_allows`: broken state, 3 fetches → no deny output, exit 0 each.
  - `S8 markers_no_state_write_nothing`: broken state → bypass and preflight-skipped paths write nothing in `TMPDIR`, `/tmp` scratch or `KT_STATE_BASE` (listings unchanged).
  - `S9 names_land_in_state_dir`: healthy state, one denial each → `aria-r22-denies-<key>`, `aria-extfetch-denies-<sid>`, `aria-preflight-denies-<sid>` exist under the state dir and nowhere under `TMPDIR`; a marker the test writes at `<dir>/aria-preflight-<sid>` satisfies the commit gate (C X U G), and X's `aria-preflight-repo-<hash>` too.
- [ ] **Step 2: Repoint the existing tests** listed under Files to the state dir (`KT_STATE_BASE` from the runner); run them on `e24934f` code — they now FAIL where they plant/inspect the new location (expected), and still PASS elsewhere.
- [ ] **Step 3: Run red** — S1–S9: S2, S3, S6, S9 FAIL (hooks read `${TMPDIR}`); S1/S5/S7/S8 FAIL or PASS-for-the-wrong-reason (state is in `TMPDIR` regardless of the broken base) — record which.
- [ ] **Step 4: Implement** C → `build.sh` → hand-port X, U. `pre-bash-write-check`'s `_bw_sid` goes through `kt_state_path` (a `/` in it now refuses instead of addressing a path).
- [ ] **Step 5: Run green** — the new repro + every test listed under Files.
- [ ] **Step 6: Mutations:** (a) pre-edit's breaker path falls back to `${TMPDIR:-/tmp}` when resolve fails → S1 red (counter reaches DEGRADED via planted/old file) or S2 red — name which; (b) treat "no state" as DEGRADED in pre-edit → S1 red; (c) extfetch denies when no state → S7 red; (d) carrier hook writes to `${TMPDIR}` when no state → S4 red.
- [ ] **Step 7: GATES.**
- [ ] **Step 8: Commit** `fix(hooks): Rule 22, preflight, bypass and fetch state live in the private state dir; no state never degrades a gate into allowing` — C X U scripts, G rebuild, tests. Hygiene gate.

---

### Task 3: `/tmp` reminder families → state dir (cooldowns, usage bands, in-progress cache, Cursor debug log)

**Files:**
- C: `bash-cd-check.sh` (cooldown `aria-bashcd-*` only — its ledger lines are T4), `pre-explore-codemap-check.sh` (`aria-codemap-*`), `task-context-check.sh` (cooldown `aria-context-<sid>` only), `usage-threshold-inject.sh` (`aria-usage-warn-<sid>`), `post-edit-check.sh` (`aria-session-inprogress-<key>`)
- X: `bash-cd-check.sh`, `pre-explore-codemap-check.sh`, `task-context-check.sh` (cooldowns only)
- U: `bash-cd-check.sh`, `pre-explore-codemap-check.sh`, `task-context-check.sh` (cooldowns), `post-edit-check.sh` (in-progress), and `aria_hook_dbg`'s default log path in its 4 scripts (`capture-task-boundary.sh`, `post-edit-check.sh`, `pre-edit-check.sh`, `record-edit-intent.sh`) — default becomes `$(kt_state_path aria-hook-debug.log)`, no state ⇒ no write; `KT_HOOK_DEBUG_LOG` stays a test-only override; `capture-task-boundary.sh`'s read of the log (`## recent … debug log`) reads the same resolved path and says `(state directory unavailable)` when there is none. `aria_hook_dbg` stays byte-identical across its 4 copies (census CC1b).
- G: `build.sh`
- Tests: create `tests/repros/state-dir-hooks-reminders.sh`; repoint `plugin-antigravity/tests/test-bash-cd-aria.bats`, `test-pre-explore-aria.bats`, `test-post-edit-aria.bats`, `tests/repros/statusline-inject.sh`, `statusline-usage.sh`, `hook-markers-safe-create.sh` (debug-log arms), `plugin-claude-code/tests/test-safe-create.sh` (in-progress arms — these currently plant unique names in the real `/tmp`; after this task they plant under `KT_STATE_BASE`, closing that Task-3 review note).

**Interfaces:** Consumes T1. D3: bash-cd / codemap / task-context cooldowns and usage warn bands → **emit nothing** without state; in-progress cache → **mark anyway** (one SESSION.md read per edit); debug log → skip.

- [ ] **Step 1: Write failing arms** in `state-dir-hooks-reminders.sh` (per port that has the hook):
  - `Q1 cooldowns_no_state_emit_nothing`: broken state → bash-cd (cd into a fixture project with a CODEMAP), codemap and task-context hooks emit empty stdout on the FIRST call and on a second call.
  - `Q2 usage_no_state_emit_nothing`: broken state + a usage snapshot past a band → no output.
  - `Q3 inprogress_no_state_marks_anyway`: broken state + `session_state: true` + a scratch `SESSION.md` with a live prompt-less ledger → first edit marks it; second edit leaves it byte-identical (one mark).
  - `Q4 debug_log_no_state_writes_nothing` (U): broken state, `KT_HOOK_DEBUG_LOG` unset, scratch `/tmp` root → no `aria-hook-debug.log` anywhere.
  - `Q5 cooldown_names_in_state_dir`: healthy state → after one reminder, `aria-bashcd-*`, `aria-codemap-*`, `aria-context-*`, `aria-usage-warn-*` exist under the state dir; the second call within the cooldown emits nothing.
- [ ] **Step 2: Run red** (Q1 FAILS: reminders still fire with cooldowns in `/tmp`; Q5 FAILS).
- [ ] **Step 3: Implement** C → `build.sh` → X, U.
- [ ] **Step 4: Run green** — the new repro + every test under Files.
- [ ] **Step 5: Mutations:** (a) bash-cd emits its reminder when resolve fails → Q1 red; (b) post-edit skips marking when resolve fails → Q3 red; (c) `aria_hook_dbg` falls back to `/tmp/aria-hook-debug.log` → Q4 red.
- [ ] **Step 6: GATES.**
- [ ] **Step 7: Commit** `fix(hooks): cooldowns, usage bands, the in-progress cache and the Cursor debug log live in the private state dir` — scripts, G, tests. Hygiene gate.

---

### Task 4: Surfacing family (shell, all ports) → state dir; `KT_SURFACE_CACHE_DIR` retired

**Files:**
- Libraries (canonical, then copies): `lib-prompt-surface.sh` ×3 (`aria-surface-hook.log`, `aria-prompt-config.<n>.cache`), `lib-index-match.sh` ×4 (`kt_index_cache_path` → `aria-surface-<n>.tsv`), `lib-tracked-artifacts.sh` ×4 (comments only). Libraries build state names only with `kt_state_path`; when it fails (no state, or the caller never resolved) they read and write no cache and no log and rank uncached. Every `${KT_SURFACE_CACHE_DIR:-${TMPDIR:-/tmp}}` goes. The comments claiming "rename replaces a planted link" (`lib-prompt-surface.sh` ~:228-229) are corrected per the measured trap: `mv -f` moves INTO a directory at NAME; inside the private dir only our own mistake can put one there.
- CLIs: `aria-surface.sh` C X U G — source `lib-state-key.sh`, `kt_state_resolve` before ranking.
- Ledger writers `aria-active-<id>` (every shell site): C `bash-cd-check.sh`, `task-context-check.sh`, `prompt-context-check.sh`, `session-start-check.sh` (`TA_LEDGER`); X `bash-cd-check.sh`, `task-context-check.sh`, `session-start-check.sh` (`TA_LEDGER`), `post-compact-check.sh`; U `bash-cd-check.sh`, `task-context-check.sh`, `session-start-check.sh` (`TA_LEDGER`), `prompt-capture-check.sh` (ledger + `_pcc_dir` pending/version/prune + its `aria-surface-hook.log`), `prompt-context-inject.sh` (ledger + `_pci_dir` claim); H `pre-invocation-aria.sh` (`ag_debug_log`, `ag_surface`'s `dir`, `aria-ag-model.last` — correct the ~:507-509 rename comment — `aria-ag-surfaced-*`, `aria-ag-logged-*`, `TA_LEDGER`, `AG_SURFACE_LEDGER`); G `build.sh`.
- Every script that sources `lib-index-match.sh` or `lib-prompt-surface.sh` sources `lib-state-key.sh` and calls `kt_state_resolve` before the first library call (T7's CC8 enforces this).
- Tests: create `tests/repros/state-dir-surfacing.sh`; repoint `surfacing-rank.sh`, `cursor-prompt-capture.sh`, `surfacing-ranking-verbatim.sh`, `surfacing-cli-references.sh`, `session-ledger-resolution.sh` (its `aria-active-${session_id}` source check now names `kt_state_path aria-active-`), `session-start-single-emitter.sh` (stop writing the real `/tmp/aria-active-sse-*`), `plugin-claude-code/tests/test-prompt-context-check.sh`, `test-prompt-surface-core.sh`, `test-count-backlog-entries.sh`, `test-safe-create.sh` (ledger/log arms), `plugin-antigravity/tests/test-pre-invocation-aria.bats`; every `KT_SURFACE_CACHE_DIR` in tests → `KT_STATE_BASE`.
- PORT-LEDGER: re-baseline `lib-index-match.sh` + `aria-surface.sh` (openai-codex, cursor-template, antigravity), `lib-prompt-surface.sh` (cursor-template, antigravity) — one port per `--update`.

**Interfaces:** Consumes T1. D3: surfacing ledger and caches unavailable → the **hooks** surface nothing (no dedupe would re-inject every prompt); Cursor pending capture/claim and Antigravity model-last / surfaced / logged markers → skip (inject nothing, log nothing). The `aria-surface.sh` CLI (skills only, no ledger) still ranks without a cache — interpretation recorded for review: the D3 row's reason is dedupe, which the CLI does not do.

- [ ] **Step 1: Write failing arms** in `state-dir-surfacing.sh`:
  - `F1 hooks_no_state_surface_nothing`: broken state, active surfacing on, a matching prompt → C `prompt-context-check.sh` emits no `ARIA ACTIVE —`; U capture writes no pending file and inject emits nothing; bash-cd / task-context (active mode) emit no surfacing; nothing appears under scratch `/tmp` / `TMPDIR`.
  - `F2 ledger_in_state_dir_dedupes`: healthy state → after one prompt `<dir>/aria-active-<sid>` lists the surfaced paths; the same prompt again surfaces nothing new.
  - `F3 caches_in_state_dir`: `aria-surface-<n>.tsv`, `aria-prompt-config.<n>.cache`, `aria-surface-hook.log` (when logging) exist under the state dir only.
  - `F4 surface_cache_dir_retired`: `KT_SURFACE_CACHE_DIR` set to a scratch dir → nothing is ever written there.
  - `F5 cli_ranks_without_state`: broken state → `aria-surface.sh --file <fixture>` exit 0 and the same ranked output as with healthy state.
  - `F6 lib_parity`: `lib-prompt-surface.sh` ×3, `lib-index-match.sh` ×4, `lib-tracked-artifacts.sh` ×4, `aria-surface.sh` ×4 (byte-identical at `e24934f`, cksum 1064706371) one `cksum` each.
  - bats: `@test "no state dir: responsibility 4 injects nothing and logs nothing"`, `@test "surfaced and logged markers live in the state dir"`.
- [ ] **Step 2: Run red** — F1 (hooks still surface via `/tmp`), F2–F4, the two bats FAIL.
- [ ] **Step 3: Implement** libs → `cp` → C hooks + CLI → `build.sh` → X, U, H by hand. `cksum` all lib copies.
- [ ] **Step 4: Run green** — the new repro, every test under Files.
- [ ] **Step 5: Mutations:** (a) restore `${KT_SURFACE_CACHE_DIR:-…}` in `kt_index_cache_path` → F4 red; (b) `prompt-context-check.sh` falls back to `/tmp/aria-active-` when resolve fails → F1 red; (c) one cursor lib copy differs → F6 red.
- [ ] **Step 6: PORT-LEDGER** re-baseline (Files list), one port at a time.
- [ ] **Step 7: GATES.**
- [ ] **Step 8: Commit** `fix(surfacing): the session ledger, caches and surfacing logs live in the private state dir in every shell port; KT_SURFACE_CACHE_DIR is retired` — libs ×11, CLIs, hooks, H, G, tests, `PORT-LEDGER.json`. Hygiene gate.

---

### Task 5: Codex Python — four names, D3, encodings, suite stops leaking

**Files:** Modify `plugin-openai-codex/bin/codex-hook.py`; `plugin-openai-codex/tests/test_codex_port.py`; `plugin-openai-codex/tests/run.sh` (leak assertion).

**Interfaces:**
- Consumes: `aria_state_resolve`, `aria_state_path` (T1).
- Sites: `user_prompt_submit` resolves once; `aria-context-<key>` and `aria-active-<key>` via `aria_state_path`; no dir → return before surfacing (no cooldown, no ledger, no `ARIA ACTIVE` — D3). `maybe_codemap_reminder`: `aria-codex-codemap-<session>-<digest>` via `aria_state_path`; no dir → `None`. `maybe_mark_session_state`: `aria-session-inprogress-codex-<key>`; no dir → mark every root anyway, write no cache. Plain `open`/`write_text`/`read_text` inside the dir (no `O_NOFOLLOW`); `ledger_is_ours` stays and keeps its callers (D2), its docstring names the state dir. A key that `aria_state_path` refuses (contains `/`) skips that name's read and write.
- Subprocesses (carried from old Task 4): `run_legacy_capture`, `git_value`, the `/retrospect` `rev-list --count` gain `encoding="utf-8", errors="replace"`; each `subprocess.run` is wrapped in `try/except (OSError, ValueError, subprocess.SubprocessError)`; failure ⇒ `(0, "", "")` / `""` / the caller's existing empty-result branch.

- [ ] **Step 1: Write failing tests** (each in a `TemporaryDirectory` used as `KT_STATE_BASE`, env patched in-process):
  - `test_state_names_live_in_state_dir`: drive `user_prompt_submit` (surfacing config fixture), `maybe_codemap_reminder` (CODEMAP in cwd), `maybe_mark_session_state` (`session_state: true`) → the four files exist under `<base>/aria-knowledge-<uid>/`; nothing under `/tmp` with this test's unique key.
  - `test_no_state_dir_skips_surfacing_and_cooldown`: file at the state name → no `ARIA ACTIVE` emitted, codemap reminder `None`, no file created anywhere with the test key.
  - `test_no_state_dir_still_marks_session_inprogress`: same broken base → the scratch `SESSION.md` is marked.
  - `test_state_name_with_slash_refused` (RF5): `session_id` `a/../../x` → nothing written outside the state dir; the hook still emits its context.
  - `test_run_legacy_capture_survives_a_lone_surrogate`: stub script under a scratch plugin root; `run_legacy_capture("stub.sh", "\udcff")` returns a tuple.
  - `test_git_value_survives_a_missing_git`: `PATH` = empty dir → `""`.
  - `test_every_text_mode_subprocess_run_names_an_encoding`: AST walk: every `subprocess.run` with `text=True`/`universal_newlines=True` has `encoding=`; positive control in the same test: the walker flags a parsed `subprocess.run(["x"], text=True)`.
  - `run.sh` leak arm: record `ls -A /tmp` and `ls -A "${TMPDIR:-/tmp}"` entries matching `aria-*session-tmp*` (the measured leak shape, spec §2) before and after the Python run; FAIL on any new one. (A raw count would be flaky against live 2.57 sessions writing `/tmp/aria-*`; the test-id filter is the bound — say so in the arm's comment.)
- [ ] **Step 2: Run red** — names test, no-state tests, slash test, surrogate (`UnicodeEncodeError`), missing git (`FileNotFoundError`), AST census (3 sites), leak arm FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run green** — `sh plugin-openai-codex/tests/run.sh`.
- [ ] **Step 5: Mutations:** (a) `user_prompt_submit` uses `Path("/tmp")` when resolve fails → no-state test red; (b) remove `encoding=` from `git_value` → AST census red; (c) drop the `/` refusal in `aria_state_path` → slash test red.
- [ ] **Step 6: GATES.**
- [ ] **Step 7: Commit** `fix(codex): hook state lives in the private state dir; text subprocesses name an encoding and survive bad input` — `codex-hook.py`, tests, `run.sh`. Hygiene gate.

---

### Task 6: Model-facing — `ARIA CONFIG` per port (G1-1), digest clause (G1-2), skills, spec correction

**Files:**
- Spec correction (G1-1): `docs/superpowers/specs/2026-11-12-private-state-dir-spec.md` D5 read-side bullet (the sentence beginning "In runtimes that emit no `ARIA CONFIG` line, no hook writes a ledger either…", ~:151) is replaced by: every port whose hooks write the ledger states `state_dir=` / `ledger=` in its own session-start value line; and D4's skill row gains `/handoff`, `/wrapup` (read `aria-r22-bypass-<sid>`) and `/setup` (names the ledger), which the spec omitted. Front-matter status unchanged.
- Emitters: C `session-start-check.sh` — `CONFIG_LINE` gains ` state_dir=<dir|none> ledger=<dir>/aria-active-<sid>|none` before its closing sentence, on every source (startup, resume, clear, compact, fork); on resolve failure append to `USER_MESSAGES` exactly `ARIA: private state directory unavailable (<reason>) — hooks are running without state.` (D3; `emit()` already drops it on compact). U `session-start-check.sh`, X `session-start-check.sh`, H `pre-invocation-aria.sh` responsibility 2 (the session-start `ephemeralMessage` — the prospect log says "responsibility 1"; the file's own numbering puts session-start messages in 2): each appends one line `ARIA CONFIG — state_dir=<dir|none> ledger=<path|none>.` as a SEPARATE `MESSAGES` append — never inside the SESSION STATE line (Task 0's `AH2` pin must stay green) and not inside `ARIA SURFACE` (that line carries "the CLI path and nothing else"). Using the name `ARIA CONFIG` in every port lets one skill sentence serve all ports.
- `ledger=` uses the id the port's own ledger writer keys on for the same input: C/X `session_id`; U and H the id their prompt-surfacing writer uses (U `conversation_id`, H sanitised `conversationId`) when the session-start input carries it, else `none`.
- Digest: in `plugin-claude-code/rules/aria-rules.md` ARIA ACTIVE CONTEXT replace `Skip paths in /tmp/aria-active-$CLAUDE_CODE_SESSION_ID; never use \`ls -t\` over that glob (wrong session).` (105 B) with `Skip paths in the file named by \`ledger=\` in \`ARIA CONFIG\`.` (59 B) → 26,152 B. Antigravity's copy via `build.sh`.
- Skills, canonical C then X by hand, G via `build.sh`, U `.mdc` via the generator: `prospect` + `retrospect` (ledger paragraphs → "the file named by `ledger=` in `ARIA CONFIG`; `none` or absent ⇒ skip nothing"; drop the `ls -t` warning, there is no glob), `preflight` (record block below), `extract` + `audit-knowledge` (digest outputs via `aria-state.sh path "aria-digest-{filename}"`), `auto` + `statusline` ("the state directory" instead of the marker / warn-file paths), `handoff` + `wrapup` (bypass log via `aria-state.sh path "aria-r22-bypass-<session_id>"`), `setup` (ledger wording). Cowork `prospect` + `retrospect`: reword the ledger path description only.
- `/preflight` record block (C; X keeps its repo marker too): `_pf_sid=${CLAUDE_CODE_SESSION_ID:-${CODEX_THREAD_ID:-}}`; empty → print `preflight: no session id — marker not written` and do not write; else `_pf_m=$("<plugin root>/scripts/aria-state.sh" path "aria-preflight-$_pf_sid")` or print the CLI's reason and do not write; then `>> "$_pf_m"`. The skill compares the CLI's directory with `state_dir=` when the `ARIA CONFIG` line carries one and says so if they differ (D5). X: `pf_repo` → `aria-state.sh path "aria-preflight-repo-${repo_hash}"`.
- Tests: create `tests/repros/state-dir-model-facing.sh`; update `plugin-claude-code/tests/test-aria-rules-digest.sh` (needles `aria-active-$CLAUDE_CODE_SESSION_ID` / `never use \`ls -t\`` → the new clause; `CMP_LEDGER` moves under `KT_STATE_BASE`), `tests/repros/session-ledger-resolution.sh` (retired-form list gains the old clause; the port scan follows the new wording).
- PORT-LEDGER: re-baseline every changed tracked skill / `.mdc` — openai-codex, cursor-template, antigravity, claude-cowork — one port per `--update`.

- [ ] **Step 1: Write failing arms** in `state-dir-model-facing.sh`:
  - `M1 config_line_every_source` (AC6): C session-start with `source` = startup, compact, clear (isolated `HOME`, `</dev/null`) → `additionalContext` contains `state_dir=$D ledger=$D/aria-active-$SID` with `D` = the resolver's dir; and `prompt-context-check.sh` run with the same `session_id` writes exactly that ledger path (stated = written).
  - `M2 config_line_no_state`: broken state → `state_dir=none ledger=none`; startup `systemMessage` contains `ARIA: private state directory unavailable (not a directory) — hooks are running without state.`; compact output has no `systemMessage`.
  - `M3 ports_state_their_paths` (G1-1): U, X and H session-start output each carry one `ARIA CONFIG — state_dir=… ledger=…` line, and the stated ledger equals the path that port's writer creates for the same input (U: `prompt-capture-check.sh`; X: `codex-hook.py user-prompt-submit`; H: responsibility 4) — fixture inputs carry both id fields.
  - `M4 digest_clause` (G1-2): digest contains the 59-B clause verbatim, not `aria-active-$CLAUDE_CODE_SESSION_ID`; `wc -c` ≤ 26198 and = 26152; `sh plugin-claude-code/tests/test-aria-rules-digest.sh` lock section green with no relock.
  - `M5 preflight_record_block` (AC7 locally): extract the fenced block containing `aria-state.sh" path "aria-preflight-` from C `preflight/SKILL.md`; run it with both ids unset → no file anywhere, message printed; with `CLAUDE_CODE_SESSION_ID=pf-x` → `<dir>/aria-preflight-pf-x` holds one `READY` line, and `pre-commit-preflight-check.sh` with `session_id` `pf-x` treats the commit as preflighted.
  - `M6 skills_name_no_old_location`: no `/tmp/aria-` or `${TMPDIR…}/aria-` remains in any C X G skill, the cursor `.mdc`, or the two Cowork skills.
  - `M7 descriptions_unchanged`: the description-diff check prints nothing.
- [ ] **Step 2: Run red** — M1–M6 FAIL (M7 passes by design; label it non-regression).
- [ ] **Step 3: Implement** spec correction → C emitter + digest + C skills → `build.sh` → X skills + X/U emitters + H by hand → `.mdc` generator → Cowork wording.
- [ ] **Step 4: Run green** — the new repro, the two updated tests, `sh tests/repros/session-state-token-directive.sh` (AH2 still green).
- [ ] **Step 5: Mutations:** (a) emit `ledger=` from the raw (unresolved) `/tmp` form → M1 red ("stated ≠ written"); (b) put the U line inside the SESSION STATE string → AH2 red; (c) revert the digest clause → M4 red.
- [ ] **Step 6: PORT-LEDGER** re-baseline, one port at a time (Files list).
- [ ] **Step 7: GATES.**
- [ ] **Step 8: Commit** `feat(state): every port states state_dir= and ledger= to the model; skills read and write through aria-state.sh; digest clause names the ledger field` — spec, emitters, digest (+ G copy), skills ×5 ports, `.mdc`, tests, `PORT-LEDGER.json`. Hygiene gate.

---

### Task 7: Census repurposed + sweeps (in-dir, legacy `/tmp` and `$TMPDIR` — G1-3)

**Files:** Modify `tests/repros/safe-create-census.sh`; `session-start-check.sh` C X U; `pre-invocation-aria.sh` H (responsibility 2 sweep block and `ag_surface` housekeeping); G via `build.sh`; `tests/repros/plugin-suite-leaves-real-tmpdir-alone.sh`. Create `tests/repros/state-dir-sweeps.sh`.

**Interfaces:**
- In-dir sweep (after `kt_state_resolve`, only when it succeeded): `find "$KT_STATE_DIR/" -mindepth 1 -maxdepth 1 -type f -mmin +1440 -exec rm -f {} +`. Replaces the `KT_SURFACE_CACHE_DIR` half of today's `.aria-new.*` sweep.
- Legacy sweep, one block per sweeping script between `# LEGACY-TMP-SWEEP-2.58 begin — remove in the first release after 2.58.0, together with KT_TMP_SWEEP_ROOT (Rule 37)` and `# LEGACY-TMP-SWEEP-2.58 end`. One `find` per root, `-maxdepth 1 -user "$(id -u)" -mmin +1440`, start points ending in `/`:
  - root `${KT_TMP_SWEEP_ROOT:-/tmp}/`: `aria-active-*`, `aria-session-inprogress-*` (today's sweeps, now user-scoped), `aria-bashcd-*`, `aria-codemap-*`, `aria-codex-codemap-*`, `aria-context-*`, `aria-usage-warn-*`, `aria-hook-debug.log`, `aria-digest-*`, `.aria-new.*`.
  - root `${KT_TMP_SWEEP_ROOT:-${TMPDIR:-/tmp}}/`: `aria-r22-*` (denies, carrier, lastedit, bypass), `aria-extfetch*`, `aria-preflight*` (incl. `-denies`, `-skipped`, `-repo`), `aria-surface-*` (`.tsv` and `-hook.log`), `aria-prompt-config.*`, `aria-cursor-*`, `aria-ag-*`, `.aria-ag-*`, `.aria-new.*`.
  - With `KT_TMP_SWEEP_ROOT` set, both roots are that dir (tests never sweep the real `/tmp` or `$TMPDIR`).
- Census arms (`safe-create-census.sh`; CC1–CC4 stay; CC4's predictable-name matcher keys on the basename so `kt_state_path` targets are still examined — adjust in T2–T4 if a gate needs it, otherwise here):
  - `CC6 no_legacy_location`: FAIL on any code line (full-line comments exempt) in a hook script, lib, `aria-state.sh`, `codex-hook.py` (`Path("/tmp")`, `"/tmp/aria-`), or a fenced shell block of a `SKILL.md` / `.mdc`, naming literal `/tmp/aria-`, `${TMPDIR…}/aria-`, `$TMPDIR/aria-` or `KT_SURFACE_CACHE_DIR` — except `mktemp` templates and lines inside a `LEGACY-TMP-SWEEP-2.58` block. Zero files examined ⇒ FAIL.
  - `CC7 state_lib_parity`: `lib-state-key.sh` ×4 byte-identical and each defines `kt_state_base kt_state_resolve kt_state_dir kt_state_path` exactly once.
  - `CC8 resolve_before_use`: every script that sources `lib-index-match.sh` / `lib-prompt-surface.sh` or calls `kt_state_path` also sources `lib-state-key.sh` and calls `kt_state_resolve` on an earlier line.
  - `CC9 one_name_builder`: `$KT_STATE_DIR/` appears only inside `lib-state-key.sh`.
  - `CC0` controls (scratch files): one plant per CC6 form (5 forms incl. Python), a comment line and a `mktemp` template and a marked legacy line (not reported); a script calling `kt_state_path` without resolving (CC8 reports it); `printf x > "$KT_STATE_DIR/aria-x"` in a hook (CC9 reports it) — each reported exactly once.

- [ ] **Step 1: Write failing tests** — census arms above; `state-dir-sweeps.sh`: plant each legacy name in a `KT_TMP_SWEEP_ROOT` scratch with `touch -t` 2 days old and a fresh copy; run each sweeping script (C X U session-start with isolated `HOME`, `</dev/null`; H via its bats-free direct run) → every old legacy name removed (`W_legacy_<name>` arm per name), every fresh one kept, a non-matching old file (`unrelated-old`) kept; in-dir: an old file in the state dir removed, a fresh one kept, nothing outside it touched (`W_indir`); `W_marker`: `grep -l LEGACY-TMP-SWEEP-2.58` lists exactly C X U H and G session-start (5 files), each with balanced begin/end. Extend `plugin-suite-leaves-real-tmpdir-alone.sh`: plant sentinels at three of the moved `$TMPDIR` names and assert the sandbox `TMPDIR` gains no `aria-knowledge-*` entry (runners set `KT_STATE_BASE`) (AC8).
- [ ] **Step 2: Run red** — sweep arms for the new names and `W_indir`, `W_marker`, CC6–CC9 controls FAIL; CC6 on the tree may already be green (all writers moved in T2–T6) — if not, the report lists the stragglers: fix them here and say which task missed them.
- [ ] **Step 3: Implement** sweeps C → `build.sh` → X, U, H; census arms.
- [ ] **Step 4: Run green.**
- [ ] **Step 5: Mutations:** (a) drop `aria-r22-*` from the `$TMPDIR` legacy list → `W_legacy_aria-r22-lastedit` red; (b) remove the `-mmin +1440` → fresh-file arm red; (c) put back one `${TMPDIR:-/tmp}/aria-extfetch-` in codex `pre-external-fetch-check.sh` → CC6 red naming that line; (d) remove `kt_state_resolve` from one CLI → CC8 red.
- [ ] **Step 6: GATES.**
- [ ] **Step 7: Commit** `test(census): no hook, lib or skill names an old shared location; sweeps clear the state dir and, for 2.58.0 only, the legacy /tmp and $TMPDIR names` — scripts, H, G, tests. Hygiene gate.

---

### Task 8: Prose, emitter sentence, CHANGELOG, PORT-LEDGER (old Task 5, folded)

**Files:** `plugin-claude-code/skills/handoff/SKILL.md` + `plugin-openai-codex/skills/handoff/SKILL.md` (by hand), G via `build.sh`, U via the generator; `plugin-cursor-template/scripts/aria/session-start-check.sh`, `plugin-openai-codex/bin/session-start-check.sh`; `tests/repros/session-state-token-directive.sh`; `CHANGELOG.md` (`[Unreleased]`); `PORT-LEDGER.json`.

**Interfaces:** Consumes `AH_EMITTER_SENTENCE` (exact, from old Task 0, trailing space included): `A stored prompt line that begins with one backslash before ##, ###, a code fence or the entry-end terminator line is escaped; read it without that one backslash. `

- [ ] **Step 1: Failing assertion** in `session-state-token-directive.sh`: `b7 "codex hook"` / `b7 "cursor hook"` — the RENDERED directive (run each `session-start-check.sh` with isolated `HOME`, `session_state: true` config, `KT_STATE_BASE` scratch, `</dev/null`) contains `AH_EMITTER_SENTENCE` exactly once. Run → FAIL.
- [ ] **Step 2: Emitters** — insert the sentence immediately before the closing `"` of the SESSION STATE `MESSAGES` line in both hooks (after `Offer the resume once per session. `). b7 PASS; `AH2` still PASS.
- [ ] **Step 3: Step 0r** (C + X by hand): after item 5, where the chosen entry's stored prompt is read to resume: "⚠ Entries stored since 2.58.0 escape structural lines: a stored line that begins with `\` before `## `, `### `, ```` ``` ```` or `<!-- aria:entry-end -->` is escaped — read it without that one backslash, and never copy the backslash into a command."
- [ ] **Step 4: 3f helper bullet** (C + X): "⚠ The terminator declares the boundary for the SHELL HELPERS ONLY …" now says entries written by 2.58.0+ carry escaped structural lines and are framed safely for every reader; the warning still applies to entries written before 2.58.0. Keep the measured-incident text.
- [ ] **Step 5: Regenerate** `build.sh` and the `.mdc` generator; `git status` shows only the handoff skill / `.mdc` changes.
- [ ] **Step 6: CHANGELOG `[Unreleased]`** (no version number). Entries: (1) ledger framing unit — walker scoping, escaped prompt lines, shared safe create (from the earlier plan); replace the clause beginning "⚠ Pre-existing, not changed here: a stored prompt that contains a column-0 `### ` line…" with: legacy entries are not rewritten; an unfenced column-0 entry header inside a legacy terminated body stays indistinguishable. (2) All hook state moves to one private per-user directory: location rule (`KT_STATE_BASE` test-only → `XDG_RUNTIME_DIR` → `TMPDIR` → macOS `getconf DARWIN_USER_TEMP_DIR` → `/tmp`, `/aria-knowledge-<uid>`, mode 700, no fallthrough) and the D3 degraded behaviours; `ARIA CONFIG` gains `state_dir=` / `ledger=` in every port; new `aria-state.sh path`; `/preflight` takes the id from `CLAUDE_CODE_SESSION_ID` (Codex: `CODEX_THREAD_ID` + its repo marker) and refuses an empty one; `KT_SURFACE_CACHE_DIR` retired; Codex encoding fixes. **Known limits:** `legacyact` (an unterminated legacy Prior-sessions entry closed by a raw unfenced terminator inside ACTIVE — old prune identical); 6 pre-2.58.0 consumed entries are retained (manual tidy); a CRLF terminator's `\r` is not escaped; without `link` on `PATH` (every shell port) ledgers and the debug log are not written (fail safe; dedupe lost); files created by the safe create are now 0600 (were umask 0644); the macOS `/tmp` sweeps now actually run — the first run removes stale ledgers (372 measured); the legacy `/tmp` and `$TMPDIR` sweeps exist for 2.58.0 only (`LEGACY-TMP-SWEEP-2.58`); on Linux a `/tmp/aria-knowledge-<uid>` created by another user leaves hooks permanently in degraded mode until an admin removes it — fail safe, visible at SessionStart, deliberately no `$HOME` fallback (G1-4); a session that switches plugin version mid-run restarts its state once; the Claude Code digest's SESSION STATE `|pending` resume path does not carry the unescape sentence; the external session-ledger checker must learn the escape; **owed live checks**: `/preflight` marker satisfying the commit gate in a live Claude Code session (AC7), a Bash-sandboxed session's `TMPDIR` vs the hook's, `TMPDIR` inside Codex / Cursor / Antigravity hooks, a launchd / cron run, Linux.
- [ ] **Step 7: PORT-LEDGER** — `check-port-drift.sh` report; for `claude-code`, `antigravity`, `cursor-template`, `openai-codex`, one at a time: diff that port's handoff skill against canonical for the two passages, `--update <port>`, re-run the report. `claude-cowork` untouched in this task.
- [ ] **Step 8: Invariants** — digest 26,152 B (≤ 26,198); description-diff check prints nothing; `git diff --stat e24934f -- plugin-claude-cowork` lists only the two T6 skills.
- [ ] **Step 9: GATES.**
- [ ] **Step 10: Commit** `docs: stored prompt lines are escaped and the state directory is documented; CHANGELOG states the 2.58.0 known limits` — skills, `.mdc`, two hooks, directive test, `CHANGELOG.md`, `PORT-LEDGER.json`. Hygiene gate.

---

### Task 9: Whole-branch review and retrospect — then STOP

- [ ] **Step 1:** One fresh reviewer on the most capable model over `3e44761..HEAD` (both units: `2026-11-11-ledger-framing-and-safe-create` spec + plan, and this spec + plan). Brief: verify AC1–AC9 of this spec and AC1–AC7 of the earlier one against the CODE, not the plans; re-run every parity `cksum`; confirm each red-first arm was red for its stated reason (the task reports name them) and each non-regression arm is labelled; trace D3's table row by row to a test; confirm no test writes the real `/tmp` / `$TMPDIR` (run `plugin-suite-leaves-real-tmpdir-alone.sh` and list `aria-knowledge-*` in the real temp dirs before/after a full gate run). Re-verify each finding before acting; fix only findings that reproduce, one commit each, GATES after each.
- [ ] **Step 2:** Invoke `/retrospect range 3e44761..HEAD` (invoke the skill — never run it inline, U29).
- [ ] **Step 3:** Report and STOP: commits, gate results, measured latency p95 (T1), the census counts, findings not fixed, the live checks owed (CHANGELOG list). No push, no version bump, no release.

---

## Gate-2 amendments (binding — /prospect 2026-11-12, log knowledge/logs/prospect/2026-11-12-file-plan-private-state-dir.md)

- **G2-1 (Task 1):** the state-dir check also refuses an ACL-bearing directory — sh: the `ls -ldn` mode string ending in `+`; Python: the same `ls -ldn` read (or `os.listxattr` where available). Fail safe. Arm with `chmod +a` on a scratch dir on macOS; reasoned where the platform cannot set one.
- **G2-2 (Task 8 / Task 10):** Cowork's reworded prospect/retrospect text ships as **Cowork 1.8.3** with 2.58.0 (Mike: "full release"). The version bump happens in Task 10, not Task 8.
- **G2-3 (Task 9 → Task 10):** Task 9 no longer stops. **Task 10: Release 2.58.0** (Mike 2026-11-12: "ok continue with full SPPPE and then do the full release"): bump canonical + every port per RELEASING.md and CLAUDE.md (antigravity `plugin.json` by hand + `build.sh`, cursor `VERSION`, codex `.codex-plugin/plugin.json`, cowork 1.8.3); build every zip; Gate D reads every commit message; merge `release/2.58.0` → `main`; push `main` and the annotated tags `v2.58.0` + `cowork-v1.8.3`, verified by `ls-remote`; `gh release create` (canonical marked latest; cowork `--latest=false`); `publish-release.sh --apply`; verify `/releases/latest` = v2.58.0, every download byte-identical to the local build, and a fake-asset 404 control; finish the worktree with `release-worktree-finish.sh` (never `git worktree remove`); update the repo CLAUDE.md footer and the project-index row.
