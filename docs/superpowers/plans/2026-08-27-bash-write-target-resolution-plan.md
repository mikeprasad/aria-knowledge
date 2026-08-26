# Plan — restore `pre-bash-write-check.sh` with resolved targets (v2.48.1)

**Status:** GATED 2026-08-27 — **PROCEED-WITH-CHANGES**; all four changes (C1 stub-first red,
C2 archive forward-pointer as new T8, C3 builtins-only before the python3 check, C4 `/preflight`
before release) applied in this revision.
**Gate 2:** `knowledge/logs/prospect/2026-08-27-file-bash-write-plan-gate2.md`.
**Spec:** `docs/superpowers/specs/2026-08-27-bash-write-target-resolution.md` (GATED, C1–C3 applied).
**Gate 1:** `knowledge/logs/prospect/2026-08-27-file-bash-write-target-resolution.md`.
**Release target:** v2.48.1 · push + release granted explicitly.

## Baseline to establish FIRST (T0)

⛔ Record the pre-change baseline before touching anything, or a later failure cannot be attributed.
`sh tests/run.sh` — record suites passed/failed as the **bare exit code**, never through a pipe.

## Task order

### T0 — Baseline
- Run `sh tests/run.sh`; record the suite count and bare exit.
- Record `git rev-parse HEAD` and confirm the tree is clean apart from the known parallel-session
  ` M .gitignore` (leave it — it is not ours).
- **Acceptance:** a recorded baseline number to compare against at T5.

### T1 — The resolver: `plugin-claude-code/bin/pre-bash-write-resolve.py`
Port from the workspace-local `tools/bash-discipline-check.py` resolver (outside this repo), taking
**only** what is needed:
- `HEREDOC_BODY` stripping · `_statements()` (shlex `punctuation_chars`) · per-statement extraction.
- **Narrow to the spec's scope**: in-place verbs (`sed -i`, `perl -i`, `awk -i inplace`) and `>>`
  append **into a source extension**. ⛔ NOT `>` creation. ⛔ NOT `cp`/`mv`. ⛔ NOT `tee`.
  Those are in the root-repo tool because it answers a different question; importing them here would
  widen the measured scope (spec §3).
- Temp exemption applied to the **resolved target path** (`/tmp/`, `/private/tmp/`, `/var/tmp/`,
  `*/scratchpad/*`, `/var/folders/`), never to the command string.
- Reads the hook JSON on stdin; prints the resolved in-scope targets, one per line; prints nothing
  when there are none. Exits 0 always, including on `ValueError` (fail open).
- **Acceptance:** driven directly with the AC1–AC6 command strings, it prints targets for AC1/AC6b
  and nothing for AC2–AC5/AC6a.

### T2 — The wrapper: `plugin-claude-code/bin/pre-bash-write-check.sh`
- Read stdin once into `INPUT` using `printf '%s'` (⛔ **not `echo`** — it interprets backslash
  escapes, so JSON `\n` becomes a real newline and a single-line `grep` silently matches nothing;
  heredoc commands are routinely multi-line. This is recorded in the archived script and is a real
  prior bug).
- **Cheap pre-filter** (spec §D3 invariant): if the raw command contains none of `sed`, `perl`,
  `awk`, `>>`, exit 0 without spawning Python.
  ⛔ **The pre-filter may only cause an EXIT, never a warning.** Comment it at the site.
- If `command -v python3` fails → exit 0 silently (AC8).
  ⛔ **Gate change C3 — ordering constraint: use ONLY shell builtins (`printf`, `command`, `case`,
  `read`) up to and including this check.** AC8 is tested by stripping `PATH`, which removes every
  external binary — so if the wrapper calls `grep`/`sed` before checking for `python3`, the test
  breaks the wrapper rather than exercising the missing-interpreter path, and AC8 would pass for
  the wrong reason.
- Pipe `INPUT` to the resolver. No output → exit 0.
- Output → append one line per fire to `${TMPDIR:-/tmp}/aria-r22-bypass-<session_id>` (AC9), then
  emit the `additionalContext` envelope and exit 0.
- Add a `[BWCHK-PRE]` marker comment so `/retrospect` can confirm the hook fired.
- **Acceptance:** `sh bin/pre-bash-write-check.sh < fixture.json` exits 0 for every fixture.

### T3 — Controls: `tests/repros/bash-write-target-resolution.sh` — RED FIRST
⛔ **Red-first against a STUB, not against absence — gate change C1.** Create
`bin/pre-bash-write-check.sh` FIRST as a stub that reads stdin and exits 0 silently, then write the
controls, then implement. With no file at all every control would fail with a missing-file error —
all red for the **same wrong reason**, proving nothing about what any of them tests.

⚑ **And the pairing this exposes, which is why C1 is worth the extra step:** against the stub the
SILENCE controls (AC2–AC5, AC6a, AC11) are **green**, because a hook that does nothing is
indistinguishable from a hook that correctly stays quiet. Those controls therefore cannot, alone,
tell a working hook from a dead one — each is meaningful **only** paired with a positive sibling
(AC1, AC6b) that must be RED against the stub and GREEN after. State the pairing in the suite.
One control per AC, following the existing `tests/repros/*.sh` idiom (exit non-zero on failure):

| Control | Command under test | Expect |
|---|---|---|
| AC1 | `cp f /tmp/bak && sed -i '' s/a/b/ f` | **WARNS** — the archived guard's false negative |
| AC2 | `git commit -F -` heredoc quoting `sed -i` | SILENT — false positive |
| AC3 | `git commit -m "use sed -i on f.py"` | SILENT — quoted form |
| AC4 | `sed -i '' s/a/b/ /tmp/scratch.py` | SILENT — temp, by resolved path |
| AC5 | `cat > newfile.py` | SILENT — creation out of scope |
| AC6a | `echo x >> notes.md` | SILENT — non-source extension |
| AC6b | `echo x >> mod.py` | **WARNS** — source extension |
| AC7 | malformed JSON; unbalanced quotes | exit 0, no output |
| AC8 | `PATH` without python3 | exit 0, no output |
| AC9 | an AC1 fire | exactly one ledger line; AC2 adds none |
| AC11 | `echo "sed -i is a string"` | SILENT — trips the pre-filter, resolves to no target |

- **Acceptance:** all 11 red before T1/T2, all green after.

### T4 — Register the hook
`.claude-plugin/plugin.json` → `hooks.PreToolUse`, a new entry with `matcher: "Bash"`:
`bash ${CLAUDE_PLUGIN_ROOT}/bin/pre-bash-write-check.sh`, placed **after** `bash-cd-check.sh` and
`pre-commit-preflight-check.sh` so the cheapest existing checks run first.
- **Acceptance:** `python3 -c "import json;json.load(open(...))"` parses; the entry count rises by
  exactly one; the two existing Bash entries are byte-identical.

### T5 — Mutation-verify (AC10)
Against a **copy** in the scratchpad, never the live tree (other sessions call these hooks):
| Mutation | Must redden |
|---|---|
| Temp exemption reads the command string instead of the resolved target | AC1 |
| Heredoc stripping removed | AC2 |
| Pre-filter emits instead of exiting | AC3, AC11 |
| `>` creation added to scope | AC5 |
| Source-extension list ignored | AC6a |
| Ledger append removed | AC9 |
- Each restore verified byte-identical with `cmp`.
- Re-run `sh tests/run.sh`; compare to the T0 baseline. **Acceptance:** baseline + 1 suite, no
  pre-existing suite newly failing.

### T6 — Version + CHANGELOG
- `.claude-plugin/plugin.json` version `2.48.0` → `2.48.1`.
- CHANGELOG entry at the top, written in the house voice: what was restored, the two defects and the
  single mechanism that closes both, the **dropped** `Path.write_text()` with its return condition,
  and the cursor-template residual.
- ⚠ Grep for every other place the version is stated (README/QUICKSTART/rules) — a version claimed in
  two places drifts. **Acceptance:** `grep -rn "2\.48\.0"` returns only historical CHANGELOG mentions.

### T8 — Forward-point the archived predecessor (gate change C2)
`plugin-claude-code/bin/.archived/pre-bash-write-check.sh`'s header reads *"RETIRED … Kept per
Rule 6 as the record of a method that was provably wrong, not as code to restore."* Once the
successor ships that is **true about the method and misleading about the state** — a reader finds an
archive asserting retirement with no pointer to the live replacement.
- Add a dated line at the top naming the successor and the spec, keeping every existing word.
- ⛔ Do **not** un-archive it and do **not** soften the "provably wrong" verdict — that verdict is
  still correct and is the reason the successor exists. Rule 6 keeps the record; it does not
  require the record to mislead.
- **Acceptance:** the header names `pre-bash-write-check.sh` (live) and the 2026-08-27 spec; the
  original text is otherwise byte-identical below the new line.

### T7 — Release ceremony
⛔ **Run `/preflight` FIRST — gate change C4.** It was explicitly requested and the first draft of
this plan omitted it; it is also precisely the moment `/preflight` exists for — before claiming
done. A recorded verdict of any kind satisfies the commit gate; a FAIL is recorded and noted, not
hidden.

Then: commit → `sh tests/run.sh` green (bare exit) → push → tag `v2.48.1` → `gh release create` →
verify the published artifact.
⛔ **Build the release from a detached `git worktree` at the release commit**, not the working tree:
`release.sh` stages from the working tree, and a parallel session's uncommitted files inside
`plugin-claude-code/` would ship into a public artifact with no error (recorded 2026-08-16).
⛔ Verify the tag with `git ls-remote --tags`, never `git tag` (which is the local list).
- **Acceptance:** the published zip is content-verified (`cmp`) against the worktree build.

## Risks carried into execution

- **R1** The resolver is a *narrowed* port, not a copy. The narrowing is where a porting bug would
  hide — T3's AC5 (creation silent) and AC6a (non-source silent) are the controls that catch it.
- **R2** `plugin.json` is shared; a parallel session could touch it. Re-read immediately before T4
  and predict the diffstat.
- **R3** The 0.674% fire rate will rise (spec §3) because defect 1 is fixed. Expected, not a
  regression — but if it fires on something legitimate in real use, the KILL rule applies again.

## Explicitly NOT in this plan
- Re-arming the root-repo `tools/bash-discipline-check.py` write gate (stays disarmed).
- Fixing the cursor template's live copy (residual, first follow-up).
- Any denial behaviour.
