---
description: "Render a per-project feature roadmap — a Band×Status grid (Shipped/Current/Next/Later × done/in-progress/blocked/buildable) synthesized from CLAUDE.md + PROGRESS.md, persisted to a committed ROADMAP.md with staleness-aware refresh. Modes: '/roadmap' (nearest project), '/roadmap <name>' (a projects_list tag), '/roadmap refresh [<name>]' (force re-synthesis). Use when user says '/roadmap', 'show the roadmap', 'what's the roadmap for <project>', 'what's buildable next', 'what's blocked', 'feature status across versions'. Renders + offers refresh when stale; never auto-commits. (Code port — ADR-094.)"
argument-hint: "[<project-name> | refresh [<project-name>]]"
allowed-tools: Read, Glob, Grep, Bash, Write
---

# /roadmap — Per-Project Feature Roadmap Grid

Render a project's **feature roadmap** as a compact `Feature / Band / Status` table — where each feature sits across the version trajectory (the *Band*) and its one current state (the *Status*) — synthesized from the project's own docs and persisted to a committed `ROADMAP.md`. The version-plane counterpart to `/recap` (which orients *temporally* — what just happened) and to aria-atlas (the live *visual* session dashboard). `/roadmap` answers "where does each feature sit, and what's ready to build next?"

## Runtime Gate (per ADR-094)

**Canonical resolution:** This is the Claude Code variant. When both `plugin-claude-code` and `plugin-claude-cowork` are loaded in the same session, bare `/roadmap` resolves to this skill — aria-knowledge (Code) is the canonical owner per ADR-094 §Part 1. No cowork `/roadmap` variant exists yet.

**Before Step 0:** Check that the `Bash` tool is available. If `Bash` is NOT available (non-Code runtime), surface:

> ⚠️ **Runtime mismatch — you invoked `/roadmap` from a non-Code runtime.**
>
> The precise staleness signal compares a stamped commit against `git log` via Bash. Without it, staleness degrades to **mtime-only** (file timestamps), which is coarser. `/roadmap` is currently a Claude-Code-only skill — no cowork variant exists.
>
> **Proceed with mtime-only staleness?** (`y` / `n`)

On `y`: run with mtime-only staleness (omit `synthesized_from_commit`). On `n`/other: exit cleanly. If `Bash` is available, proceed to Step 0.

## Step 0: Resolve Mode

Parse the first argument (case-insensitive):
- `refresh` → **refresh mode** — force re-synthesis + rewrite without the staleness prompt. Consume an optional second argument as the project `<name>`.
- any other token `<name>` → **project-named** — the `<name>:` tag in `projects_list`.
- no argument → **project-nearest** — the current project (walk up from cwd).

### Resolver (verbatim from /recap)

- **project-nearest** (no arg) → walk up from cwd to the nearest `CLAUDE.md`/`PROGRESS.md` (the same Step-1 resolver the other aria-knowledge skills use). No `projects_list` needed.
- **project-named** (`<name>`) → read `~/.claude/aria-knowledge.local.md` and parse the `projects_list:` frontmatter key — comma-separated `tag:path` entries; expand a leading `~` in any path. The typed `<name>` IS the `projects_list` tag (`/roadmap cs` → the `cs:` entry). **Unknown tag → list the available tags and stop (no fuzzy matching).** This is the same roster `/aria-assist` and `/recap` read; **be read-only on `projects_list` — never write it.**

**Always print the resolved project path** so the user can verify which project was read.

## Step 1: Read Flow (render-then-offer)

The persisted `ROADMAP.md` is the fast read, but it is never trusted blindly — every read checks staleness against its sources and offers a refresh when stale.

```
1. Resolve project (Step 0). PRINT the resolved path.
2. ROADMAP.md exists at the project root?
   - NO  → synthesize from sources, stamp, write, render (mark FRESH).
   - YES → compute staleness (Step 2).
```

### Hand-authored guard (no-clobber + notify)

If `ROADMAP.md` exists but has **no `synthesized_at` stamp** in its frontmatter, treat it as **hand-authored** (the stamp is the discriminator — its absence covers both "hand-written" and "a different concept entirely," e.g. a cross-subproject *portfolio* roadmap like `df/ROADMAP.md`). **Notify the user** — e.g. *"`ROADMAP.md` looks hand-authored (no `synthesized_at` stamp) — rendering as-is, will not overwrite without `/roadmap refresh`"* — render it as-is, and **never auto-overwrite**. Converting it to a synthesized file requires an explicit `/roadmap refresh` with a confirm.

## Step 2: Staleness (source-stamp)

The artifact carries a stamp in YAML frontmatter:

```yaml
---
synthesized_at: 2026-06-25
synthesized_from_commit: a1b2c3d   # HEAD at synthesis; OMITTED when not a git repo / no Bash
sources: [CLAUDE.md, PROGRESS.md]
---
```

**Stale** ⇔ any source's mtime is newer than `synthesized_at`, **OR** `git log <synthesized_from_commit>..HEAD` is non-empty. Because `ROADMAP.md` is **committed** and shared, the commit-delta signal correctly catches *anyone's* intervening commits — a teammate's `CLAUDE.md` edit pulled in after synthesis registers as stale. No extra machinery for the multi-author case.

- **Fresh** → render the persisted grid (mark FRESH).
- **Stale** → **render the persisted grid, then** offer refresh, citing why — e.g. *"stale — 4 commits + CLAUDE.md edited since `a1b2c3d`; refresh from synthesis? (y/n)"*. On `y` → re-synthesize + rewrite. A bare invocation **never** auto-rewrites.

**Graceful degradation:** no git repo or no Bash → drop the commit-delta signal, fall back to **mtime-only** staleness, omit `synthesized_from_commit` from the stamp, and say so. Never present a guessed signal as certain.

## Step 3: Synthesize the Grid

Read the sources — the project `CLAUDE.md` (especially the `Last reviewed` footer + status blocks) and `PROGRESS.md` (arc headings + open items). Derive a `Feature / Band / Status` table.

### Band (the *when* — version-trajectory axis)

| Band | Meaning | Resolved from |
|------|---------|---------------|
| Shipped | Released at/before current | versions ≤ current in CLAUDE.md / CHANGELOG |
| Current | The in-flight release | the version the footer/PROGRESS treats as live |
| Next | The immediately planned release | "next up", "vN target", nearest planned |
| Later | Planned / someday | "deferred", "future", "Phase N+" |

Bands **collapse gracefully**: a young project shows only the bands it has and *notes which were empty* rather than rendering blank columns.

### Status (exactly one state per feature)

| Glyph | State | Source |
|-------|-------|--------|
| ✓ | done | transcribed (shipped/complete in prose) |
| ◐ | in-progress | transcribed ("active", "underway", "in-progress") |
| ⛔ | blocked | transcribed — **cites the blocker phrase** |
| ▷ | buildable | **inferred** — Band=Next ∧ no blocker found (overridable) |

**Buildable is the only inference:** ▷ ⇔ `Band = Next` AND **no blocker found** for the feature. Conservative — absence of evidence is NOT buildable unless the feature is in Next; a feature with any named blocker is ⛔, never ▷.

### Rendered shape

```
Roadmap — <project> · synthesized 2026-06-25 from a1b2c3d · FRESH
Resolved path: /Users/.../<project>

| Feature | Band | Status |
|---------|------|--------|
| <feature — short detail if the name isn't self-descriptive> | Current | ✓ done |
| <feature> | Next | ▷ buildable |
| <feature> | Next | ⛔ blocked |
| <feature> | Later | ⛔ blocked |
| +N more (Shipped) | | |

⛔ blockers (cited):
  · <feature> — "<the exact blocker phrase from the prose>"

▷ buildable (Next, no blocker found — override if wrong):
  · <feature> · <feature>
```

The **evidence blocks below the grid** are the honesty mechanism: every ⛔ **cites** the phrase that justifies it; every ▷ is explicitly "no blocker found — override if wrong", so the one inferred axis stays falsifiable.

**Legibility:** self-descriptive rows (a bare feature name gets a short `— detail` clause when not clear on its own); cap + summarize the tail (~12–15 feature rows, then a `+N more (Shipped)` summary row grouping the shipped tail).

## Step 4: Write (only on synthesis / approved refresh)

When synthesizing (first run) or on an approved refresh, write the grid + frontmatter stamp to `ROADMAP.md` at the project root. **`ROADMAP.md` is committed** (a shareable team artifact — teammates see the synthesized roadmap). The skill **writes only `ROADMAP.md`** and **leaves committing to the user** — it never auto-commits and never touches any source file. The file simply appears in `git status` for the user to stage.

## Rules

- **Write only `ROADMAP.md`** — only on first synthesis, an approved refresh (`y`), or `/roadmap refresh`. Never touch CLAUDE.md / PROGRESS.md / SESSION.md / any source. Never auto-commit.
- **Read-only on `projects_list`** — never write the roster (same rule as `/recap`).
- **Buildable is the only inference** — narrow (Next + no blocker found), overridable, evidence shown.
- **Print the resolved project path + the staleness verdict (and why)** every run. Never present a guessed scope as certain.
- **Degrade loudly** — no git/Bash → mtime-only staleness, say so.
- **Honor the hand-authored guard** — no `synthesized_at` stamp → notify + render as-is + never overwrite without `/roadmap refresh`.
- **Not `/recap`** — recap orients *temporally* (what just happened); roadmap orients on the *version-trajectory plane*. May offer "`/recap` for recent changes."
- **Not `/aria-assist`** — assist *recommends what to do today* (PM judgment + writes proposals); roadmap *renders state* and stops. May offer to escalate to `/aria-assist` for prioritization.
- **Not aria-atlas** — atlas is the live *visual* session-state dashboard; roadmap is the terminal *feature-by-version* artifact.
