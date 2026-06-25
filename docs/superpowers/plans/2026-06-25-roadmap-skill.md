# `/roadmap` Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `/roadmap` skill to aria-knowledge that renders a per-project feature×band status grid (✓done / ◐in-progress / ⛔blocked / ▷buildable across Shipped/Current/Next/Later), persisted to a committed `ROADMAP.md` with source-stamp staleness-aware refresh, and ship it in the unreleased v2.37.1 to GitHub.

**Architecture:** A single new prose skill (`plugin-claude-code/skills/roadmap/SKILL.md`) modeled on two proven in-family templates — `/codemap` (persist + modes + staleness, `allowed-tools` with Write) and `/recap` (`projects_list` resolver, graceful git/Bash degradation, honest-about-inference output). The deliverable is a model-instruction document; its "tests" are structural grep-assertions in a bash repro (`tests/repros/roadmap-modes.sh`, auto-discovered by `tests/run.sh`'s `repros/*.sh` glob) that verify the authored contract, not runtime behavior. Runtime correctness is verified by a live dogfood at the end.

**Tech Stack:** Markdown SKILL.md (YAML frontmatter + prose); POSIX `sh` repro harness; `release.sh` (Gate A tests / Gate B skill-budget / Gate C drift); `gh` for tag + GitHub release; `PORT-LEDGER.json` for parity tracking.

## Global Constraints

- **Port:** Claude-Code-canonical only (`plugin-claude-code/`). Other ports = tracked-drift in `PORT-LEDGER.json`. No propagation this round. (spec §4)
- **Version:** Fold into the current **unreleased v2.37.1** (`plugin.json` already 2.37.1; v2.37.0 is the latest tag/release). Do NOT bump — v2.37.1 is the carrier and gets released. (spec §5)
- **Public repo:** never commit personal info, secrets, internal URLs, or real project/roster names into shipped files (SKILL.md / repro / README). Use generic illustrative examples. (CLAUDE.md Rules)
- **`allowed-tools: Read, Glob, Grep, Bash, Write`** — Write is permitted (this skill persists, like `/codemap`) but the prose must constrain it to `ROADMAP.md` only. (spec §4)
- **Buildable is the only inference:** ▷ ⇔ Band=Next ∧ no blocker found; ⛔ cites its blocker phrase; evidence shown; overridable. (spec §3)
- **Render-then-offer** on stale; write only on explicit `y` or `/roadmap refresh`. (spec §2)
- **`ROADMAP.md` is committed** (shareable); the skill writes it but never auto-commits. Hand-authored `ROADMAP.md` (no `synthesized_at` stamp, e.g. df's portfolio file) → notify + render as-is + never overwrite without `/roadmap refresh`. (spec §2)
- **Budget:** do NOT pre-raise `ARIA_SKILL_BUDGET` (default 18944). Measure summed-description bytes after authoring; raise the baseline in the same commit only if over. (spec §5, prospect §4.3 Step #5)
- **Release validation:** confirm via observable signal (tag + GH release assets resolve), not exit code. (spec §5, prospect §4.4)

---

## File Structure

- **Create** `plugin-claude-code/skills/roadmap/SKILL.md` — the skill (frontmatter + Runtime Gate + mode resolution + read flow + grid spec + rules).
- **Create** `tests/repros/roadmap-modes.sh` — structural contract assertions (auto-discovered by `tests/run.sh`).
- **Modify** `README.md` — one capability-table row + one prose blurb.
- **Modify** `plugin-claude-code/skills/help/SKILL.md` — one `/roadmap` command-table row.
- **Modify** `PORT-LEDGER.json` — record `roadmap` as Code-canonical tracked-drift.
- **Modify (conditional)** `release.sh` — raise `ARIA_SKILL_BUDGET` default only if measured summed-description exceeds 18944.
- **Modify** CLAUDE.md footer + `aria-site` — release-time, after gates green.

---

### Task 1: Author the `/roadmap` skill

**Files:**
- Create: `plugin-claude-code/skills/roadmap/SKILL.md`
- Test: `tests/repros/roadmap-modes.sh` (written in Task 2 — this task is gated by it via TDD ordering; write the test first per Step 1)

**Interfaces:**
- Consumes: `/recap`'s documented `projects_list` resolver pattern (`recap/SKILL.md:66-72`); `/codemap`'s persist+modes+`allowed-tools` pattern (`codemap/SKILL.md:19-37`).
- Produces: a SKILL.md satisfying every assertion in `roadmap-modes.sh` (Task 2). Key authored invariants downstream tasks/tests rely on, by exact token: frontmatter `allowed-tools: Read, Glob, Grep, Bash, Write`; the literal table header `| Feature | Band | Status |`; the literal band tokens `Shipped` `Current` `Next` `Later`; the literal phrase `synthesized_at`; the literal phrase `render-then-offer` (or `render the persisted grid, then`); the phrase `read-only on \`projects_list\``; the phrase `no blocker found`; the phrase `mtime-only` (degradation); the phrase `/roadmap refresh`.

- [ ] **Step 1: Write the failing test first** — see Task 2 (TDD: author `roadmap-modes.sh` before the SKILL.md). Return here once Task 2 Step 1-2 confirm RED.

- [ ] **Step 2: Author the frontmatter**

```markdown
---
description: "Render a per-project feature roadmap — a Band×Status grid (Shipped/Current/Next/Later × done/in-progress/blocked/buildable) synthesized from CLAUDE.md + PROGRESS.md, persisted to a committed ROADMAP.md with staleness-aware refresh. Modes: '/roadmap' (nearest project), '/roadmap <name>' (a projects_list tag), '/roadmap refresh [<name>]' (force re-synthesis). Use when user says '/roadmap', 'show the roadmap', 'what's the roadmap for <project>', 'what's buildable next', 'what's blocked', 'feature status across versions'. Renders + offers refresh when stale; never auto-commits. (Code port — ADR-094.)"
argument-hint: "[<project-name> | refresh [<project-name>]]"
allowed-tools: Read, Glob, Grep, Bash, Write
---
```

- [ ] **Step 3: Author the Runtime Gate** (copy the canonical ADR-094 gate shape from `recap/SKILL.md` lines 11-25, adapted: this is the Claude Code variant; no cowork `/roadmap` exists yet, so use the lighter "proceed without git modes?" gate that `/recap` uses — bare `/roadmap` resolves to this skill; if Bash absent, warn that staleness degrades to mtime-only and ask to proceed).

- [ ] **Step 4: Author "Step 0: Resolve Mode"** — parse first arg: `refresh` → refresh mode (consume optional second arg as `<name>`); any other token → `<name>` (project-named); no arg → project-nearest. Document the resolver **verbatim from `/recap`**: nearest = walk up cwd to nearest `CLAUDE.md`/`PROGRESS.md`; named = read `~/.claude/aria-knowledge.local.md`, parse `projects_list` (`tag:path`, expand `~`), **read-only on `projects_list`**, unknown tag → list tags and stop (no fuzzy match).

- [ ] **Step 5: Author "Read Flow"** — the render-then-offer staleness flow (spec §2): resolve + **print resolved path** → ROADMAP.md absent? synthesize+stamp+write+render FRESH : compute staleness (any source mtime > `synthesized_at` OR `git log <synthesized_from_commit>..HEAD` non-empty) → fresh: render FRESH; stale: **render the persisted grid, then** offer refresh citing why → on `y` re-synthesize+rewrite. Document the hand-authored guard: no `synthesized_at` stamp → notify + render as-is + never overwrite without `/roadmap refresh`. Document `mtime-only` degradation when no git/Bash (omit `synthesized_from_commit`).

- [ ] **Step 6: Author "The Grid"** (spec §3) — the literal table header `| Feature | Band | Status |`; Band column (`Shipped`/`Current`/`Next`/`Later`, collapse-empty-and-note); Status column (✓done / ◐in-progress / ⛔blocked / ▷buildable); the buildable rule (▷ ⇔ Band=Next ∧ `no blocker found`, overridable); the evidence blocks below the grid (every ⛔ cites its phrase; every ▷ says "no blocker found — override if wrong"); self-descriptive rows + cap-and-summarize tail.

- [ ] **Step 7: Author "Rules" + boundaries** (spec §4) — Write only `ROADMAP.md`, only on first-synth / approved-refresh / `/roadmap refresh`; never touches sources; never auto-commits; **read-only on `projects_list`**; print resolved path + staleness verdict every run; degrade loudly; not-`/recap` / not-`/aria-assist` / not-aria-atlas with escalation offers.

- [ ] **Step 8: Run the test to verify it now PASSES**

Run: `sh tests/repros/roadmap-modes.sh`
Expected: `N passed, 0 failed`

- [ ] **Step 9: Commit**

```bash
git add plugin-claude-code/skills/roadmap/SKILL.md tests/repros/roadmap-modes.sh
git commit -m "feat: add /roadmap skill — per-project feature Band×Status grid

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Write the structural contract test (authored BEFORE Task 1's SKILL.md body per TDD)

**Files:**
- Create: `tests/repros/roadmap-modes.sh`

**Interfaces:**
- Consumes: nothing (self-contained bash; reads `plugin-claude-code/skills/roadmap/SKILL.md`).
- Produces: the RED→GREEN gate for Task 1. Auto-discovered by `tests/run.sh` (`repros/*.sh` glob) — no runner edit needed.

- [ ] **Step 1: Write the test file**

```sh
#!/bin/sh
# roadmap-modes.sh — asserts /roadmap SKILL.md documents the 3 modes, the
# committed-ROADMAP.md persist + source-stamp staleness (render-then-offer),
# the Feature|Band|Status grid + buildable-only-in-Next-with-evidence rule,
# the projects_list resolver (read-only, unknown-tag-lists), graceful mtime-only
# degradation, the hand-authored no-clobber + notify guard, and the write-only-
# ROADMAP.md invariant. Claude-executed prose; this checks the contract, not runtime.
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SK="$REPO_ROOT/plugin-claude-code/skills/roadmap/SKILL.md"
PASS=0; FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

[ -f "$SK" ] && ok "A roadmap SKILL.md exists" || bad "A exists" "no roadmap/SKILL.md"

# B: three modes documented
grep -qiE 'nearest' "$SK"        && ok "B nearest mode"        || bad "B nearest" "not documented"
grep -qiE 'projects_list' "$SK"  && ok "B named mode (projects_list)" || bad "B named" "not documented"
grep -qiF '/roadmap refresh' "$SK" && ok "B refresh mode"      || bad "B refresh" "not documented"

# C: resolver — read-only on roster, unknown tag lists tags, no fuzzy
grep -qiE 'read-only on .?projects_list' "$SK" && ok "C read-only on projects_list" || bad "C ro-roster" "guard not documented"
grep -qiE 'unknown tag' "$SK" && ok "C unknown-tag handling" || bad "C unknown-tag" "not documented"
grep -qiE 'no fuzzy' "$SK" && ok "C no fuzzy match" || bad "C no-fuzzy" "not documented"

# D: the grid — Feature|Band|Status header + band tokens + status glyphs
grep -qF '| Feature | Band | Status |' "$SK" && ok "D Feature|Band|Status header" || bad "D header" "grid header not documented"
for b in Shipped Current Next Later; do
  grep -qF "$b" "$SK" && ok "D band token: $b" || bad "D band $b" "not documented"
done
grep -qiE 'done|in-progress|blocked|buildable' "$SK" && ok "D status vocabulary" || bad "D status" "not documented"

# E: buildable is the only inference — Next-only + evidence + overridable
grep -qiE 'no blocker found' "$SK" && ok "E buildable = no blocker found" || bad "E buildable-rule" "not documented"
grep -qiE 'override' "$SK" && ok "E buildable overridable" || bad "E override" "not documented"
grep -qiE 'cite' "$SK" && ok "E blocked cites its phrase" || bad "E cite" "blocker-citation not documented"

# F: staleness — source-stamp, render-then-offer, mtime-only degradation
grep -qiF 'synthesized_at' "$SK" && ok "F synthesized_at stamp" || bad "F stamp" "not documented"
grep -qiE 'synthesized_from_commit' "$SK" && ok "F commit stamp" || bad "F commit-stamp" "not documented"
grep -qiE 'render the persisted grid, then|render-then-offer' "$SK" && ok "F render-then-offer" || bad "F render-then-offer" "not documented"
grep -qiF 'mtime-only' "$SK" && ok "F mtime-only degradation" || bad "F degrade" "not documented"

# G: persist constraints — committed, write-only-ROADMAP.md, never auto-commit, hand-authored guard
grep -qiE 'committed' "$SK" && ok "G ROADMAP.md committed" || bad "G committed" "not documented"
grep -qiE 'never auto-commit|leaves committing to the user' "$SK" && ok "G never auto-commits" || bad "G no-auto-commit" "not documented"
grep -qiE 'hand-authored' "$SK" && ok "G hand-authored guard" || bad "G hand-authored" "not documented"
grep -qiE 'notify' "$SK" && ok "G notify on hand-authored" || bad "G notify" "not documented"

# H: write-only-ROADMAP.md invariant — Write present but constrained in prose
tools=$(grep -m1 '^allowed-tools:' "$SK")
echo "$tools" | grep -qE '\bWrite\b' && ok "H Write present (persist skill)" || bad "H Write" "persist needs Write: $tools"
echo "$tools" | grep -qE '\bBash\b' && ok "H Bash present (git staleness)" || bad "H Bash" "staleness needs Bash: $tools"
grep -qiE 'writes? (only )?.?ROADMAP\.md' "$SK" && ok "H write scoped to ROADMAP.md" || bad "H write-scope" "write-scope not documented"

# I: boundaries — not /recap, not /aria-assist, not aria-atlas
grep -qiE 'not .?/recap|not `?/recap' "$SK" && ok "I distinct from /recap" || bad "I recap" "boundary not documented"
grep -qiE 'aria-assist' "$SK" && ok "I escalation/boundary /aria-assist" || bad "I aria-assist" "not documented"

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
```

- [ ] **Step 2: Run the test to verify it FAILS (RED)**

Run: `sh tests/repros/roadmap-modes.sh`
Expected: FAIL — `A exists — no roadmap/SKILL.md` (SKILL.md not authored yet), nonzero exit.

- [ ] **Step 3: (Proceed to Task 1 to author the SKILL.md, then return to Task 1 Step 8 for GREEN.)** No separate commit — Task 1 Step 9 commits both files together.

---

### Task 3: Verify the full repro suite + measure skill budget

**Files:**
- Modify (conditional): `release.sh:66` (raise `ARIA_SKILL_BUDGET` default only if over)

**Interfaces:**
- Consumes: Task 1 + Task 2 deliverables.
- Produces: green Gate A (full suite) + a known summed-description byte total feeding the Gate B decision.

- [ ] **Step 1: Run the full repro suite**

Run: `sh tests/run.sh`
Expected: all suites pass including `roadmap-modes.sh` (e.g. `NN passed, 0 failed`).

- [ ] **Step 2: Run the plugin test suite**

Run: `sh plugin-claude-code/tests/run.sh`
Expected: all pass (35-ish assertions).

- [ ] **Step 3: Measure summed skill-description bytes** (reproduce Gate B's accounting)

Run:
```bash
total=0; for f in plugin-claude-code/skills/*/SKILL.md; do
  d=$(awk '/^description:/{flag=1} flag{print} /^---$/{if(NR>1)exit}' "$f" 2>/dev/null)
  total=$((total + ${#d}))
done; echo "approx summed description bytes (proxy): see release.sh Gate B for exact"
sh release.sh 2>&1 | grep -iE 'gate B|budget|byte' | head
```
Expected: a `gate B` line reporting summed bytes vs 18944.

- [ ] **Step 4: Conditionally raise the budget** — ONLY if Step 3 shows summed bytes > 18944:

```bash
# release.sh line ~66 — raise the default in THIS commit (per the Gate B comment)
# Example if total were 19200: ARIA_SKILL_BUDGET="${ARIA_SKILL_BUDGET:-20480}"
```
Edit `release.sh` to raise the `:-18944` default to the next reasonable headroom value (round up ~1.5KB). If under budget, **make no edit** and note "budget OK, no raise."

- [ ] **Step 5: Commit (only if Step 4 edited release.sh)**

```bash
git add release.sh
git commit -m "chore: re-baseline ARIA_SKILL_BUDGET for /roadmap skill

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Docs + port ledger

**Files:**
- Modify: `README.md` (capability table row + prose blurb)
- Modify: `plugin-claude-code/skills/help/SKILL.md` (command-table row)
- Modify: `PORT-LEDGER.json` (record `roadmap` Code-canonical)

**Interfaces:**
- Consumes: the shipped skill name/description from Task 1.
- Produces: discoverability + recorded parity drift.

- [ ] **Step 1: Add the `/help` command-table row** — open `plugin-claude-code/skills/help/SKILL.md`, find the command table, add a `/roadmap` row in the orientation cluster (near `/recap`): `| /roadmap [<name>\|refresh] | Per-project feature Band×Status roadmap grid |` (match the table's exact column shape).

- [ ] **Step 2: Add the README capability-table row + blurb** — find the skill/capability table in `README.md`, add a `/roadmap` row mirroring `/recap`'s entry; add a one-sentence prose mention in the orientation-family paragraph. Use generic examples only (no real project names).

- [ ] **Step 3: Bump the PORT-LEDGER version (NOT a surface entry — corrected by plan-prospect).** Sourcing found `PORT-LEDGER.json`'s `claude-code.surfaces` is `{}` (empty by design — only *cowork* surfaces are sha-tracked for drift detection), and `claude-code.version` was stale at `2.36.0` vs `plugin.json` 2.37.1. So the correct edit is a version/parity bump, NOT adding a `roadmap` surface hash. Code-canonical-only status is implicit (the skill simply never appears in cowork's surface list). Edit `PORT-LEDGER.json`:
  - `claude-code.version`: `2.36.0` → `2.37.1`
  - `claude-code.parity_target`: `2.36.0` → `2.37.1`
  - `claude-code.last_parity_pass`: `2026-06-24` → `2026-06-25`
  - Leave `claude-code.surfaces` as `{}` (do not add `roadmap`).

Then run the drift checker to confirm no schema break:

Run: `sh plugin-claude-code/bin/check-port-drift.sh`
Expected: runs clean (report-only). `roadmap` is Code-only by absence from cowork's tracked surfaces — no explicit entry needed.

- [ ] **Step 4: Commit**

```bash
git add README.md plugin-claude-code/skills/help/SKILL.md PORT-LEDGER.json
git commit -m "docs: surface /roadmap in README + /help; record port-drift

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Live dogfood (runtime verification the structural tests can't give)

**Files:** none (verification task).

**Interfaces:**
- Consumes: the installed skill.
- Produces: evidence the skill *behaves* correctly at runtime (the grep-tests only prove it's *authored* correctly).

- [ ] **Step 1: Invoke `/roadmap` on a real project with no ROADMAP.md** (e.g. aria-knowledge itself, or a roster project lacking the file). Expected: synthesizes a Band×Status grid from CLAUDE.md + PROGRESS.md, stamps `synthesized_at` + `synthesized_from_commit`, writes `ROADMAP.md`, renders FRESH, does NOT auto-commit.

- [ ] **Step 2: Invoke `/roadmap` again immediately.** Expected: reads the file, computes FRESH (no source changes since stamp), renders without offering refresh.

- [ ] **Step 3: Touch a source, invoke `/roadmap` again.** Expected: renders the persisted grid THEN offers refresh, citing the changed source/commit-delta. Decline (`n`) → file unchanged.

- [ ] **Step 4: Invoke `/roadmap` on df** (the hand-authored portfolio case). Expected: detects no `synthesized_at` stamp → notifies "looks hand-authored" → renders as-is → does NOT overwrite `df/ROADMAP.md`. **Verify `git status` in df shows no modification.**

- [ ] **Step 5: Invoke `/roadmap <unknown-tag>`.** Expected: lists available `projects_list` tags and stops (no fuzzy match, no guess).

- [ ] **Step 6: Report results to Mike.** If any behavior diverges from the spec, fix the SKILL.md prose, re-run Task 3 Step 1 (suite green), and re-dogfood the affected step before release.

---

### Task 6: Release v2.37.1 to GitHub

**Files:**
- Modify: CLAUDE.md footer (release-time)
- Modify: `aria-site` version badge / feature list (if applicable, per prior release pattern)

**Interfaces:**
- Consumes: green gates from Tasks 3-5.
- Produces: tag `v2.37.1` + GH release + 6 stable aliases; the live release.

- [ ] **Step 1: Read `RELEASING.md`** end-to-end (per Rule 33 — verify the current release contract before invoking it; do not run from memory).

Run: `cat RELEASING.md`
Expected: confirms the build→tag→GH-release→`publish-release.sh` (6 aliases) flow.

- [ ] **Step 2: Build the canonical zip + run all gates**

Run: `sh release.sh`
Expected: Gate A (both suites) pass, Gate B under budget (or at the raised baseline), Gate C drift report clean; `aria-knowledge-plugin-2.37.1.zip` produced.

- [ ] **Step 3: Update the CLAUDE.md footer** — lead the `Last reviewed` footer with the v2.37.1 release (now actually shipping), describing `/roadmap` + the already-present `/recap project`; demote prior detail with a pointer (per `feedback_always_update_claude_md_on_milestone`).

- [ ] **Step 4: Commit the footer + any version-string bumps**

```bash
git add CLAUDE.md
git commit -m "docs: v2.37.1 release notes — /roadmap + /recap project (footer)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 5: Tag + push + GH release** (per RELEASING.md exact commands)

```bash
git push origin main
git tag v2.37.1
git push origin v2.37.1
gh release create v2.37.1 aria-knowledge-plugin-2.37.1.zip \
  --title "v2.37.1 — /roadmap + /recap project (lateral orientation)" \
  --notes "New /roadmap skill (per-project feature Band×Status grid, committed ROADMAP.md, staleness-aware refresh) + the already-built /recap project lateral mode. Claude-Code-canonical; other ports tracked-drift."
sh publish-release.sh   # attaches the 6 stable aliases per RELEASING.md
```

- [ ] **Step 6: Validate via OBSERVABLE signal** (prospect §4.4 — not exit code)

Run:
```bash
gh release view v2.37.1 --json tagName,assets -q '.tagName, (.assets[].name)'
git ls-remote --tags origin v2.37.1
```
Expected: tag `v2.37.1` resolves on origin AND the GH release lists its assets (the canonical zip + the 6 stable-alias assets). If either is missing, the release did NOT land — investigate before claiming done.

- [ ] **Step 7: Update aria-site** (if the prior-release pattern includes a version badge / feature-list bump) — add the v2.37.1 badge + `/roadmap` to the feature list, deploy per the site's flow. Verify the deployed page shows the new version (observable signal).

---

## Self-Review

**1. Spec coverage:**
- spec §1 (identity + 3 modes + defer portfolio) → Task 1 Steps 2,4 + repro B. ✓
- spec §2 (hybrid persist, source-stamp staleness, render-then-offer, mtime degradation, committed, hand-authored guard) → Task 1 Step 5 + repro F,G. ✓
- spec §3 (Band×Status grid, buildable rule, evidence blocks, legibility) → Task 1 Step 6 + repro D,E. ✓
- spec §4 (allowed-tools, write-scope, read-only roster, boundaries, ports) → Task 1 Steps 2,7 + repro C,H,I + Task 4 Step 3. ✓
- spec §5 (v2.37.1 carrier, repro, docs, ledger, measure-then-raise budget, observable release) → Tasks 3,4,6. ✓

**2. Placeholder scan:** No TBD/TODO/"implement later". The only conditional is Task 3 Step 4 (raise budget *only if* measured over) — that's a measured branch, not a placeholder; both arms are specified.

**3. Type consistency:** Token names are consistent across Task 1 (authoring) and Task 2 (assertions): `synthesized_at`, `synthesized_from_commit`, `| Feature | Band | Status |`, band tokens `Shipped/Current/Next/Later`, `no blocker found`, `mtime-only`, `/roadmap refresh`, `read-only on \`projects_list\``. The repro greps for exactly these tokens; Task 1 authors exactly these tokens.

**Note on TDD ordering:** Task 2 (the test) is authored before Task 1's SKILL.md body and verified RED first; Task 1 Step 1 explicitly defers to it. They commit together (Task 1 Step 9) because the test is meaningless without its target and vice-versa — they form one reviewable unit.
