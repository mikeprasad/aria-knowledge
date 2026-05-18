# ARIA Quickstart (Cursor port)

Get ARIA running in Cursor in 5 minutes. Then learn the rhythm that makes it valuable.

> **Already installed?** Jump to [Best Practices](#best-practices-by-session-phase) or [Common Patterns](#common-patterns).
>
> **Looking for the Claude Code version?** This file mirrors the upstream `QUICKSTART.md` (https://github.com/mikeprasad/aria-knowledge) with Cursor-specific wiring. Knowledge folder formats and rule content are identical to upstream.

## 5-Minute Setup

### 1. Drop the port into your repo

Copy the four port surfaces to your repo root:

```
AGENTS.md
.cursor/
  hooks.json
  aria-knowledge.local.md
  rules/
    aria-core.mdc
    aria-rule-22.mdc
    aria-context.mdc
    aria-audit.mdc
    aria-commands.mdc
scripts/aria/
  *.sh
  VERSION
knowledge/   (the template — see step 2 if it isn't there yet)
```

Make sure scripts are executable:

```bash
chmod +x scripts/aria/*.sh
```

### 2. Point `.cursor/aria-knowledge.local.md` at your knowledge folder

Open `.cursor/aria-knowledge.local.md` and set `knowledge_folder:` to an absolute path. If you don't have one yet, ARIA's `knowledge/` template at the repo root works — set it to that absolute path. For team setups, point it at a folder you commit to a separate private repo.

### 3. Ask the agent to run `/setup`

```
/setup
```

The wizard walks you through:

- **Knowledge folder location** — confirms (and creates if missing) the folder structure (`approaches/`, `decisions/`, `rules/`, `references/`, `intake/`).
- **Audit cadences** — when to prompt you for `/audit-knowledge` and `/audit-config` (defaults are sensible).
- **Advanced options** — toggle features like `active_knowledge_surfacing` (recommended: keep `true`).
- **Project setup (optional)** — per-project knowledge tiers + proactive CODEMAP/STITCH surfacing via `projects_list`.

### 4. Build the initial index

```
/index
```

Scans your knowledge folder, builds `index.md` with the tag index, and flags any untagged files. Re-run whenever you add or move knowledge files.

### 5. Confirm it's wired

```
/stats
```

Shows your knowledge base health: file counts, intake backlog status, audit dates, codemap status, index health. If `/stats` works, ARIA is configured.

Edit any file in the repo — you should see a `[Rule 22]` reminder in the agent's response (the `beforeFileEdit` hook firing). Check `/tmp/aria-hook-debug.log` to confirm hooks are firing.

**You're ready.** The rest of this doc explains how to use it well.

---

## What's different from the Claude Code version

| Capability | Claude Code | Cursor port |
|---|---|---|
| Hook events | `SessionStart`, `PreToolUse`, `PostToolUse`, `PreCompact`, `PostCompact`, `TaskCreated` | `sessionStart`, `beforeFileEdit`, `afterFileEdit`, `beforeShellExecution`, `beforeReadFile`, `stop` |
| Rule 22 enforcement | Transcript-scoped scan in `pre-edit-check.sh` (structural deny) | Edit-intent marker (`record-edit-intent.sh`) + `beforeFileEdit` advisory + AGENTS.md/.cursor/rules instructions |
| Task-boundary capture | `PreCompact` transcript snapshot | `stop` hook → `capture-task-boundary.sh` writes git + config + hook state under `intake/task-boundary-captures/` |
| Slash commands | Native Claude Code skill runtime | Natural-language triggers documented in `.cursor/rules/*.mdc` (slash names recognized; trigger phrases work too) |
| Plugin packaging | `.claude-plugin/plugin.json` | `.cursor/hooks.json` + `.cursor/rules/*.mdc` (Cursor IDE conventions) |
| Config path | `~/.claude/aria-knowledge.local.md` | `.cursor/aria-knowledge.local.md` (per-repo) |
| Knowledge folder format | Same | **Same** — schemas, frontmatter, tag index, backlogs, logs all compatible with upstream |

**Knowledge folder is fully cross-compatible.** You can point a Cursor repo and a Claude Code repo at the same knowledge folder; both will read and write the same files in the same formats.

---

## Your First Session — A Walkthrough

### Before you start

When Cursor opens the repo, the `sessionStart` hook runs and surfaces context-setting reminders (audit-due prompts, last-setup-version checks). Note them; you don't need to act immediately.

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

1. **Rule 22 markers**: before any non-trivial edit, the agent should emit a `[Rule 22]` block declaring impact + the change being made, and run:

    ```bash
    bash scripts/aria/record-edit-intent.sh <filePath> rule22-low|rule22-high "<one-line rationale>"
    ```

    The `beforeFileEdit` hook checks for a recent matching marker. Missing/stale/mismatched markers raise an escalated advisory (especially loud for protected files like `AGENTS.md`, `working-rules.md`, `change-decision-framework.md`, and any file under `critical_paths`). Cursor's hooks plan does not document a stable agent-side deny for `beforeFileEdit`, so this stays advisory; the discipline is instruction-based.

2. **Active surfacing**: when you `cd` into a configured project directory, ARIA proactively surfaces relevant knowledge files + the project's CODEMAP/STITCH artifacts via the `beforeShellExecution` hook (`bash-cd-check.sh`).

### Mid-session capture

```
/clip <url>          # capture a URL or snippet for later reference
/snapshot            # write a task-boundary capture (git + hook + config state) under intake/task-boundary-captures/
```

Inline `★ Insight` blocks the agent emits during work get auto-captured to your intake backlog at session end via `/extract`.

### Session end

```
/wrapup              # end-of-session ceremony (PROGRESS, AGENTS.md, memory, commit, /extract)
```

or a tighter version:

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
| Let `sessionStart` reminders run — don't dismiss them | They include audit-cadence prompts you don't want to miss |
| Run `/context <project>` early if you know what you're working on | Pulls relevant decisions + approaches before you start |
| Check `/stats` if it's been > a week | Surfaces stale audits, missing CODEMAPs, drift |

### During work

| Practice | Why |
|----------|-----|
| Honor Rule 22 markers — and run `record-edit-intent.sh` before Edit/Write | Cursor can't structurally enforce, so the marker is your discipline. Bypassing defeats the audit trail |
| Use `/prospect` before multi-step plans | Pre-mortem catches assumption errors before the first edit lands |
| `/clip` and `/snapshot` are cheap | If something feels worth keeping, capture it. Audit triages later |
| Keep commits atomic | Per ARIA's commit discipline — one concern per commit makes `/retrospect` output useful |

### Session end (last 2 minutes)

| Practice | Why |
|----------|-----|
| Run `/extract` before closing | Captures the session's insights/decisions into the intake backlog |
| Run `/wrapup` or `/handoff` | Updates PROGRESS / AGENTS.md / commit prompt + next-session opener |
| Don't leave uncommitted work without a reason | Next session starts confused |
| For shipped releases, run `/retrospect` | Post-mortem produces failure-mode patterns that prevent the same mistake twice |

### Audit cadences

ARIA prompts at thresholds; don't ignore them.

| Audit | Trigger | What to do |
|-------|---------|------------|
| `/audit-knowledge` | 20+ intake entries OR 7+ days since last | Review intake; accept / reject / defer into the promoted tree |
| `/audit-config` | Every 14 days | Walk AGENTS.md / settings / config drift; reconcile or document |
| `/codemap update` | When a feature ships or every ~14 days per project | Refresh the structural map |
| `/stitch verify` | For multi-repo projects, every ~30 days | Cross-repo contracts drift slowly; verify backend ↔ frontend bindings |

### Decision discipline (Rule 22)

For non-trivial edits, declare:

1. **What changed** — which artifact, what concretely changes
2. **Why** — what problem this solves
3. **Solutions considered** — explicit alternatives ruled out
4. **Decision made** — the picked path
5. **How** — implementation specifics
6. **Verification** — how you'll confirm it worked
7. **Post-edit check** — scope held? unintended impact?

**High Impact** (auth, migrations, model changes, public-facing surfaces, `critical_paths`): full 7-step framework.
**Low Impact** (docs, single-file refactor, formatting): lighter scope check.

Then run:

```bash
bash scripts/aria/record-edit-intent.sh <filePath> rule22-low|rule22-high "<rationale>"
```

The `beforeFileEdit` hook reads this marker to verify you assessed before the edit. The marker is consumed (deleted) by `afterFileEdit` on a matching successful edit, so each edit needs its own fresh marker.

---

## Common Patterns

### "I just discovered a useful approach mid-session"

Drop an inline `★ Insight` block in your reply, or run `/clip` with a snippet. At session end, `/extract` will collect it into `knowledge/intake/insights-backlog.md`. The next `/audit-knowledge` lets you promote it.

### "Switching projects mid-session"

`cd` into the new project's directory. The `beforeShellExecution` hook fires and surfaces relevant knowledge for the destination directory.

### "Just want to know what ARIA can do right now"

```
/help
```

### "Working in Cursor Cloud agents"

`sessionStart` and `stop` hooks only fire in the local Cursor IDE, not in Cloud agents. For Cloud agents, the `.cursor/rules/*.mdc` files (loaded as persistent instructions) carry the workflow; the hook scripts are a no-op. Knowledge-folder reads/writes via `/context`, `/extract`, etc. still work — they're just driven by instructions instead of hooks.

---

## Cursor-port-specific notes

- **Hook events** are defined in `.cursor/hooks.json`. Cursor resolves `command` paths relative to the hooks.json file location (`.cursor/`); the port uses paths relative to the repo root, which Cursor resolves correctly when scripts are at `scripts/aria/*.sh`.
- **Path validation**: at session start, the hook reads `.cursor/aria-knowledge.local.md`. If `knowledge_folder` is not an absolute path or the folder doesn't exist, you'll see a prompt to run `/setup`.
- **Permissions**: scripts run with the user's permissions. The port avoids destructive operations; the only writes are under the configured `knowledge_folder` and to `/tmp/aria-hook-debug.log`.
- **Fail-open**: every hook script is fail-open. A bug in a hook will never block an edit, shell command, or read.
- **Compaction**: there is no compaction lifecycle in Cursor. The port's `stop` hook + `capture-task-boundary.sh` substitute writes a non-transcript snapshot at task end.
