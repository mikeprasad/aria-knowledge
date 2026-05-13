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
- **Version-stamp ripple** — when a version appears in one CLAUDE.md, does the same version appear consistently across sibling CLAUDE.md files and memory files that reference the same project? Mismatched versions across surfaces (e.g., root says v2.14.2, sub-project says v2.14.3) signal a post-release update that didn't propagate. See Step 3a for the detection pattern.
- **Adoption-state phrases** — does language like "NOT YET BUILT", "(placeholder)", "spec drafted, not yet built", "currently disabled", "still has older prototype", "pipeline built but not yet adopted" contradict the actual state of a referenced artifact (plugin.json exists with non-zero version, config flag is enabled, build output is present)? See Step 3a.
- **Team roster** — is it consistent across CLAUDE.md files?
- **Stale content** — are there line numbers, dates, or status claims that look outdated?
- **Missing references** — are there significant docs/files in the project that aren't referenced?

## Step 3a: Release-State Cascade Patterns

Two specific cascade shapes are common enough to warrant dedicated detection. Both follow the same structural pattern: one source-of-truth surface changes (a version bump, an enabled flag), and N downstream surfaces fail to update.

### 3a.1: Version-stamp ripple

After a plugin/package release, version references typically touch 5+ surfaces: the manifest itself, the project's CLAUDE.md status header, any parent container CLAUDE.md table row, the project memory file's description + body + version-row, and the MEMORY.md index entry. Each is small; skipping any creates documentation drift.

**Detection:**

1. For each plugin manifest (`plugin.json`) or `package.json` found, extract the canonical version string (e.g., `v2.14.4`).
2. Glob CLAUDE.md files in the project + ancestor directories + `~/.claude/projects/.../memory/project_*.md` files referencing the project's slug.
3. For each surface, grep for version strings matching the pattern `v?\d+\.\d+\.\d+` near a mention of the project name.
4. Flag any surface where the stated version is **older than** the manifest version. Treat "older" by semver comparison, not string comparison.
5. Do NOT flag surfaces where the version is absent entirely — those are not drift, just under-documentation (out of scope for this check).

Report shape:
```
Version-stamp drift for {project-slug}:
  Canonical: v{manifest-version} (from {manifest-path})
  Stale surfaces:
    - {surface-path} — stated v{stale-version}
    - {surface-path} — stated v{stale-version}
```

### 3a.2: Adoption-state cascade

When a binary config value flips (e.g., `enabled=0` → `enabled=1` in a deploy script, or a placeholder folder becomes a built artifact), N referenced docs may still describe the prior state.

**Detection patterns to grep against CLAUDE.md / README.md / memory files:**

| Phrase pattern (case-insensitive) | Inverse-state check |
|-----------------------------------|---------------------|
| "currently disabled in {flag-name}" | Read the named flag/script; flag drift if value is now enabled |
| "NOT YET BUILT" / "(placeholder)" / "spec drafted, not yet built" | Check for plugin.json / package.json with non-zero version, or built artifact (e.g., `*.plugin` package) in the referenced folder |
| "pipeline built but not yet adopted" | Check whether the pipeline is enabled in the canonical config |
| "still has older prototype" / "render-broken `dist/` not regenerated" | Check `git status` / file mtimes of the referenced folder |
| "deferred to v{X.Y.Z}+" where X.Y.Z is now in the past | Check current manifest version against X.Y.Z |

Surfaces to scan are the same as 3a.1: CLAUDE.md files in the working tree, README.md files, and project memory files in `~/.claude/projects/.../memory/`.

**Conservative reporting:** Both 3a.1 and 3a.2 are pattern-based heuristics, so false positives are possible. Report under **Should Fix** (not **Critical**) and present the specific surface + the specific contradicting phrase + the underlying state — let the user judge whether each is real drift or intentional historical note.

## Step 3b: Missing-Known-Fields Cascade (v2.15.2+)

After 3a's pattern-based drift checks, run a structural check for config-schema gaps: any user-facing field documented in `${CLAUDE_PLUGIN_ROOT}/bin/config.sh` but missing from `~/.claude/aria-knowledge.local.md`. This catches `/setup` discipline failures retroactively — if the wizard ever silently skipped surfacing a new field (e.g., the `active_knowledge_surfacing` gap that bit v2.15.1's first users), this audit cadence picks it up at the configured `audit_cadence_config` cadence (default 14 days).

**Algorithm:**

1. Enumerate known user-facing field names by parsing `${CLAUDE_PLUGIN_ROOT}/bin/config.sh`. Each known field is encoded as:

   ```bash
   KT_FIELDNAME=$(sed -n '/^---$/,/^---$/p' "$KT_CONFIG" | grep '^fieldname:' | sed 's/^fieldname: *//')
   ```

   Extract `fieldname` from each `grep '^FIELDNAME:'` literal. These are the canonical fields the user's config should contain.

2. For each known field, grep `~/.claude/aria-knowledge.local.md` for `^{fieldname}:`. Zero hits → missing.

3. **Report:** under a new **Missing config fields** subsection in Step 6's findings, list each missing field with:
   - Field name
   - Default value (from the matching `KT_FIELDNAME=${KT_FIELDNAME:-default}` line in config.sh; "empty" if no default)
   - Recommended action: *"Run `/setup` to re-surface this field with `[NEW]` marker, OR hand-add `{fieldname}: {default}` to the config's frontmatter between hook-parsed entries."*

4. **Classification:** report under **Should Fix** (consistent with 3a.1/3a.2 conservative reporting). Missing-field detection has effectively zero false-positive rate (deterministic grep) but the FIX is user judgment — a missing field might be intentional (e.g., user removed it to fall back to default behavior).

**Why this check exists (v2.15.2 Origin):** the `/setup` wizard's Step 6 Advanced Options bundle is a *soft instruction* to Claude — it's not hook-enforced, so a fast/quiet `/setup` run can silently skip surfacing new fields. Step 3b runs against the canonical `bin/config.sh` source-of-truth at audit cadence, surfacing gaps regardless of how the wizard got there. Pairs with `/setup` Step 7e (Self-Validation Audit) as the setup-time safety net.

**Presence-only check:** the field can be present with an empty value (e.g., `critical_paths:` with no value is valid). Step 3b checks for *key presence*, not non-empty value — empty fields are intentional in this schema (per CONFIG.md "Empty values: bare `key:` only").

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
- Check if IDEAS-BACKLOG.md exists and has dated entries (if present)

## Step 5a: Check Tracked Artifact Staleness (added v2.16.1)

For each configured project in `KT_PROJECTS_LIST` (from config), stat `{project_root}/CODEMAP.md` and `{project_root}/STITCH.md`. Compute `age = (today - mtime).days`. Classify per the v2.16.0 thresholds:

- **Critical** (will block aria-knowledge from loading as reference): CODEMAP age > `2 × codemap_staleness_threshold_days` (default 14, so refusal zone = 28d). STITCH age > `2 × stitch_staleness_threshold_days` (default 30, so refusal zone = 60d). Flag with "REFUSAL ZONE: {N} days; trigger-based loading (T-1/T-2/T-3/T-5/T-6) refuses this artifact until updated. Run /codemap update / /stitch verify {tag}."
- **Should Fix:** CODEMAP age > threshold but ≤ 2×. STITCH age > threshold but ≤ 2×. Flag with "STALE: {N} days old; run /codemap update / /stitch verify {tag}."
- **Low Priority:** project in `projects_list` but no CODEMAP.md found. Flag with "no CODEMAP for {tag} — consider /codemap create."
- **Healthy:** all tracked artifacts within thresholds.

Skip projects whose `project_root` directory doesn't exist (stale `projects_list` entries — surface as a separate config-drift finding under "Should Fix").

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
| **Release-state cascade** | Version-stamp ripple (one surface bumped, siblings stale); adoption-state phrases that contradict the underlying flag/manifest/artifact state |

## Rules

- **Never auto-fix** — always present findings for user review first
- **Use agents for parallel scanning** — config, CLAUDE.md, and knowledge checks are independent
- **Verify paths on disk** — don't trust that documented paths exist, check them
- **Compare, don't assume** — cross-reference versions, names, and structures against actual files
- **Focus on actionable items** — don't flag cosmetic issues or preferences, focus on things that will cause errors or confusion
