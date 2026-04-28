# Knowledge Repository — Local Guide

Project-specific conventions, format templates, and usage details that extend the base [README.md](README.md). This file is yours — the aria-knowledge plugin will never overwrite it.

**Last updated:** (update when you edit this file)

## Extended Structure

<!-- Document any subdirectories or conventions you add beyond the base structure.
     Example: if you create guides/claude/ for Claude Code-specific docs, note it here
     so future sessions know where to look. -->

```
knowledge/
├── ...                              # (base structure — see README.md)
├── guides/
│   └── your-topic/                  # Group related guides into subdirectories
├── intake/
│   ├── clippings/                   # Web articles, threads, saved content
│   ├── notes/                       # Quick notes and observations
│   └── attachments/                 # Images, PDFs, supporting files
└── references/
    └── ...                          # Research papers, external docs
```

## Format Templates

### Approaches (`approaches/`)

```markdown
---
Last updated: YYYY-MM-DD
tags: [tag1, tag2, tag3]
---

# [Approach Name]

## When to Use
[Conditions where this approach applies]

## When NOT to Use
[Conditions where this approach is wrong or doesn't apply]

## The Approach
[Description with examples]

## Validated By
[Project/session where this was tested and confirmed]

## Related
[Links to related rules, decisions, or other approaches]
```

### Decisions (`decisions/` or `projects/{tag}/decisions/`)

```markdown
---
Status: Accepted | Superseded | Deprecated
Date: YYYY-MM-DD
tags: [tag1, tag2]
---

# [Number] — [Title]

## Context
[What prompted this decision]

## Decision
[What we decided]

## Alternatives Considered
[What else we evaluated and why it was rejected]

## Consequences
[What this means going forward]

## Related
[Links to related rules, approaches, or other decisions]
```

**Numbering:**
- Cross-project ADRs in `decisions/` use `YYYY-NNN-` prefix (e.g., `2026-001-auth-strategy.md`) — self-dating, resets per year.
- Project-level ADRs in `projects/{tag}/decisions/` use sequential `NNN-` per project (e.g., `001-app-router-as-spa.md`) — each project is its own namespace.

### Guides (`guides/`)

```markdown
---
Last updated: YYYY-MM-DD
tags: [tag1, tag2]
---

# [Guide Title]

## Overview
[What this guide covers and who it's for]

## [Sections as needed]
[Content organized by topic]

## Related
[Links to related guides, approaches, or references]
```

### Provenance — `originally_at` (any promoted file)

When `/audit-knowledge` Step 5e promotes a project-specific file to the cross-project tree — whether a decision, approach, pattern, or guide — the new file gains an `originally_at:` YAML frontmatter field documenting the source(s) and move context. This creates a greppable consolidation history that survives git history truncation (shallow clones, squashed merges) and doesn't depend on git's rename-detection heuristics.

```yaml
---
Last updated: YYYY-MM-DD
tags: [tag1, tag2]
originally_at: projects/proj-a/decisions/004-uuid-auth.md (moved 2026-04-15 during cross-project promotion)
---
```

To enumerate every migrated file in your knowledge folder:

```bash
grep -rn "^originally_at:" knowledge/
```

Seeing `originally_at:` on a promoted file isn't an error — it's the provenance pointer back to the source. Combined with the stub-and-reference disposition at the source path, you get forward-linking provenance (this file) plus backward-linking redirect (the stub).

## What Belongs Where

| Content | Location | Reason |
|---------|----------|--------|
| Principles and constraints | `rules/` | "We must / must not" |
| Validated methodologies (cross-project) | `approaches/` | "How we do X (proven across projects)" |
| Cross-project architectural choices | `decisions/` (YYYY-NNN) | "We chose X because Y, applies across projects" |
| Operational knowledge | `guides/` | "Here's how X works" |
| External research | `references/` | "What others say about X" |
| Retired content | `archive/` | "What we used to do" |
| Unprocessed input | `intake/` | "Not yet categorized" |
| Project-specific decisions | `projects/{tag}/decisions/` (opt-in, sequential `001-`) | "Single-project decision not yet proven elsewhere" |
| Project-specific patterns | `projects/{tag}/patterns/` (opt-in) | "Pattern valuable within one project" |
| Project-specific context | Project's CLAUDE.md | Loaded automatically per project |
| Session history | Project's PROGRESS.md | Ephemeral project state |

## What Does NOT Belong Here

- Code snippets or implementation details (those belong in the codebase)
- Ephemeral task context (use PROGRESS.md or session notes)
- Opinions without validation (approaches must be tested)
- Duplicated content from CLAUDE.md files (reference, don't copy)

## When to Read

Add your own "When to Read" mappings as your knowledge base grows:

| Scenario | Read |
|----------|------|
| Starting any session | `rules/working-rules.md` (or summary in your project's CLAUDE.md) |
| Before a code change triggers the Rule 22 hook | `rules/change-decision-framework.md` |
| Designing a new enforcement mechanism | `rules/enforcement-mechanisms.md` |
| Working in a specific domain (API, CSS, Stripe, etc.) | Run `/context <topic>` to load relevant knowledge |
| After promoting knowledge or adding new files | Run `/index` to rebuild the tag index |
| Checking what knowledge exists for a topic | Run `/context <topic>` to see matches |
| *(add your own rows as your knowledge base grows)* | |

## Adding New Knowledge

1. Determine the right category (rules, approaches, decisions, guides, references)
2. Check if an existing file should be updated rather than creating a new one
3. Use the format template above for the category
4. Review with your team before committing

## How New Knowledge Files Emerge

The `intake/` backlogs are staging areas and signal generators. Over time, multiple backlog entries may cluster around a theme — repeated insights about the same problem space, or several related decisions that share underlying principles.

During the knowledge audit (`/audit-knowledge`), look for these clusters:

- **Multiple insights on the same topic** → may warrant a new approach or guide
- **Multiple decisions with shared rationale** → may warrant an approach documenting the pattern
- **Recurring feedback corrections** → may warrant a new rule

Not every insight becomes a knowledge file — but patterns of insights do.

## Tag Convention

Every promoted knowledge file should include a `tags:` field in its YAML frontmatter:

```yaml
---
Last updated: YYYY-MM-DD
tags: [api, pagination, django]
---
```

**Known tags** are maintained in `index.md` under `## Known Tags`. The initial set includes:

| Group | Tags |
|-------|------|
| Tech domain | `api`, `css`, `database`, `deployment`, `django`, `react`, `nextjs`, `react-native`, `tailwind`, `testing`, `infrastructure` |
| Cross-cutting | `architecture`, `performance`, `security`, `accessibility` |
| Tool/service | `stripe`, `linear`, `supabase`, `figma`, `claude-code` |
| Process | `process`, `decision-framework`, `enforcement` |
| Project | `cs`, `ss`, `df`, `aria` |

**Freeform tags** are valid — any tag works. Freeform tags that appear on 3+ files get suggested for promotion to the known set during `/index`. Similar tags (e.g., `api` vs `apis`) get flagged for normalization.
