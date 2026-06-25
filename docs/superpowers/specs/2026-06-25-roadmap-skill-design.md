# `/roadmap` skill — design

**Date:** 2026-06-25
**Target version:** v2.37.1 (current unreleased; `/roadmap` folds in, then v2.37.1 ships to GitHub)
**Port:** Claude-Code-canonical only (`plugin-claude-code/`); other ports recorded as tracked-drift in `PORT-LEDGER.json`, no propagation this round.
**Status:** Approved (brainstorm complete) — pending `/prospect`.

---

## 1. Identity & Scope

`/roadmap` is a **read-mostly orientation skill** that renders a project's **feature-by-feature status grid** organized across the version trajectory. It joins the orientation family (`/recap`, `/aria-assist`, `/stats`) but owns a plane none of them cover: *where each feature sits across the version trajectory, and what is ready to build next.*

It is the **CODEMAP-for-the-version-plane**: a persisted synthesis (`ROADMAP.md`) with staleness-aware refresh, exactly as `/codemap` persists a code synthesis.

**Modes / scope:**
- `/roadmap` → nearest project (walk-up from cwd to the nearest `CLAUDE.md`/`PROGRESS.md`, the standard aria Step-1 resolver).
- `/roadmap <name>` → the `<name>:` tag in `projects_list` (the **verbatim `/recap` resolver**: read `~/.claude/aria-knowledge.local.md`, parse `projects_list`, expand a leading `~`, read-only on the roster; unknown tag → list available tags and stop, no fuzzy match).
- `/roadmap refresh [<name>]` → force a re-synthesis + rewrite of `ROADMAP.md` without the staleness prompt.

**Deferred (NOT v1):** a portfolio / `all` view across every project. A cross-project roadmap is a different artifact shape (portfolio milestones, not feature-by-version), and aria-atlas + `/recap project all` already serve "glance across everything." Designed so a future `all` mode can be added without reworking the single-project core.

---

## 2. Data source — hybrid persist + staleness-aware refresh

### The artifact: per-project `ROADMAP.md`

YAML frontmatter carries the staleness stamp:

```yaml
---
synthesized_at: 2026-06-25
synthesized_from_commit: a1b2c3d   # HEAD at synthesis; OMITTED if not a git repo / no Bash
sources: [CLAUDE.md, PROGRESS.md]  # what was read
---
```

`ROADMAP.md` is **committed** (a shareable team artifact — teammates see the synthesized roadmap; not a local-only file like `SESSION.md`). The skill *writes* the file but **leaves committing to the user** (family posture: offer, never auto-commit — `/roadmap` is not a committing skill; the file simply appears in `git status` for the user to stage).

**Clobber-safety + notify (hand-authored case).** Some projects already track a hand-authored `ROADMAP.md`. **Verified example (prospect 2026-06-25):** `df/ROADMAP.md` exists, is git-tracked, and is a *"Designframe Portfolio Roadmap"* — a cross-subproject portfolio view, i.e. a different *concept* from this skill's single-project feature-grid (and the very portfolio shape this skill defers). The skill writes `ROADMAP.md` only when absent or on an approved refresh; if a `ROADMAP.md` exists with **no `synthesized_at` stamp**, treat it as hand-authored (the stamp is the discriminator — its absence covers both "hand-written" and "different concept" cases) — **notify the user** (e.g. *"`ROADMAP.md` looks hand-authored (no `synthesized_at` stamp) — rendering as-is, will not overwrite without `/roadmap refresh`"*), render it as-is, and never auto-overwrite. Converting it to a synthesized file requires an explicit `/roadmap refresh` with a confirm.

### Sources of truth (read; the roadmap is never itself treated as truth)

- Project `CLAUDE.md` — especially the `Last reviewed` footer + status blocks.
- `PROGRESS.md` — arc headings + open (TODO / in-progress) items.
- `git log` — supplies the commit-delta staleness signal only.

These are the same canonical surfaces `/recap` and `/aria-assist` read.

### Read flow (every invocation)

1. Resolve project (nearest, or `<name>` via `projects_list`). **Print the resolved path.**
2. `ROADMAP.md` exists?
   - **No** → synthesize from sources, stamp, write, render (marked FRESH).
   - **Yes** → compute staleness.
3. Staleness (Option A — source-stamp): **stale** ⇔ any source's mtime is newer than `synthesized_at`, **OR** `git log <synthesized_from_commit>..HEAD` is non-empty. Because `ROADMAP.md` is committed and shared, the commit-delta signal correctly catches **anyone's** intervening commits (not just the local author's) — a teammate's CLAUDE.md edit pulled in after synthesis registers as stale via `<synthesized_from_commit>..HEAD`. The multi-author case needs no extra machinery.
   - **Fresh** → render the persisted grid (marked FRESH).
   - **Stale** → render the persisted grid, then **offer refresh, citing why** (e.g. *"stale — 4 commits + CLAUDE.md edited since `a1b2c3d`; refresh from synthesis? (y/n)"*). On `y` → re-synthesize + rewrite. Never auto-rewrites on a bare invocation.

**Render-then-offer** (not refresh-then-render): the user always sees something immediately and is told the staleness verdict; writes happen only on explicit `y` or `/roadmap refresh`.

### Graceful degradation (inherited from `/recap project`)

No git repo or no Bash → drop the commit-delta signal, fall back to **mtime-only** staleness, omit `synthesized_from_commit` from the stamp, and **say so**. Never pretend a precise signal exists.

---

## 3. The grid — two-column model: Band + Status

A feature sits in exactly one band with exactly one state, so Band and Status are orthogonal single-value columns (no sparse matrix).

**Band column** (the *when* — version-trajectory axis; rows may be grouped by it):

| Band | Meaning | Resolved from |
|------|---------|---------------|
| Shipped | Released at/before current | versions ≤ current in CLAUDE.md / CHANGELOG |
| Current | The in-flight release | the version the footer/PROGRESS treats as live |
| Next | Immediately planned release | "next up", "vN target", nearest planned |
| Later | Planned / someday | "deferred", "future", "Phase N+" |

Bands **collapse gracefully**: a young project shows only the bands it has and *notes which were empty* rather than rendering blank columns.

**Status column** (exactly one state):

| Glyph | State | Source |
|-------|-------|--------|
| ✓ | done | transcribed (shipped/complete in prose) |
| ◐ | in-progress | transcribed ("active", "underway", "in-progress") |
| ⛔ | blocked | transcribed — **cites the blocker phrase** |
| ▷ | buildable | **inferred** — Band=Next ∧ no blocker found (overridable) |

**Buildable rule (the only inference):** ▷ ⇔ `Band = Next` AND no blocker phrase found for the feature. Conservative — absence of evidence is NOT buildable unless the feature is in Next; a feature with any named blocker is ⛔, never ▷. Always overridable.

### Rendered shape

```
Roadmap — aria-knowledge · synthesized 2026-06-25 from a1b2c3d · FRESH
Resolved path: /Users/.../aria/aria-knowledge

| Feature                          | Band    | Status      |
|----------------------------------|---------|-------------|
| /recap orientation               | Current | ✓ done      |
| /roadmap skill                   | Current | ◐ in-prog   |
| Portfolio /roadmap all           | Next    | ▷ buildable |
| Cowork cap-trim pass             | Next    | ▷ buildable |
| Synapse Wave 2                   | Next    | ⛔ blocked  |
| aria-core public visibility flip | Later   | ⛔ blocked  |
| +6 more (Shipped)                |         |             |

⛔ blockers (cited):
  · Synapse Wave 2 — "R-D1 (DB provider) gates P-S1 exec"
  · aria-core public flip — "deferred per Mike's call"

▷ buildable (Next, no blocker found — override if wrong):
  · Portfolio /roadmap all · Cowork cap-trim pass
```

**Evidence blocks below the grid** are the honesty mechanism: every ⛔ cites the phrase that justifies it; every ▷ is explicitly "no blocker found — override if wrong", keeping the one inferred axis falsifiable.

**Legibility rules (carried from `/recap`):** self-descriptive rows (a bare feature name gets a short `— detail` clause when not clear on its own); cap + summarize the tail (~12–15 feature rows, then a `+N more (Shipped)` summary row grouping the shipped tail).

---

## 4. Rules, boundaries & `allowed-tools`

**`allowed-tools: Read, Glob, Grep, Bash, Write`** — the one orientation skill that persists (like `/codemap`). Writes are constrained:
- Writes **only** `ROADMAP.md`, **only** on first synthesis / approved refresh (`y`) / `/roadmap refresh`. Never touches CLAUDE.md / PROGRESS.md / SESSION.md / any source.
- **Read-only on `projects_list`** (verbatim `/recap` rule).

**Boundaries — what it is NOT:**
- **Not `/recap`** — recap orients *temporally* (what just happened); roadmap orients on the *version-trajectory plane*. May offer "`/recap` for recent changes."
- **Not `/aria-assist`** — assist *recommends what to do today* (PM judgment + writes proposals); roadmap *renders state* and stops. May offer to escalate to `/aria-assist` for prioritization.
- **Not aria-atlas** — atlas is the live *visual* session-state dashboard; roadmap is the terminal *feature-by-version* artifact.

**Honesty rules (family-carried):**
- Buildable is the only inference — narrow, overridable, evidence shown.
- Print the resolved project path + the staleness verdict (and *why*) every run.
- Degrade loudly — no git/Bash → mtime-only staleness, say so.

**Ports:** Claude-Code-canonical only for v1 (Bash/git-native staleness signal). Recorded as tracked-drift in `PORT-LEDGER.json`, matching how `/recap`, `/auto`, and recent skills shipped. Cowork's summed-description cap is already over budget → propagation is a deliberate later pass.

---

## 5. Delivery

- **Version:** folds into the current **unreleased v2.37.1** (already contains `/recap project`; not yet tagged/GH-released). v2.37.1 then ships to GitHub carrying both lateral-orientation features.
- **New skill:** `plugin-claude-code/skills/roadmap/SKILL.md`.
- **Tests:** new repro `roadmap-modes.sh` — synthesis-on-absent, staleness verdict (stale/fresh), mtime-only degradation when no git, band/status vocabulary, buildable-cites-evidence + buildable-only-in-Next, write-only-`ROADMAP.md` invariant, `<name>` resolver + unknown-tag-lists-tags, hand-authored-no-clobber + notify-when-hand-authored.
- **Docs:** README prose + capability table updated; `/help` command table updated; `PORT-LEDGER.json` records `roadmap` as Code-canonical tracked-drift.
- **Release:** spec → `/prospect` → plan → `/prospect` → execute (TDD) → `release.sh` (Gate A tests, Gate B skill-budget, Gate C drift) → tag `v2.37.1` + GH release + 6 stable aliases per `RELEASING.md` → README/aria-site update as applicable.
- **Budget (prospect §4.3 Step #5):** do NOT pre-raise `ARIA_SKILL_BUDGET` (default 18944). Write the SKILL.md description, measure the summed-description bytes, and raise the baseline *in the same commit* only if over — per the `release.sh` Gate B comment.
- **Release validation (prospect §4.4 — bundle-unverification counter-discipline):** confirm the release via an **observable signal** — the `v2.37.1` git tag and the GH release assets resolving — not the `release.sh`/`gh` exit code alone (per `feedback_deploy_validation_via_observable`).

---

## 6. Resolved decisions

| Fork | Decision |
|------|----------|
| Data source | **C — hybrid** persist + synthesis, with a staleness check on every read that offers refresh when stale. |
| Staleness signal | **A — source-stamp** (`synthesized_at` + `synthesized_from_commit`); stale = source newer than stamp OR commits since. Degrades to mtime-only without git/Bash. |
| Scope | `/roadmap` = nearest; `/roadmap <name>` = `projects_list` tag. Portfolio `all` deferred. |
| Grid shape | **A-banded → normalized to two columns**: Band (Shipped/Current/Next/Later) + Status (one of ✓/◐/⛔/▷). |
| Buildable | **A — explicit-blocker-driven, conservative**: ▷ = Next ∧ no blocker found; ⛔ cites its phrase; evidence shown; overridable. |
| Stale read behavior | **Render-then-offer** (show stale grid, offer refresh; write only on `y`/`refresh`). |
| Version | Fold into unreleased **v2.37.1**; release it to GitHub. |
| Ports | Claude-Code-canonical only. |
