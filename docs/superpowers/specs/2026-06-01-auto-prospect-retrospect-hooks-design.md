# Auto-Prospect & Auto-Retrospect Hooks — Design

- **Date:** 2026-06-01
- **Status:** Design (approved in brainstorming; **/prospect run 2026-06-01 → PROCEED-WITH-CHANGES**, see Prospect Findings below; pending implementation plan)
- **Target version:** v2.22.2 (patch bump from v2.22.1)
- **Scope:** plugin-claude-code only (Code-first, like `session_state` v2.22.0 and subagent capture v2.21.0)

## Context

ARIA already ships two reflective skills:

- `/prospect` — a forward-looking pre-mortem on a plan/approach **before** execution.
- `/retrospect` — a backward-looking review of shipped work (commit/range/PR/release/deployment).

Both are invoked manually today. On 2026-06-01 the maintainer hand-built a *personal* `PostToolUse:Write` hook (in `~/Projects/.claude/`, absolute paths) that auto-runs `/prospect file <path>` inline whenever a superpowers plan file is written. This spec generalizes that idea into a **distributable plugin feature** and adds a symmetric **auto-retrospect** counterpart.

The personal hook cannot ship as-is: it uses an absolute `/Users/...` path and lives in local settings. The plugin's hook convention is `bash ${CLAUDE_PLUGIN_ROOT}/bin/<name>.sh` registered in `.claude-plugin/plugin.json`, with config read from `~/.claude/aria-knowledge.local.md` via `bin/config.sh`.

### The trigger asymmetry (central design fact)

Auto-prospect has a clean, single trigger — a plan file is **written** (one `PostToolUse:Write` event with a structured `file_path`). Auto-retrospect has no equivalent: "I just shipped" is not one tool event. We choose **`git push`** as the local "work shipped" signal — the symmetric counterpart to prospect's plan-write trigger.

## Goals

- Ship auto-prospect and auto-retrospect as opt-in, per-skill-configurable plugin hooks.
- Match the plugin's existing hook conventions (`${CLAUDE_PLUGIN_ROOT}`, `config.sh`, one-script-per-concern).
- Default-off; surfaced in `/setup`; safe for arbitrary users (no surprise token-heavy auto-runs).
- Recursion-safe and low-noise by construction.

## Non-Goals

- Porting to Codex / Cursor / Antigravity in v1 (tracked drift; push-stdout parsing per-runtime unverified). Cowork is skills-only (no hooks API) → permanently N/A.
- Deploy/PR-merge triggers for retrospect (push is the chosen signal; other triggers are future work).
- Changing the `/prospect` or `/retrospect` skills themselves — these hooks only *invoke* them.

## Behavior model — per-skill configurable

Each skill independently chooses `off | nudge | run`:

- `off` — hook is a silent no-op.
- `nudge` — hook injects a suggestion ("Plan written — want me to /prospect it?") and the user decides.
- `run` — hook instructs Claude to run the skill inline immediately (the maintainer's personal behavior).

Both skills are interactive (their Evidence-Sourcing Pass asks the user targeted questions) and token-heavy (~30–70k), so `nudge` is the safe shared default; `off` is the actual ship default.

## Config keys (in `bin/config.sh` + `/setup` + `aria-knowledge.local.md`)

| Key | Default | Values | Purpose |
|-----|---------|--------|---------|
| `auto_prospect` | `off` | `off` \| `nudge` \| `run` | Behavior when a plan file is written |
| `auto_retrospect` | `off` | `off` \| `nudge` \| `run` | Behavior when work is pushed |
| `retrospect_min_commits` | `3` | integer | Skip pushes below this commit count |
| `retrospect_branches` | `main,master,production` | comma-list | Only fire on these branches (empty = any branch) |

Parsing follows the existing `config.sh` pattern (YAML frontmatter `grep`/`sed`, `${VAR:-default}` defaults, space-stripping for comma-list membership tests).

## Component 1 — Auto-prospect hook

- **Script:** `bin/post-plan-prospect-check.sh`
- **Registration:** a *new* `PostToolUse` entry, `matcher: "Write"`, alongside the existing `Edit|Write → post-edit-check.sh`. Both fire on a Write; both inject independently.
- **Flow:**
  1. Read `file_path` from tool input (same `grep -o '"file_path":"[^"]*"'` extraction as `post-edit-check.sh`).
  2. Source `config.sh`. If `auto_prospect=off` → silent `exit 0`.
  3. Match `file_path` against plan-path globs. No match → silent `exit 0`.
  4. Match → emit `hookSpecificOutput.additionalContext`:
     - `nudge`: instruct Claude to **offer** `/prospect file <path>` before execution and ask the user.
     - `run`: instruct Claude to **run** `/prospect file <path>` inline now.
- **Plan-path globs (default):** `*/docs/specs/*.md`, `*/docs/plans/*.md`, `*/docs/superpowers/plans/*.md` — unions the plugin's own convention with the superpowers path the personal hook used.
- **Debounce:** the `Write`-only matcher means a plan *written* via Write fires once; later *edits* via the Edit tool do not re-trigger. No flag needed.

## Component 2 — Auto-retrospect hook

- **Script:** `bin/post-push-retrospect-check.sh`
- **Registration:** a *new* `PostToolUse` entry, `matcher: "Bash"`, alongside the existing `Bash → bash-cd-check.sh`.
- **Flow:**
  1. Source `config.sh`. If `auto_retrospect=off` → silent `exit 0`.
  2. Read the Bash `command`. If not a `git push` invocation → silent `exit 0`.
  3. **Force-push skip:** command carries `--force` / `-f` / `--force-with-lease` → silent skip.
  4. **Parse the pushed range from `tool_response.stderr`** (verified 2026-06-01: `git push` writes its summary to **stderr**, not stdout; Claude Code's `PostToolUse` payload exposes `tool_response.{stdout,stderr,exit_code}` as separate fields). Git prints `  <old>..<new>  <branch> -> <branch>`. Extract `<old>..<new>` and the target branch using `grep`/`sed` (the repo deliberately avoids a `jq` dependency).
     - `Everything up-to-date` / no range line → **no-op skip**.
     - `* [new branch]` (no prior remote ref) → **range-less nudge fallback** (no precise `<old>` exists).
  5. **Branch filter:** `retrospect_branches` non-empty and target branch not in list → silent skip.
  6. **Commit threshold:** `git rev-list --count <old>..<new>` < `retrospect_min_commits` → silent skip.
  7. All gates pass → emit `additionalContext`: **offer** (nudge) or **run inline** (run) `/retrospect range <old>..<new>`.

### Parsing discipline (load-bearing risk)

Unlike the prospect trigger (structured `file_path`), this hook parses human-formatted git stderr, which varies by git version, push type, and locale. **Rule: anything we cannot confidently parse → skip silently rather than fire a wrong range.** A missed retrospect is invisible; a retrospect on a garbage range is a visible, annoying failure. The cost is asymmetric → bias toward skipping. Test fixtures (Component-by-Component below) must cover fast-forward, new-branch, `Everything up-to-date`, and force-push stderr shapes before `auto_retrospect` is enabled in any real config.

## Recursion safety

When `/prospect` or `/retrospect` runs, it writes its report to `~/knowledge/logs/{prospect,retrospect}/` — which matches no plan-path glob and is not a `git push`. Neither hook can re-trigger itself. The path/event filters *are* the guard; no debounce flag required.

## /setup, ports, version, docs

- **`/setup`:** add the 4 keys to the setup config flow (two `off|nudge|run` pickers + threshold + branch list), with the defaults above.
- **Ports:** plugin-claude-code only for v1. Codex/Cursor/Antigravity = tracked drift (push-stdout parsing per-runtime unverified). Cowork = N/A (no hooks API).
- **Version:** patch bump `plugin.json` 2.22.1 → **2.22.2**.
- **Docs:** CHANGELOG entry; `CONFIG.md` + README hook-table additions; CLAUDE.md "Last reviewed" refresh.

## Testing

Follow the existing `tests/` harness (feed sample hook-input JSON to each script; assert the `additionalContext` payload or silent no-op):

- **Prospect:** each plan-glob match × `off`/`nudge`/`run`; non-plan path → silent.
- **Retrospect:** clean fast-forward range parse; force-push skip; `Everything up-to-date` no-op skip; new-branch range-less fallback; below-threshold skip; off-branch skip; `nudge` vs `run` output shape.

## Prospect Findings (2026-06-01)

`/prospect file` run — verdict **PROCEED-WITH-CHANGES**. Log: `~/knowledge/logs/prospect/2026-06-01-file-auto-prospect-retrospect-hooks.md`. 7/8 steps pre-validated; evidence pass made 2 upgrades + 1 falsification.

- **Falsified & fixed (applied above):** range is parsed from `tool_response.stderr`, not stdout. Mechanism confirmed via claude-code-guide (docs-cited): `PostToolUse` delivers `tool_response.{stdout,stderr,exit_code}` separately, and `pre-edit-check.sh` already reads `tool_response` in-repo. Multi-entry `PostToolUse` coexistence (matcher `Edit|Write` + `Write`) also confirmed: both fire, both inject.
- **Open decision A — retrospect default framing:** the personal-hook "inline bloat is free" rationale does **not** transplant to retrospect. Prospect fires before a *fresh* execution session (bloat disposable); retrospect fires *after a push*, when the user keeps working in the same session (bloat NOT disposable). Recommendation: `/setup` frames `nudge` as the sensible retrospect default and `run` as the cost-aware choice. Both values still supported. *(Novel pattern banked: `asymmetric-cost-rationale-transplant`.)*
- **Open decision B — prospect plan-path globs:** consider dropping `*/docs/specs/*.md` from the defaults. A spec is a pre-plan design; `/prospect` targets a plan about to execute. Keeping specs risks double-prospecting (once at spec, once at the following plan). Recommended default globs: `*/docs/plans/*.md` + `*/docs/superpowers/plans/*.md` only.

Decisions A and B are implementation-phase calls (not spec-blocking); resolve them when writing the plan.

## Open questions

None blocking. Candidate future work: deploy/PR-merge retrospect triggers; per-port rollout once stderr range-parsing is verified on each runtime.
