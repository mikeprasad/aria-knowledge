# ARIA Quickstart

Get ARIA running in 5 minutes. Then learn the rhythm that makes it valuable.

> **Already installed?** Jump to [Best Practices](#best-practices-by-session-phase) or [Common Patterns](#common-patterns).

## 5-Minute Setup

### 1. Install the plugin

```
/plugin marketplace add mikeprasad/aria-knowledge
/plugin install aria-knowledge@latest
```

### 2. Run `/setup`

```
/setup
```

The wizard walks you through:
- **Knowledge folder location** — typically `~/Projects/knowledge/` (a folder you'll commit to your own private git repo, separate from ARIA itself)
- **Audit cadences** — when to prompt you for `/audit-knowledge` and `/audit-config` (defaults are sensible)
- **Advanced options** — toggle features like `active_knowledge_surfacing` (recommended: keep `true`)
- **Project setup (optional)** — if you want per-project knowledge tiers and proactive CODEMAP/STITCH surfacing, configure `projects_list` here

A first run creates the knowledge folder structure (`approaches/`, `decisions/`, `rules/`, `references/`, `intake/`) and seeds the working-rules + change-decision framework.

### 3. Build the initial index

```
/index
```

Scans your knowledge folder, builds `index.md` with the tag index, and flags any untagged files. Re-run whenever you add or move knowledge files.

### 4. Confirm it's wired

```
/stats
```

Shows your knowledge base health: file counts, intake backlog status, audit dates, codemap status, index health. If `/stats` works, ARIA is configured.

**You're ready.** The rest of this doc explains how to use it well.

---

## Your First Session — A Walkthrough

The fastest way to understand ARIA: do a real session with it.

### Before you start

When Claude Code launches, ARIA's `SessionStart` hook runs and surfaces context-setting reminders. If you've configured projects, it'll also auto-load (with your permission) the relevant CODEMAP directory for the project containing your `$PWD`.

If you know which project you're working on:

```
/context <project-tag>
```

This loads all knowledge files matching that project's tags. You'll see something like:

```
Found 7 files matching: [project-a] (OR)

## Cross-project (4 files)
1. decisions/004-state-sync.md — State sync between AI and wizard
2. approaches/api-pagination.md — Cursor-based pagination patterns
…

## Tracked artifacts (2)
8. ~/Projects/project-a/CODEMAP.md — 8 days fresh
9. ~/Projects/project-a/STITCH.md — 18 days fresh

Load which files? (all / numbers / none)
```

Pick what's relevant and load it.

### During work

Code, write, debug, refactor — normal flow. ARIA stays mostly invisible. Two interventions you'll notice:

1. **Rule 22 markers**: before any non-trivial edit, Claude emits a `[Rule 22 · Scope]` block declaring impact + the change being made. **Don't bypass these.** They enforce decision discipline and become the audit trail.

2. **Active surfacing**: when you `cd` into a configured project or spawn a subagent, ARIA proactively surfaces relevant knowledge files + the project's CODEMAP directory. You'll see `[aria] Loaded CODEMAP directory for <tag> (N days fresh)`. No silent context injection.

### Mid-session capture

Two skills for capturing rationale on the fly:

```
/clip <url>          # capture a URL or snippet for later reference
/snapshot            # save the full current transcript for later extraction
```

Inline `★ Insight` blocks Claude emits during work get auto-captured to your intake backlog at session end.

### Session end

When wrapping up:

```
/wrapup              # end-of-session ceremony (PROGRESS, CLAUDE.md, memory, commit, /extract)
```

or, for a tighter version that compresses everything into a single review:

```
/handoff             # express handoff with combined-go review
/handoff auto        # autonomous handoff (skip review gates)
```

Both finish with a paste-ready opener for your next session.

Before `/wrapup` or `/handoff`, consider:

```
/extract             # capture session insights / decisions / approaches / rules into the backlog
```

`/wrapup` and `/handoff` will prompt you to run `/extract` if you haven't.

---

## The Lifecycle

ARIA models knowledge as a five-phase loop:

```
capture → govern → promote → apply → refresh
```

| Phase | What happens | Primary skills |
|-------|-------------|----------------|
| **Capture** | Insights, decisions, URLs, snippets enter the intake backlog | `/clip`, `/snapshot`, `/extract`, inline `★ Insight` blocks |
| **Govern** | You review intake at audit cadence; decide what's load-bearing vs noise | `/audit-knowledge` |
| **Promote** | Approved items move from intake into the promoted knowledge tree (`approaches/`, `decisions/`, etc.) with tags | `/audit-knowledge` (auto-routes) |
| **Apply** | Promoted knowledge actively shapes the next decision via tag-based retrieval + Rule 22 enforcement | `/context`, `/rules`, `/codemap`, `/stitch`, `/distill`, `/prospect`, `/retrospect` |
| **Refresh** | Stale items get re-verified, archived, or removed | `/audit-knowledge` (staleness sub-mode), `/index` (drift detection) |

The point is the apply phase. Knowledge that gets captured but never retrieved is overhead, not memory.

---

## Best Practices by Session Phase

### Session start (first 30 seconds)

| Practice | Why |
|----------|-----|
| **Let SessionStart's reminders run** — don't dismiss them | They include audit-cadence prompts you don't want to miss |
| **Run `/context <project>` early** if you know what you're working on | Pulls relevant decisions + approaches before you start; cheaper than rediscovering them mid-task |
| **Check `/stats` if it's been > a week** | Surfaces stale audits, missing CODEMAPs, drift |

### During work

| Practice | Why |
|----------|-----|
| **Honor Rule 22 markers** | Bypassing them defeats the discipline; if you genuinely think a marker is unnecessary, that's a signal to assess impact, not to skip |
| **Use `/prospect` before multi-step plans** | Pre-mortem catches assumption errors before the first edit lands. Strongly recommended for plans touching >3 files or any unmeasured hypothesis |
| **`/clip` and `/snapshot` are cheap** | If a URL or session segment feels worth keeping, capture it. The audit pass triages later |
| **Keep commits atomic** | Per ARIA's commit discipline — one concern per commit makes `/retrospect` produce useful output later |

### Session end (last 2 minutes)

| Practice | Why |
|----------|-----|
| **Run `/extract` before closing** | Captures the session's insights/decisions into the intake backlog. Without this, the rationale evaporates |
| **Run `/wrapup` or `/handoff`** | Updates PROGRESS.md, CLAUDE.md, and memory; prompts you to commit; emits a next-session opener |
| **Don't leave uncommitted work without a reason** | Next session starts confused; if you must, leave a note in PROGRESS.md |
| **For shipped releases, run `/retrospect`** | Post-mortem produces the failure-mode patterns that prevent the same mistake twice |

### Audit cadences

ARIA prompts you at thresholds; don't ignore the prompts.

| Audit | Trigger | What to do |
|-------|---------|------------|
| **`/audit-knowledge`** | 20+ intake entries OR 7+ days since last | Review intake; accept / reject / defer items into the promoted tree |
| **`/audit-config`** | Every 14 days | Walk CLAUDE.md / settings / config drift; reconcile or document |
| **`/codemap update`** | When a feature ships or every ~14 days per project | Refresh the structural map; future sessions trust it as reference |
| **`/stitch verify`** | For multi-repo projects, every ~30 days | Cross-repo contracts drift slowly; verify backend ↔ frontend bindings are accurate |

### Decision discipline (Rule 22)

The change-decision framework. For non-trivial edits, declare:

1. **What changed** — which artifact, what concretely changes
2. **Why** — what problem this solves, what evidence supports the approach
3. **Solutions considered** — explicit alternatives ruled out
4. **Decision made** — the picked path
5. **How** — implementation specifics
6. **Verification** — how you'll confirm it worked
7. **Post-edit check** — scope held? unintended impact?

**High Impact** (auth, migrations, model changes, public-facing surfaces, critical paths): full 7-step framework.
**Low Impact** (docs, single-file refactor, formatting): lighter scope check.

Bypassing markers because "this is too simple" is the most common way bugs ship. The discipline is a cheap insurance policy.

---

## Retrieval Vocabulary (v2.16.0+)

Three layers of "make my files findable":

| Layer | What it is | When to use |
|-------|-----------|-------------|
| **Tags** | Exact-match controlled vocabulary in frontmatter `tags:` | Default. Your authoritative category labels. |
| **Semantic-hints** | Substring-matched free-form phrases in `semantic-hints:` | When the file is about a concept but you might search for it under several different names. Hyphenation is normalized; case-insensitive. |
| **Aliases** | User-edited map at `aliases.md` (e.g., `` `k8s` → `kubernetes` ``) | When you want a nickname to resolve to a canonical tag for everyone using your knowledge base |

Example file frontmatter:

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

With this file, all of these queries surface it:
- `/context api` (tag match)
- `/context cursor` (semantic-hint substring)
- `/context infinite-scroll` (semantic-hint substring with hyphen-normalize)

If you've declared `` `pg` → `pagination` `` in `aliases.md`:
- `/context pg` (alias resolution → `pagination` tag match)

---

## Common Patterns

### "What do we know about X?"

```
/context <tag>       # tag-based retrieval; loadable file list
/ask "...question..." # ad-hoc question answered from knowledge base
```

### "I'm about to ship a multi-step change"

```
/prospect <plan-file>          # pre-mortem before the first edit
# ... ship ...
/retrospect <commit-range>     # post-mortem after, ideally same session
```

### "I'm in a new project / sub-directory"

If you have `projects_list` configured and `active_knowledge_surfacing: true`:

```
cd <project-dir>     # auto-surfaces project knowledge + CODEMAP directory + STITCH (if multi-repo)
```

Manual fallback:

```
/context <project-tag>
```

### "I'm capturing rationale mid-session"

```
/clip <url-or-snippet>         # URL or fragment capture
/snapshot                      # full-session transcript preserve
```

Insights you mention inline (`★ Insight` blocks) get auto-captured to intake at session end.

### "It's been a while since I audited"

```
/audit-knowledge               # review intake backlog; promote/archive
/audit-config                  # check config + docs for drift
/codemap update                # refresh project structural map
/stitch verify <tag>           # verify multi-repo contracts
```

### "I'm wrapping up the session"

```
/extract                       # capture session insights
/wrapup                        # full end-of-session ceremony
# OR
/handoff                       # express handoff with combined-go review
```

### "I want to ask aria-knowledge a free-form question"

```
/ask "How do we typically structure pagination for cursor-based APIs?"
```

The `/ask` skill searches the knowledge base by tag + semantic-hints + aliases, then synthesizes an answer with citations.

---

## Codebase Mapping (per-project)

For projects you work in regularly, ARIA can build a structural map you can load instead of re-exploring every session.

```
/codemap create        # full-codebase scan; produces CODEMAP.md at project root
/codemap inventory     # quick index-only mode (no full generation)
/codemap update        # refresh after feature work
/codemap section <name>  # rebuild one section
```

CODEMAP.md is structured for **selective loading**:
- Directory section at top (20-40 lines): high-level feature map
- Feature sections below (50-200 lines each): load on demand via `Read CODEMAP.md offset=X limit=Y`

In v2.16.1+, when you `cd` into a configured project, ARIA auto-loads the directory section (~600-1200 tokens) and lets you pull specific feature sections as needed.

### Multi-repo projects

For workspaces with multiple sub-repos (e.g., backend + web + mobile):

```
/stitch create <project-tag>   # generates STITCH.md at workspace root
/stitch verify <project-tag>   # check cross-repo contracts haven't drifted
/stitch diff <project-tag>     # show differences since last verify
```

STITCH.md captures **cross-repo bindings**:
- Auth flow (which frontend module calls which backend endpoint)
- Endpoint matrix (BE namespace → FE consumer)
- Drift sources (per-repo CODEMAP sections that need to stay in sync)

In v2.16.1+, STITCH auto-loads (full file, ~4K tokens) alongside the umbrella CODEMAP when you activate a multi-repo project.

---

## Knowledge Base Hygiene

| Practice | Cadence | Skill |
|----------|---------|-------|
| Rebuild index | After adding/moving knowledge files | `/index` |
| Backlog triage | When prompted (20+ entries / 7+ days) | `/audit-knowledge` |
| Config drift | Every 14 days | `/audit-config` |
| Stale file detection | Implicit in `/audit-knowledge` and `/stats` | (automatic) |
| Archive don't delete | Always | (skill behavior) |

**Don't delete knowledge files.** ARIA archives instead of deletes. If you outgrow a decision, archive it with a pointer to its replacement. Future-you may need the context.

---

## When ARIA Adds Value (and When It Doesn't)

**Adds value when:**
- You work across multiple sessions on related problems
- You collaborate with future-you on similar codebases
- You ship non-trivial changes with multi-step plans
- You want decisions and rationales to compound, not evaporate
- You maintain >1 project and need to keep them organized

**Doesn't add value when:**
- You're doing one-off exploratory work with no future relevance
- You're new to a codebase and have nothing yet to capture (use ARIA after a few weeks)
- You're allergic to discipline (the markers + cadences are the point)

---

## What to Read Next

- [README.md](README.md) — full feature catalog, philosophy, model recommendations
- [CHANGELOG.md](CHANGELOG.md) — version history (v2.x evolution)
- Skill descriptions via `/help` — every installed skill with one-line summary
- [LICENSE](LICENSE) — CC BY-NC-SA 4.0 (non-commercial use; copyleft on derivatives)

---

## Troubleshooting

### "Hook error" labels on every tool call

Cosmetic Claude Code UI bug ([anthropic/claude-code#17088](https://github.com/anthropics/claude-code/issues/17088)). The hooks are working correctly; the label is misleading. Ignore.

### `/setup` says my config is missing fields

That's the v2.15.2+ self-audit catching drift. Run `/setup` again to add missing fields with defaults.

### `/context` returns nothing for tags I think exist

Run `/index` first — your `index.md` may be out of date. Then re-try `/context`. If still nothing, check spelling and your file's frontmatter `tags:` field.

### Active surfacing is too noisy

Set `active_knowledge_surfacing: false` in `~/.claude/aria-knowledge.local.md`. Hooks fall back to passive `/context` suggestions; skills skip auto-loading. You can re-enable any time.

### A skill I expect doesn't exist

Run `/help` to see what's installed at your version. If a skill from a release note isn't there, check `plugin.json` — your installed version may be older than the release note's target version. Update via `/plugin install aria-knowledge@latest` and re-run `/setup`.

---

**The shortest summary of ARIA:** capture once, retrieve forever, decide with discipline. The five-phase lifecycle is the loop; Rule 22 is the discipline; tags + hints + aliases are the retrieval surface; CODEMAP + STITCH are the structural memory; `/prospect` + `/retrospect` are the review cycle. Everything else is plumbing in service of those.
