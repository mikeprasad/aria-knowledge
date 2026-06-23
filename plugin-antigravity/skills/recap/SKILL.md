---
description: "Read-only orientation — render a scannable table of what just happened so you can situate yourself. Modes: '/recap' (this session), '/recap arc' (the last product arc), '/recap commit' (the last commit), '/recap push' (the last push's commits — what I sent up), '/recap pull' (the last pull's changes — what came down to me). Use when user says '/recap', 'catch me up', 'what just happened', 'where am I', 'recap the session', 'recap the last commit/push/pull'. Plain summary only — never validates or judges (that's /retrospect); never writes to disk. (Code port — ADR-094.)"
---

# /recap — Read-Only Orientation

Render a compact `What / Where / Status` table of recent work to situate the user at a glance. **Read-only**: no disk writes, no logs, no verdicts. The orient-side counterpart to `/handoff` (which packages state for the *next* reader) — recap re-orients the *current* reader. Distinct from `/retrospect`, which validates with per-fix verdicts; `/recap` only summarizes, and may *offer* to escalate to `/retrospect` but never runs verdict work itself.

## Step 0: Resolve Mode

Parse the first argument (case-insensitive):
- `arc` → arc mode
- `commit` (optionally followed by a `<hash>`) → commit mode
- `push` → push mode
- `pull` → pull mode
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
- Git modes populate rows from commit subjects + changed paths; session/arc from the conversation/PROGRESS synthesis.
- Cap at ~8–12 rows; if more, add a final `| +N more … | | |` summary row.
- **Close with an optional offer** (never auto-run): "Want a `/retrospect` on this for validation?"

## Rules

- **Read-only — never write.** No logs, no files, no SESSION.md, nothing. `allowed-tools` excludes `Write`/`Edit` by design; honor it.
- **Orient, don't judge.** No verdicts, no validation, no per-fix scrutiny — that's `/retrospect`. Recap states what happened; it may offer to escalate.
- **Be honest about inference.** `pull` prints its resolved range; `arc` states its inferred boundary. Never present a guessed scope as certain.
- **Glance, not essay.** Keep the table scannable; summarize the tail rather than listing 40 commits.
- **Not `/handoff`.** Recap orients the current reader; it does not package state for a next session or write any artifact.
