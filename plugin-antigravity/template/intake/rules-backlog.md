# Rules Backlog

Rule candidates captured during Claude Code sessions — observations and proposals about *how to work* (rather than *what is*). Reviewed during the knowledge audit and either promoted to user memory (`feedback_*.md` for personal/working-style rules) or to a project-local `working-rules.md` (for project-scoped discipline), or cleared.

## Format

Each entry includes the date, project(s), the rule statement, and (when known) **Why:** and **How to apply:** lines. Rules entered here typically come from one of three sources:

1. The `Accept → rule` path during an `intake/ideas/` audit (an idea reclassifies as a "how to work" rule)
2. Direct extraction during `/extract` when conversation surfaces a repeating discipline worth codifying
3. Manual append when you notice a pattern in your own corrections to the assistant

## Promotion targets

All targets stay inside the user memory directory or this knowledge folder — ARIA never modifies project source.

- **User memory** — write `feedback_*.md` under the active project's `~/.gemini/antigravity/transcripts/{cwd-encoded}/memory/` directory and add a one-line entry to its local `MEMORY.md`. Use this when the rule is personal/working-style and applies across projects (mirrors how feedback memories already get written manually).
- **Cross-project ARIA rule** — append to `rules/user-rules.md` (the user-owned rules file at the knowledge folder root, plugin-managed `working-rules.md`'s counterpart). Use this when the rule shapes ARIA's behavior consistently across all your work.
- **Project-tier working rule** (projects tier only) — append to `projects/{tag}/rules/working-rules.md`. Use this when the rule is scoped to one project's codebase or workflow. Setup's Step 7c scaffolds the `rules/` subdirectory under each configured project, so the destination is always available when projects tier is on.

---

(No pending rules)
