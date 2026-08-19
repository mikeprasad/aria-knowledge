# Plan — cowork parity + port commits + canonical v2.46.3 release

**Date:** 2026-08-19
**Repo:** `aria-knowledge` (branch `main`)
**Authorization:** Mike, 2026-08-19 — "update the cowork plugin to parity, then validate all then release."
Release scope ruled *[No preference]* → executing the recommended option (commit ports, one canonical
release). Cowork scope ruled **All 4, including the dead detector**.

---

## Measured starting state (this session, 2026-08-19)

| Port | Version on disk | Ledger | Skills | Verdict |
|---|---|---|---|---|
| `plugin-claude-code` (canonical) | 2.46.2 | — | 36 | reference |
| `plugin-antigravity` | 2.46.2 | 2.46.2, pass 08-18 | 36 (identical set) | at parity, **committed** |
| `plugin-openai-codex` | 2.46.2-codex.0 | 2.46.2-codex.0, pass 08-19 | 35 (`statusline` deliberately absent, `PORTING.md:61-63`) | at parity, **uncommitted** |
| `plugin-cursor-template` | 2.46.2-cursor.0 | **2.36.0-cursor.0, pass 06-24** | n/a (compiles to `.mdc`) | files at parity, **ledger stale**, **uncommitted** |
| `plugin-claude-cowork` | 1.5.0 | 1.4.0 → target 2.36.0 | 27 (divergent by ADR-014) | 4 real gaps |

All five ports carry 38 working rules. Cowork alone lacks two preamble paragraphs.

### The four cowork gaps

1. `template/rules/working-rules.md` — missing **"Two strictness tiers"** and **"Tie-breaker for
   genuine ties."** Class censused: canonical, antigravity, codex, cursor all have both; cowork alone
   has neither. Only other diff is the documented `/setup` → `/aria-setup` substitution.
2. `template/rules/retrospect-patterns.md` — **absent**, yet cowork's own `/prospect` and
   `/retrospect` instruct reading it in **18 places**. Plugin-managed in canonical.
3. `/aria-setup` scaffold list omits both `rules/retrospect-patterns.md` and
   `rules/overbuild-patterns.md` (the latter ships in cowork's template but is never scaffolded).
4. **Root cause** — `plugin-claude-cowork/release.sh:24` resolves `ARIA_KNOWLEDGE_TEMPLATE` to
   `<root>/plugin-claude-cowork/../aria-knowledge/plugin/template` = `<root>/aria-knowledge/plugin/template`,
   a doubled path that has never existed (canonical is `plugin-claude-code/template`). Its miss branch
   is `vlog` (verbose-only), so the check has silently skipped on every cowork release. This is why
   gap 1 accumulated undetected.

Run by hand with the corrected path, the detector reports exactly two drifted files:
`rules/working-rules.md` (4 lines — gap 1) and `aliases.md` (20 lines — **false positive**: user-owned
and deliberately cowork-flavoured, same class as `user-examples.md`).

---

## Global constraints

- **`release.sh` stages from the WORKING TREE.** A release built with a dirty tree ships whatever is
  uncommitted, with no error. Build from a **detached `git worktree` at the release commit**.
- **Shared working tree, shared HEAD.** Other sessions use this repo. Re-verify branch + no live
  aria-knowledge session immediately before each commit. Never `git add -A`; stage named paths.
- **Do NOT re-baseline a port whose files are not verified at parity.** `--update` stamps lag away.
  Cursor's re-baseline is legitimate *only because* its files are measured at 2.46.2 first.
- **Cowork description budget:** `release.sh` caps summed `skills/*/SKILL.md` description fields at
  ~9000 chars (empirical fail 9233). No skill descriptions change here, but the gate must still pass.
- Ports are **hand-maintained, never regenerated** from canonical (ADR-014).

---

## Tasks

### Phase 0 — safety

- **T0.1** Re-check transcript mtimes for a live session with `aria-knowledge` in scope. Abort commits
  if one is active.
- **T0.2** Record HEAD and the exact uncommitted path list as the pre-state.

### Phase 1 — commit the inherited port work

- **T1.1** Stage + commit codex (30 modified + 7 new skill dirs + 6 new `bin/` scripts) as
  `feat(codex): sync codex port to v2.46.2 canonical parity`.
- **T1.2** Stage + commit cursor (18 modified + 6 new scripts) as
  `feat(cursor): sync cursor port to v2.46.2 canonical parity`.
- **T1.3** Re-baseline **cursor only** in `PORT-LEDGER.json`. Precondition, verified first: cursor's
  `VERSION` reads `2.46.2-cursor.0` and its `working-rules.md` carries all 38 rules + both preamble
  paragraphs. Codex's ledger entry is already stamped 08-19 and needs no change.

### Phase 2 — cowork parity (all 4)

- **T2.1** Add the two missing paragraphs to `plugin-claude-cowork/template/rules/working-rules.md`,
  positioned exactly as in canonical, with `/setup` → `/aria-setup` applied if the text names it.
- **T2.2** Add `plugin-claude-cowork/template/rules/retrospect-patterns.md`, ported from canonical
  with the `/setup` → `/aria-setup` substitution and any Bash-dependent phrasing adapted (cowork has
  no shell). Preserve existing divergences per ADR-014.
- **T2.3** Add `rules/retrospect-patterns.md` + `rules/overbuild-patterns.md` to `/aria-setup`'s
  expected-files and plugin-managed lists.
- **T2.4** Repair `plugin-claude-cowork/release.sh` — point `ARIA_KNOWLEDGE_TEMPLATE` at
  `plugin-claude-code/template`, and narrow the checked set to **plugin-managed** files only
  (`working-rules.md`, `change-decision-framework.md`, `enforcement-mechanisms.md`,
  `retrospect-patterns.md`), dropping the user-owned `aliases.md` that produces the false positive.
  Change the miss branch from `vlog` to `warn` so a future path break is visible, not silent.
- **T2.5** Bump cowork `1.5.0` → `1.6.0`; add a CHANGELOG entry naming all four fixes.

### Phase 3 — validation (every check run, none inferred)

- **T3.1** `tests/run.sh` (repro suite) — bare exit code, not piped.
- **T3.2** `plugin-claude-code/tests/` — 7 suites.
- **T3.3** `plugin-openai-codex/tests/test_codex_port.py` — the codex port's own test.
- **T3.4** Repaired cowork detector reports **clean** — and is **mutation-verified**: temporarily
  reintroduce a drift, confirm it goes red for that reason, restore, confirm green. A detector that
  has never been seen to fail is not evidence.
- **T3.5** `check-port-drift.sh` — cursor's `lag` line gone, no port reports `drifted`.
- **T3.6** cowork `release.sh` description-budget gate passes.

### Phase 4 — release

- **T4.1** Bump canonical `2.46.2` → `2.46.3`; CHANGELOG entry covering the port syncs + cowork parity.
- **T4.2** Build from a **detached worktree at the release commit**, not the working tree. Verify the
  built artifact matches the committed tree and differs from any dirty state.
- **T4.3** `gh release create` + attach stable aliases + the cowork `.plugin`.
- **T4.4** Verify the published artifact by content (download + grep a symbol), not by the release
  command's exit code.

---

## Named risks

- **R1 — committing another session's work.** Both diffs reviewed and coherent, but not authored here.
  Commit messages must attribute the sync, and the ports' own tests must pass before the release.
- **R2 — `--update` stamping away real lag.** Mitigated by verifying cursor's files at 2.46.2 *first*.
- **R3 — dirty-tree release.** Mitigated by T4.2's detached worktree.
- **R4 — the repaired detector surfacing NEW drift.** It must run before the release, not after.
- **R5 — cursor's ledger tracks only 2 surfaces** vs codex 42 / antigravity 36, so its tripwire is
  near-blind. Expanding it is scope growth; flag rather than fix unless prospect rules otherwise.
