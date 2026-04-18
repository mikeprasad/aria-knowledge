---
description: "Audit project configuration and documentation for drift, staleness, and broken references. Use when user asks for 'config audit', 'docs audit', 'check setup', 'audit configs', 'review CLAUDE.md files', or at session start when audit cadence is exceeded."
argument-hint: ""
allowed-tools: Read, Glob, Grep, Write, Edit, Agent
---

# /audit-config — Configuration & Documentation Health Check

Scan all CLAUDE.md files, `.claude/settings.local.json` configs, plugin manifests, and knowledge files for drift, broken references, and staleness.

## Step 0: Resolve Config

Read `~/.claude/aria-knowledge.local.md` and extract `knowledge_folder` and `audit_cadence_config`. If the file doesn't exist, stop: "aria-knowledge is not configured. Run /setup to get started."

Use `{knowledge_folder}` as the base path for all knowledge file operations in subsequent steps.

## Step 1: Read the Audit Log and Determine Mode

Read `{knowledge_folder}/logs/config-audit-log.md`.

Note the "Last Audit" date and calculate days since.

**Determine how this skill was invoked:**

- **User-requested** (user said `/audit-config`, "audit configs", "check setup", etc.): **Always run the full audit**, regardless of how recently the last audit was. Skip directly to Step 2.
- **Session-start check** (triggered by the SessionStart hook): Check if the configured cadence has been exceeded.
  - If **cadence exceeded**: Prompt the user — *"It's been N days since the last config & docs audit. Want me to check for drift?"* If they agree, proceed to Step 2. If not, stop.
  - If **within cadence**: Report the last audit date and stop. *"Last config & docs audit was N day(s) ago (YYYY-MM-DD). Next check due in M days."*

## Step 2: Scan Configuration Files

Use agents in parallel to scan these areas:

### 2a: Settings Files
Find all `.claude/settings.local.json` files in the current working directory. For each:
- Validate JSON structure
- Check all `Bash(...)` permission paths exist on disk
- Check all `mcp__*` references against currently available MCP tools
- Flag stale or redundant permissions
- Check for ghost configs in unexpected locations (e.g., `node_modules/`)

### 2b: Plugin Manifests
For each plugin referenced in settings files:
- Compare manifest version against any version claims in CLAUDE.md files
- Verify plugin paths referenced in settings files

### 2c: Plugin Configs
Check `.claude/*.local.md` files:
- Verify referenced IDs and paths are properly formatted
- Note configuration settings

## Step 3: Scan CLAUDE.md Files

Find all CLAUDE.md files recursively in the current working directory.

Expand via Glob first, then issue Read calls for all found CLAUDE.md files in a single parallel tool-use block. Validation checks run in the main thread after reads complete.

For each file, check:
- **File references** — do referenced files/paths actually exist?
- **Cross-references** — do pointers to other CLAUDE.md files resolve?
- **Version claims** — do stated versions match actual manifests/package.json?
- **Team roster** — is it consistent across CLAUDE.md files?
- **Stale content** — are there line numbers, dates, or status claims that look outdated?
- **Missing references** — are there significant docs/files in the project that aren't referenced?

## Step 4: Scan Knowledge Repository

Read the `{knowledge_folder}` directory structure and verify:
- `{knowledge_folder}/README.md` tree matches actual file structure
- All files referenced in README exist
- No orphaned files (files that exist but aren't in README)
- Knowledge files cross-reference correctly
- `{knowledge_folder}/decisions/` — check if pending decisions in backlog have been waiting more than 2 audit cycles
- `{knowledge_folder}/guides/` — verify subdirectory READMEs exist if subdirectories are present

Resolve the knowledge-folder glob patterns via Glob first, then issue Read calls for all resolved files in a single parallel tool-use block. Structural verification runs in the main thread after reads complete.

## Step 5: Check PROGRESS.md Files

Glob for PROGRESS.md files first, then Read all found files in a single parallel tool-use block.

For each PROGRESS.md file found in the current working directory:
- Note the date of the last session entry
- Flag if no updates in 7+ days (for active projects)
- Check if PLAN.md and PROGRESS.md are aligned (if both exist)

## Step 6: Present Findings

Present results organized by severity:

**Output policy:** emit every severity section defined in the format below, even when all sections resolve to "None". Zero-finding audits are informational signals that the audit actually ran the checks — do not collapse the structured report into a one-line "no issues" summary. "Healthy (no issues)" should always list the areas that passed cleanly, not be omitted even when all four severity sections are empty.

```
## Config & Docs Audit Results (YYYY-MM-DD)

**Last audit:** YYYY-MM-DD (N days ago)
**Files scanned:** X config files, Y CLAUDE.md files, Z knowledge files

### Critical (blocks work or causes errors)
- [list items or "None"]

### Should Fix (drift that will cause confusion)
- [list items or "None"]

### Low Priority (cleanup, nice-to-have)
- [list items or "None"]

### Healthy (no issues)
- [list areas that passed cleanly]
```

## Step 7: Wait for User Review

**STOP here.** Do NOT fix anything automatically.

Present findings and ask the user which items to fix. Only proceed with fixes after explicit approval. For each approved fix, apply the change and confirm.

If there are no issues, say so clearly:
> "All configs and docs are healthy. No drift detected."

## Step 8: Update the Audit Log and Knowledge Files

After completing any approved fixes:

1. Update `{knowledge_folder}/logs/config-audit-log.md`:
```markdown
## Last Audit
- **Date:** YYYY-MM-DD
- **Result:** [describe outcome — e.g., "No issues found" or "Fixed N items — brief description"]
```

Move the previous "Last Audit" entry to "Previous Audits".

2. If the audit revealed changes to the knowledge system setup, update relevant files in `{knowledge_folder}/`.

## What This Audit Catches

| Category | Examples |
|----------|----------|
| **Config drift** | Broken paths, stale permissions, ghost configs, outdated MCP refs |
| **Doc staleness** | Version mismatches, missing file references, line number rot |
| **Context drift** | Team roster changes, project status gaps, PROGRESS.md staleness |
| **Structure issues** | README not matching actual files, orphaned docs, missing cross-refs |

## Rules

- **Never auto-fix** — always present findings for user review first
- **Use agents for parallel scanning** — config, CLAUDE.md, and knowledge checks are independent
- **Verify paths on disk** — don't trust that documented paths exist, check them
- **Compare, don't assume** — cross-reference versions, names, and structures against actual files
- **Focus on actionable items** — don't flag cosmetic issues or preferences, focus on things that will cause errors or confusion
