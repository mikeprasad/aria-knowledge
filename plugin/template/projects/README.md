---
Last updated: 2026-04-15
tags: [knowledge-structure]
---

<!-- plugin-managed: /setup diffs this file on plugin updates (only when the project tier is enabled). Per-project READMEs under `projects/{tag}/` are user-owned and never diffed. Customize this overview doc freely — your edits appear as diff prompts on future `/setup` runs. See OVERVIEW.md "Plugin-Managed vs User-Owned Files" for details. -->


# Project-Specific Knowledge

Durable architecture decisions, patterns, and insights that are valuable to preserve but **specific to one project** — not yet validated across multiple projects. Sits between ephemeral memory files (status tracking) and cross-project knowledge in the top-level folders (`approaches/`, `decisions/`, `rules/`).

> **This file is shipped by ARIA.** It explains the structure of `projects/` and is updated when the plugin updates. Project subdirectories below (e.g., `projects/your-project/`) are user-owned — your customizations are never overwritten by `/setup` updates.

## When to use

- A decision or pattern is architecturally important for one project, but there's no evidence it applies to others
- Knowledge you'd want to load when starting a session in that project, but not when working on unrelated projects
- Historical "why did we build it this way" context that survives context compaction

## Structure

Each configured project gets its own subdirectory under `projects/`, scaffolded by `/setup` from your `projects_list` config:

```
projects/
├── README.md              (this file — plugin-managed)
├── {project-tag}/
│   ├── README.md          (per-project guide — user-owned)
│   ├── decisions/         (project ADRs)
│   ├── patterns/          (reusable patterns within this project)
│   ├── guides/            (optional — operational knowledge)
│   └── references/        (optional — external resources)
└── {another-project}/
    └── ...
```

`decisions/` and `patterns/` are created automatically. `guides/` and `references/` are created on demand when you first add content there.

## Promotion ladder

Project-specific knowledge graduates to cross-project when evidence accumulates across projects:

1. **Captured in `projects/{project-tag}/patterns/`** — validated within one project, ≥2 sessions of evidence
2. **Promoted to `/approaches/`** — same pattern observed in a second project with broader applicability (`/audit-knowledge` Step 5e suggests promotion when a pattern appears in ≥`projects_promotion_threshold` projects)
3. **Promoted to `/rules/working-rules.md`** — pattern becomes a universal rule

Decisions don't typically promote — they stay in the project where they were made (though a cross-project decision can supersede them, in which case add a note linking the supersession).

## Multi-project patterns

If a pattern applies to a parent project and a child (e.g., a platform and a sub-product), tag with both project tags, place the file in the **more specific** subdirectory, and cross-link from the parent project's `README.md`. This avoids duplication while keeping discovery natural from either side.

## Indexing

All files under `projects/` are indexed by `/index` and surfaced via `/context`. Project-specific files automatically inherit the project tag from their location (e.g., a file under `projects/myproject/decisions/` is tagged `myproject` even without explicit YAML tags). You can still add additional topical tags (`architecture`, `patterns`, etc.) in YAML frontmatter — they union with the path-derived tag.

## Provenance for promoted files

When `/audit-knowledge` Step 5e promotes a project-specific file to the cross-project tree (or merges multiple project files into a synthesized cross-project file), the new file gets an `originally_at:` frontmatter field describing the source(s). This survives git history truncation and makes consolidation history greppable.

## Related
- [../README.md](../README.md) — top-level knowledge structure
- [../index.md](../index.md) — tag index
