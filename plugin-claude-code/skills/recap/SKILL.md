---
description: "Read-only orientation — render a scannable table of what just happened so you can situate yourself. Modes: '/recap' (this session), '/recap arc' (the last product arc), '/recap commit' (the last commit), '/recap push' (the last push's commits — what I sent up), '/recap pull' (the last pull's changes — what came down to me), '/recap project' (current project's state), '/recap project <name>' (a named project from projects_list), '/recap project all' (roster glance across all projects). Use when user says '/recap', 'catch me up', 'what just happened', 'where am I', 'recap the session', 'recap the last commit/push/pull', 'where does this project stand', 'recap all my projects', 'where do my projects stand'. Plain summary only — never validates or judges (that's /retrospect); never writes to disk. (Code port — ADR-094.)"
argument-hint: "[arc|commit|push|pull|project [name|all]]"
allowed-tools: Read, Glob, Grep, Bash
---

# /recap — Read-Only Orientation

Render a compact `What / Where / Status` table of recent work to situate the user at a glance. **Read-only**: no disk writes, no logs, no verdicts. The orient-side counterpart to `/handoff` (which packages state for the *next* reader) — recap re-orients the *current* reader. Distinct from `/retrospect`, which validates with per-fix verdicts; `/recap` only summarizes, and may *offer* to escalate to `/retrospect` but never runs verdict work itself.

## Runtime Gate (per ADR-094)

**Canonical resolution:** This is the Claude Code variant. When both `plugin-claude-code` and `plugin-claude-cowork` are loaded in the same session, bare `/recap` resolves to this skill — aria-knowledge (Code) is the canonical owner per ADR-094 §Part 1.

**Before Step 0:** Check that the `Bash` tool is available. If `Bash` is NOT available (non-Code runtime), surface:

> ⚠️ **Runtime mismatch — you invoked `/recap` from a non-Code runtime.**
>
> The `commit`/`push`/`pull` modes run `git` via Bash, unavailable here. `/recap` is currently a Claude-Code-only skill — no cowork variant exists yet.
>
> **Proceed with session/arc modes only (no git)?** (`y` / `n`)

On `y`: run only default/arc modes. On `n`/other: exit cleanly. (This gate is lighter than the dual-port redirect since there is no cowork `/recap` to hand off to.)

If `Bash` is available, proceed to Step 0.

## Step 0: Resolve Mode

Parse the first argument (case-insensitive):
- `arc` → arc mode
- `commit` (optionally followed by a `<hash>`) → commit mode
- `push` → push mode
- `pull` → pull mode
- `project` → **project mode** — consume a *second* argument as the breadth selector:
  - no second arg → **project-nearest** (the current session's main project)
  - `all` → **project-roster** (every project in `projects_list`)
  - any other token `<name>` → **project-named** (the `<name>:` tag in `projects_list`)
- anything else / no arg → **session mode** (default)

## Mode Resolution

### Session mode (default)
Synthesize what happened in THIS conversation — files created/modified, decisions made, current state — **from conversation context, not git** (same source as `/handoff` Step 2). Headline frame: "this session · {N} changes".

### Arc mode (`arc`)
Read the project's `PROGRESS.md` (nearest one from cwd). The arc boundary = the most recent dated/`## ` arc heading; everything from that heading forward (plus this session's work) is "the arc". **State the inferred boundary in the headline** (e.g. "arc since PROGRESS 2026-06-21 entry") so the user sees what was treated as the arc. If no PROGRESS.md, fall back to session mode and say so.

### Commit mode (`commit [<hash>]`)
`git show <hash|HEAD> --stat` for the subject + changed files. Headline: "commit {short-sha} · {subject} · {N} files".

### Push mode (`push`)
`git log @{push}..HEAD --stat` (commits *I* sent up). If no upstream is configured, fall back to `git log -10` and say so. Headline: "last push · {N} commits · {M} files".

### Pull mode (`pull`)
Commits that *came down to me* on the last pull. Resolve the range:
1. Try `git log ORIG_HEAD..HEAD --stat` (git sets `ORIG_HEAD` before a pull/merge).
2. If `ORIG_HEAD` is unset OR the range is empty (it was overwritten by an intervening merge/rebase/reset), scan `git reflog` for the most recent `pull`/`merge` entry and use that entry's pre-state as the range start.
3. **Always print the resolved range** (e.g. "last pull · ORIG_HEAD..HEAD · 5 commits from origin/main") so the user can verify what "last pull" meant.

**push vs pull:** `push` = what *I* sent up (`@{push}..HEAD`, my commits); `pull` = what *came down to me* (`ORIG_HEAD..HEAD`, others' commits I merged). Opposite directions.

### Project mode (`project [<name>|all]`)

Where the modes above orient you *temporally* (this session, this repo's git), `project` mode orients you *laterally* — the current state of one project, or of the whole portfolio. A terminal-table analogue of the aria-atlas dashboard. The second argument selects breadth (resolved in Step 0).

**Roster resolution (named + roster sub-modes).** Read `~/.claude/aria-knowledge.local.md` and parse the `projects_list:` frontmatter key — comma-separated `tag:path` entries; expand a leading `~` in any path. This is the same roster `/aria-assist` reads; **be read-only on `projects_list` — never write it.** If `projects_list` is empty/absent:
- **project-roster** → hard stop: "Roster unconfigured — run `/setup` to populate `projects_list`." Do not guess a roster.
- **project-named** → fall back to treating `<name>` as a literal filesystem path if it exists; else the same unconfigured message.

**Resolve the project path per breadth:**
- **project-nearest** (no second arg) → walk up from cwd to the nearest `CLAUDE.md`/`PROGRESS.md` (the same Step-1 resolver the other aria-knowledge skills use). No `projects_list` needed.
- **project-named** (`<name>`) → the typed `<name>` IS the `projects_list` tag (`/recap project cs` → the `cs:` entry). Unknown tag → list the available tags and stop (no fuzzy matching).
- **project-roster** (`all`) → iterate every `tag:path` entry.

**Per-project read (tolerant — a missing/malformed file degrades to a blank/omitted row, never throws):**
- **`SESSION.md`** (nearest, then sub-project roots if present): `lastEvent` (`in-progress`/`wrapup`/`handoff`) → *current state*; the embedded next-session prompt → an *in-flight* fragment.
- **`PROGRESS.md`** (nearest): the most recent dated/`## ` arc heading + its open (TODO / in-progress) items.
- **Git — only if the directory is a git repo AND Bash is available:** `git -C <path> log -1 --stat` (last commit) + `git -C <path> status --short` (dirty tree). **If not a git repo → silently omit the commit and working-tree rows** (per-project version of the Runtime-Gate Bash check).

**Output — single project (nearest / named).** Full orientation, keeping the standard `What / Where / Status` table. Each substantive item carries an indented `↳` **context sub-row** with a short sentence (so "T0 completed" reads with what T0 *was*). Repo rows are absent entirely when the project is not a git repo. Headline: `project <tag-or-path> · <lastEvent or '—'> · last touched <date>`. **Always print the resolved project path** so the user can verify which project was read.

```
Recap — project cs · handoff · last touched 2026-06-25

| What | Where | Status |
|------|-------|--------|
| Current state: handoff — next-session opener embedded | SESSION.md | ready |
| Latest arc: native Space comment-replies | PROGRESS.md 2026-06-24 | in-progress |
|   ↳ Space comment-replies: threaded replies under Space posts, native SwiftUI | | |
| Last commit: feat: tap-through routing for Space notifs | a1b2c3d | done |
|   ↳ routed notification taps to the correct Space/post detail view | | |
| Working tree: 2 files modified, uncommitted | git status | open |
| Open: RenderPreview gate for comment-reply cell | PROGRESS open items | open |
```

**Output — all projects (roster).** Terse rows + one short in-flight fragment, **recency-sorted** (most-recent `SESSION.md`/`PROGRESS.md` mtime first). Cap visible rows (~8–12); summarize the tail as a `+N more (older)` row. Headline shows the total count only (recency-sort, no activity-tier thresholds).

```
Recap — all projects · 18 total

| Project | State   | In flight                    | Touched |
|---------|---------|------------------------------|---------|
| cs      | handoff | native Space comment-replies | 06-25   |
| aria    | in-prog | recap project mode           | 06-25   |
| df      | wrapup  | df-editor row affordance     | 06-24   |
| …       | …       | …                            | …       |
| +12 more (older)        |         |                              |         |
```

- `State` = SESSION.md `lastEvent`, or `—` if no SESSION.md. `In flight` = a ~6-word fragment from the next-session prompt or the latest PROGRESS heading (blank if neither). `Touched` = most-recent mtime of SESSION.md / PROGRESS.md (MM-DD).
- **Escalation offer** (never auto-run): single-project → "Want a `/retrospect` on this for validation?"; roster → "Want a `/aria-assist` PM review across these?"

## Output — one consistent shape (all modes)

Emit a headline frame line, then the table:

```
Recap — {headline frame}

| What | Where | Status |
|------|-------|--------|
| {high-level item} | {file / area / skill} | {done / in-progress / open} |
| … | … | … |
```

- `What` = the change/action at a high level. `Where` = the file/area/skill touched. `Status` = done / in-progress / open.
- **Self-descriptive or annotate (all modes).** If a `What` cell isn't understandable on its own — a bare artifact name (`group G`, `T0`, a flag/config key, a ticket ID) — append a short detail clause (≤~8 words) so the row reads without prior context: `group G — 9 recap-mode contract assertions`, not `group G`; `T0 — auth-token refactor`, not `T0`. A cell that already reads plainly (`Bump version to 2.37.1`) needs no addition. This sharpens "Glance, not essay" rather than fighting it: every row must be understandable at a glance, which a bare token isn't. (Single-project mode does this via the `↳` context sub-row; terse roster rows use the inline `— detail` form to stay one line.)
- Git modes populate rows from commit subjects + changed paths; session/arc from the conversation/PROGRESS synthesis.
- Cap at ~8–12 rows; if more, add a final `| +N more … | | |` summary row.
- **Close with an optional offer** (never auto-run): "Want a `/retrospect` on this for validation?"

## Rules

- **Read-only — never write.** No logs, no files, no SESSION.md, nothing. `allowed-tools` excludes `Write`/`Edit` by design; honor it.
- **Orient, don't judge.** No verdicts, no validation, no per-fix scrutiny — that's `/retrospect`. Recap states what happened; it may offer to escalate.
- **Be honest about inference.** `pull` prints its resolved range; `arc` states its inferred boundary; `project` prints the resolved project path (single) or the roster total (all). Never present a guessed scope as certain.
- **Glance, not essay.** Keep the table scannable; summarize the tail rather than listing 40 commits.
- **Not `/handoff`.** Recap orients the current reader; it does not package state for a next session or write any artifact.
