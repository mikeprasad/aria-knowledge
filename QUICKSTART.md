# ARIA Quickstart

Set up in five minutes. Then two habits — one per session, one per week.

Everything you need is in **Getting Started**. It ends with an explicit stop line.
**Advanced Usage** below is optional, organised by job, and worth reading when a
particular job calls for it — not before.

---

# Getting Started

## 1. Setup

Three commands, about five minutes, no existing knowledge required.

### Install the plugin

```
/plugin marketplace add https://github.com/mikeprasad/aria-knowledge
/plugin install aria-knowledge@latest
```

Codex, Cursor and Antigravity users: see the matching port in the latest release
for editor-specific install.

### Run `/setup`

```
/setup
```

The wizard walks you through:

- **Knowledge folder location** — typically a `knowledge/` folder you commit to your own private git repo, separate from ARIA itself
- **Audit cadences** — when to prompt you for `/audit-knowledge` and `/audit-config` (defaults are sensible)
- **Advanced options** — toggles like `active_knowledge_surfacing` (recommended: keep `true`)
- **Project setup (optional)** — configure `projects_list` here if you want per-project knowledge tiers and proactive CODEMAP/STITCH surfacing

A first run creates the knowledge folder structure (`approaches/`, `decisions/`,
`rules/`, `references/`, `intake/`) and seeds the working-rules + change-decision
framework.

### Build the initial index

```
/index
```

Scans your knowledge folder, builds `index.md` with the tag index, and flags any
untagged files. Re-run whenever you add or move knowledge files.

### Confirm it's wired

```
/stats
```

Shows knowledge base health: file counts, intake backlog status, audit dates,
codemap status, index health. If `/stats` works, ARIA is configured.

**Installed.** Next: the rhythm you run each session.

---

## 2. Per Session

The five-step rhythm. Once you are set up, this is all a session asks of you.
The effort is front-loaded into setup and two session-boundary habits; the
expensive judgment work stays selective.

### 1. Start at your Projects folder, name the project

```
project-name
# or, to resume the last session exactly where it stopped:
project-name handoff
```

Keep one Projects folder with `knowledge/` inside it and each project as a
sibling. Start the session at that level and name the project. Add `handoff` to
pick up from the `SESSION.md` the last close-out wrote.

ARIA's `SessionStart` hook surfaces context-setting reminders. With projects
configured it also loads that project's CODEMAP directory and announces it —
`[aria] Loaded CODEMAP directory for <tag> (N days fresh)`. No silent context
injection. Manual fallback:

```
/context <project-tag>
```

That loads all knowledge files matching the project's tags:

```
Found 7 files matching: [project-a] (OR)

## Cross-project (4 files)
1. decisions/004-state-sync.md — State sync between AI and wizard
2. approaches/api-pagination.md — Cursor-based pagination patterns
…

## Tracked artifacts (2)
8. <project-a>/CODEMAP.md — 8 days fresh
9. <project-a>/STITCH.md — 18 days fresh

Load which files? (all / numbers / none)
```

Pick what's relevant and load it.

### 2. Spec and plan, then pre-mortem

```
/prospect <plan>
```

Plan the work first, then run `/prospect` on the plan before executing. The
pre-mortem earns its keep for anything touching more than about three files or
resting on an unmeasured assumption — it catches corrections that are cheap now
and expensive after the first edit.

### 3. Execute — the discipline layer runs itself

Code, write, debug, refactor. ARIA stays mostly invisible. Rule 22 fires before
every non-trivial edit, emitting a block that declares impact and the change
being made, with no action needed from you.

**Don't bypass the markers.** If one feels unnecessary, that is a signal to
assess impact, not to skip. See [Decision discipline](#decision-discipline-rule-22)
for the full framework.

Keep commits atomic — one concern per commit is what makes `/retrospect`
produce useful output later.

### 4. Retrospect after big or critical work

```
/retrospect <range>
```

After auth, migrations, releases — anything whose failure costs more than its
success saves. It produces the failure-mode patterns that stop the same mistake
twice. Skip it for trivial changes; match the ceremony to the risk.

### 5. Close the session with one command

```
/handoff auto     # work continues next session
/wrapup auto      # nothing to carry forward
```

These are different intents, not fast versus full.

- **`/handoff auto`** — full close-out (PROGRESS, CLAUDE.md, memory, commit) plus a paste-ready opener for the next session.
- **`/wrapup auto`** — the same close-out with no opener.

Both capture knowledge on the way out, both commit locally, and neither ever
pushes. Don't leave uncommitted work without a reason — the next session starts
confused. If you must, leave a note in PROGRESS.md.

### Why this shape

ARIA models knowledge as a five-phase loop:

```
capture → govern → promote → apply → refresh
```

| Phase | What happens | Primary skills |
|-------|-------------|----------------|
| **Capture** | Insights, decisions, URLs, snippets enter the intake backlog | `/intake`, `/snapshot`, `/extract`, inline `★ Insight` blocks |
| **Govern** | You review intake at audit cadence; decide what's load-bearing vs noise | `/audit-knowledge` |
| **Promote** | Approved items move from intake into the promoted tree with tags | `/audit-knowledge` (auto-routes) |
| **Apply** | Promoted knowledge actively shapes the next decision | `/context`, `/rules`, `/codemap`, `/stitch`, `/distill`, `/prospect`, `/retrospect` |
| **Refresh** | Stale items get re-verified, archived, or removed | `/audit-knowledge`, `/index` |

The point is the apply phase. Knowledge that gets captured but never retrieved
is overhead, not memory.

---

## 3. Weekly

Two commands most weeks; the rest when prompted. ARIA prompts you when a cadence
is overdue, so in practice you are confirming rather than remembering.

| Command | Cadence | Why |
|---------|---------|-----|
| **`/audit-knowledge`** | Weekly, or 20+ intake entries / 7+ days | Reviews what was staged and promotes what you approve into the tagged tree. This is the step that turns capture into memory — skip it and the backlog just grows. |
| **`/index`** | Straight after the audit | Rebuilds the tag index over what was just promoted; flags untagged files, detects stale ones. |
| **`/stats`** | Any time you wonder | File counts, backlog depth, audit status, codemap dates, coverage gaps. |
| **`/audit-config`** | Every ~14 days | Catches CLAUDE.md / settings / config drift and references that no longer resolve. |
| **`/codemap update`** | When a feature ships, or ~14 days | Refreshes the per-project map so retrieval keeps pointing at code that still exists. |
| **`/stitch verify`** | Multi-repo only, ~30 days | Cross-repo contracts drift slowly and silently. |

**Don't delete knowledge files.** ARIA archives instead of deletes. If you
outgrow a decision, archive it with a pointer to its replacement. Future-you may
need the context.

---

> ## That's the whole loop.
>
> Setup once, five steps a session, a short pass most weeks. Everything below is
> optional — it is there for when a specific job calls for it, not reading you
> owe before you start.

---

# Advanced Usage

Seven jobs. Each is a short flow plus the commands that serve it.

## Knowledge intake

**Getting things in.** Capture is deliberately cheap, because the audit pass
triages later. If something feels worth keeping, keep it.

```
/intake <url>  →  work  →  /extract  →  /audit-knowledge promotes it
```

| Command | What it does |
|---------|--------------|
| `/intake <src>` | Clip a URL or snippet whole; bulk-scan a file, directory or glob. |
| `/intake extract <src>` | Decompose a source into backlog entries rather than clipping it whole. |
| `/intake doc <src>` | Capture one structured artifact as a reflection document. |
| `/intake thread <id>` | Pull a chat or email thread via MCP. |
| `/snapshot` | Save the full transcript on demand, before compaction erases it. |
| `/extract` | Scan the conversation for uncaptured insights, decisions and rationale. |
| `/interview <topic>` | The inverse of extract — ARIA asks you questions to get a topic out of your head. |
| `/backlog` | See what is staged and waiting for review; triage before an audit. |

Inline `★ Insight` blocks Claude emits during work are auto-captured to the
intake backlog at session end.

> **Note:** `/clip`, `/clip-thread` and `/extract-doc` were retired into
> `/intake` in v2.33.0. A bare URL now clips whole; use `/intake extract <url>`
> to mine it instead.

## Retrieval and recall

**Getting things back out.** The phase the rest exists to serve.

```
/context <project>  at session start  →  /ask when a question comes up
```

| Command | What it does |
|---------|--------------|
| `/context <tag>` | Load promoted knowledge for a topic or project into the session. |
| `/ask "<question>"` | Checks what you already know before researching, then saves the answer as a knowledge doc. |
| `/rules 22` | Quick lookup into the working rules, by number or topic. |

### Retrieval vocabulary

Three layers of "make my files findable":

| Layer | What it is | When to use |
|-------|-----------|-------------|
| **Tags** | Exact-match controlled vocabulary in frontmatter `tags:` | Default. Your authoritative category labels. |
| **Semantic-hints** | Substring-matched free-form phrases in `semantic-hints:` | When a file is about a concept you might search for under several names. Hyphenation is normalized; case-insensitive. |
| **Aliases** | User-edited map at `aliases.md` (e.g. `` `k8s` → `kubernetes` ``) | When a nickname should resolve to a canonical tag for everyone using the knowledge base. |

Example frontmatter:

```yaml
---
name: cursor-pagination
description: Cursor-based pagination patterns for paginated APIs
type: approach
tags: [api, pagination]
semantic-hints:
  - cursor pagination
  - keyset pagination
  - infinite scroll
---
```

All of these surface that file:

- `/context api` — tag match
- `/context cursor` — semantic-hint substring
- `/context infinite-scroll` — semantic-hint substring, hyphen-normalized
- `/context pg` — if `` `pg` → `pagination` `` is declared in `aliases.md`

## Code review and quality gates

**Four moments, four gates.** Each sits at a different point in the arc. Reach
for the one matching where you actually are.

```
/prospect  →  build  →  /preflight  →  ship  →  /retrospect
```

| Command | When |
|---------|------|
| `/prospect <plan>` | Before executing — a structured pre-mortem with an evidence-sourcing pass. Per-step verdicts: PROCEED / SHRINK / SPLIT / DEFER / KILL. |
| `/preflight` | Before you claim done — six executed checks, each PASS, FAIL or INVALID. An unrun check blocks the verdict. |
| `/retrospect <range>` | After shipping — per-fix validation over a commit range, PR, release or deployment. |
| `/foundational-review` | Before something irreversible — a version freeze, a public repo flip, a major re-scope. |
| `/readiness-audit` | Recurring — is this surface clean, legal and consistent to ship for THIS event? |

Opt-in hooks can offer `/prospect` on plan-writes and `/retrospect` after
qualifying pushes (`auto_prospect` / `auto_retrospect`; start with `nudge`
before `run`).

### Decision discipline (Rule 22)

The change-decision framework. For non-trivial edits, declare:

1. **What changed** — which artifact, what concretely changes
2. **Why** — what problem this solves, what evidence supports the approach
3. **Solutions considered** — explicit alternatives ruled out
4. **Decision made** — the picked path
5. **How** — implementation specifics
6. **Verification** — how you'll confirm it worked
7. **Post-edit check** — scope held? unintended impact?

**High Impact** (auth, migrations, model changes, public-facing surfaces,
critical paths): full 7-step framework.
**Low Impact** (docs, single-file refactor, formatting): lighter scope check.

Bypassing markers because "this is too simple" is the most common way bugs ship.
The discipline is a cheap insurance policy. Tune assessment depth per path with
`critical_paths` (upgrade) and `planning_paths` (downgrade).

## Session management

**Start clean, end clean.** Pick by whether work carries forward, not by how
much time you have.

```
project-name handoff  →  work  →  /handoff auto  or  /wrapup auto
```

| Command | What it does |
|---------|--------------|
| `project-name handoff` | Resume exactly where the last session stopped, from the `SESSION.md` it wrote. |
| `/handoff auto` | Full close-out plus a paste-ready opener for the next session. |
| `/handoff brief` | An 80–150 word coworker-facing prose brief instead. No file writes. |
| `/handoff snap` | Like `auto`, but archives the transcript via `/snapshot` for later extraction instead of running `/extract` now. Use when context is high. |
| `/wrapup auto` | The same close-out when nothing carries forward — no opener. |
| `/recap` | Read-only orientation. Modes for session, arc, commit, push, pull and project. |
| `/statusline` | Install the context-window and plan-usage meter in the CLI. |

## Codebase mapping

**Give the model a map** instead of making it re-read the repo every session.

```
/codemap  →  ship a feature  →  /codemap update
```

| Command | What it does |
|---------|--------------|
| `/codemap` | Full scan; produces a feature-organized `CODEMAP.md` at project root. |
| `/codemap inventory` | Quick index-only mode, no full generation. |
| `/codemap update` | Incremental refresh after feature work. |
| `/codemap section <name>` | Rebuild one section. |
| `/distill <task>` | Turn raw task text into a tiered executable spec, auto-tiered by complexity. |

`CODEMAP.md` is structured for **selective loading** — a directory section at the
top (20–40 lines) with feature sections below (50–200 lines each) pulled on
demand. When you `cd` into a configured project, ARIA auto-loads the directory
section and lets you pull specific feature sections as needed.

### Multi-repo projects

For workspaces with multiple sub-repos (backend + web + mobile):

| Command | What it does |
|---------|--------------|
| `/stitch create <tag>` | Generates `STITCH.md` at workspace root. |
| `/stitch verify <tag>` | Check cross-repo contracts haven't drifted. |
| `/stitch diff <tag>` | Show differences since last verify. |

`STITCH.md` captures cross-repo bindings: the auth flow (which frontend module
calls which backend endpoint), the endpoint matrix, and the per-repo CODEMAP
sections that need to stay in sync. It auto-loads alongside the umbrella CODEMAP
when you activate a multi-repo project.

The trigger is **two or more codebases bound by a shared contract** — separate
repos, or a monorepo with a `contract/` directory feeding several clients.

## Autonomous execution

**Hand over a goal, not a step.** The heaviest thing here. It composes the whole
arc and decides objectively-checkable forks itself, stopping when a fork
genuinely needs you.

```
brainstorm → spec → /prospect → plan → /prospect → TDD → /retrospect
```

| Command | What it does |
|---------|--------------|
| `/auto` | Drive a full execution arc from a goal, with the gates composed in. A bare `/auto` opens the config picker rather than guessing. |
| `/auto execute <plan>` | Skip ideation and run an existing plan, spec or ticket. |
| `/auto plan` | Stop at a prospected plan. Writes no code. |
| `/auto config` | Guided per-run picker for the knobs. Never persists. |

Three orthogonal axes, one word each: **authority** (`full` — everything except
push, which nothing can pre-authorize), **presence** (`attended` / `unattended`),
**duration** (`continue` / `stop`). Any decision that could not be objectively
validated is logged to a judgment ledger and handed back to you at close.

## Corpus health and sharing

**The deeper audits** — beyond the weekly pass, plus the tier that moves personal
knowledge to the team.

```
/audit  routes to whichever sub-audit fits
```

| Command | What it does |
|---------|--------------|
| `/audit` | Umbrella that routes to the sub-audits. |
| `/audit-style` | Mine past session logs for revealed working-style rules — proven by what you did. Opt-in. |
| `/audit-usage` | A value report over your own corpus, measured from your prospect and retrospect logs. Opt-in. |
| `/audit-share` | Batch-review personal knowledge for promotion to the team-shared tier. |
| `/roadmap` | A per-project Band × Status grid synthesized from your project docs. |
| `/aria-assist` | Morning product-management review across all configured projects. |

---

## When ARIA Adds Value (and When It Doesn't)

**Adds value when:**

- You work across multiple sessions on related problems
- You collaborate with future-you on similar codebases
- You ship non-trivial changes with multi-step plans
- You want decisions and rationales to compound, not evaporate
- You maintain more than one project and need them kept straight

**Doesn't add value when:**

- You're doing one-off exploratory work with no future relevance
- You're new to a codebase and have nothing yet to capture (use ARIA after a few weeks)
- You're allergic to discipline (the markers and cadences are the point)

---

## Troubleshooting

### "Hook error" labels on every tool call

Cosmetic Claude Code UI bug ([anthropic/claude-code#17088](https://github.com/anthropics/claude-code/issues/17088)).
The hooks are working correctly; the label is misleading. Ignore.

### `/setup` says my config is missing fields

That's the self-audit catching drift. Run `/setup` again to add missing fields
with defaults.

### `/context` returns nothing for tags I think exist

Run `/index` first — your `index.md` may be out of date. Then re-try. If still
nothing, check spelling and the file's frontmatter `tags:` field.

### Active surfacing is too noisy

Set `active_knowledge_surfacing: false` in your config. Hooks fall back to
passive `/context` suggestions; skills skip auto-loading. You can re-enable any
time.

### A skill I expect doesn't exist

Run `/help` to see what's installed at your version. If a skill from a release
note isn't there, your installed version may be older than that note's target.
Update via `/plugin install aria-knowledge@latest` and re-run `/setup`.

---

## What to Read Next

- [README.md](README.md) — full feature catalog, philosophy, model recommendations
- [CHANGELOG.md](CHANGELOG.md) — version history
- `/help` — every installed skill with a one-line summary and model recommendations
- [LICENSE](LICENSE) — CC BY-NC-SA 4.0 (non-commercial use; copyleft on derivatives)

---

**The shortest summary of ARIA:** capture once, retrieve forever, decide with
discipline. The five-phase lifecycle is the loop; Rule 22 is the discipline;
tags + hints + aliases are the retrieval surface; CODEMAP + STITCH are the
structural memory; `/prospect` + `/retrospect` are the review cycle. Everything
else is plumbing in service of those.
