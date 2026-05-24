# Decisions

Cross-project architectural decisions using ADR (Architecture Decision Record) format. Each decision captures context, the choice made, alternatives considered, and consequences.

**File naming:** `YYYY-NNN-` prefix + kebab-case (e.g., `2026-001-auth-strategy.md`, `2026-002-database-choice.md`). Self-dating, resets per year. Track `NNN` sequentially within a year — the next new ADR in 2026 is `2026-003`.

**Scope:** These are *cross-project* ADRs — decisions that apply across multiple projects. Project-specific ADRs that don't (yet) apply across projects belong in `projects/{project-tag}/decisions/` (opt-in via `/setup`), which use separate per-project sequential numbering (`001-`, `002-`, ...).

**Format template:** See LOCAL.md
