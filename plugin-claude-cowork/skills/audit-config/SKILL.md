---
name: audit-config
description: 'Audit project configuration and documentation for drift, staleness, and broken references. Use when user says "/aria-cowork:audit-config", "/aria-cowork:config-audit", "config audit", "docs audit", "check setup", "audit configs", "review CLAUDE.md files", or at the first aria-cowork skill invocation when audit cadence is exceeded. (Claude Cowork variant. Namespaced-only — bare /audit-config belongs to aria-knowledge per ADR-094.)'
argument-hint: ''
---

# /audit-config — Configuration & Documentation Health Check (cowork variant)

Scan all CLAUDE.md files, plugin manifests, and knowledge files for drift, broken references, and staleness.

**Cowork variant of aria-knowledge's `/audit-config`.** Output schema (4-tier findings table) is byte-identical per item #17g + #17m. Three input-discovery + scope divergences:

- **Field enumeration via `CONFIG.md`, not `bin/config.sh`** (#17b + #17e + ADR-013). Cowork has no `bin/` directory; the canonical schema list is the human-readable `CONFIG.md` cowork ships at repo root.
- **Tracked-artifact staleness check (Step 5a) SKIPPED per ADR-005** (#17f). aria-knowledge stats `CODEMAP.md` / `STITCH.md` per project; cowork excludes `/codemap` + `/stitch` so no tracked artifacts to check.
- **Cadence invocation differs** (#17n). aria-knowledge runs cadence checks at SessionStart via hook. Cowork has no hook layer — cadence checks fire at the first aria-cowork skill invocation per session (entry-points: `/aria-setup`, `/extract`, etc., which check the log and prompt if cadence exceeded).

Step 3a.1 version-stamp ripple + Step 3a.2 adoption-state cascade run with cowork-scoped surfaces + cowork-relevant phrases per #17c + #17d.

Plugin attribution in audit-log entries uses `aria-cowork@{INSTALLED_VERSION}`. Schema-identical 4-tier output means a knowledge folder's `logs/config-audit-log.md` accepts entries from both plugins without format drift.

## Runtime Gate (per ADR-094)

**Canonical resolution:** This is the Claude Cowork variant — namespaced-only. When both `plugin-claude-code` and `plugin-claude-cowork` are loaded in the same session (most common in Claude Desktop), bare `/audit-config` resolves to aria-knowledge's variant — Code is the canonical owner of all 24 dual-port skills per ADR-094 §Part 1. To reach this skill, use the namespaced form: `/aria-cowork:audit-config`. Do NOT match bare `/audit-config` — that belongs to aria-knowledge.

**Before Step 0:** Check whether the `Bash` tool is available in this session. If `Bash` IS available (you are running in Claude Code or another runtime with shell access), surface the following notification and wait for explicit user confirmation:

> ⚠️ **Runtime mismatch — you invoked aria-cowork's `/audit-config` from a runtime with shell access.**
>
> This variant uses `CONFIG.md`-driven field enumeration and skips `CODEMAP.md` / `STITCH.md` checks per ADR-005 — but you appear to be in Claude Code, where the canonical aria-knowledge variant uses `bin/config.sh` + Agent sub-audits + tracked-artifact staleness. For the Code-native variant, use `/audit-config` (the aria-knowledge canonical).
>
> **Use `/audit-config` instead?** (`y` / `n`)

Wait for an explicit reply:

- **`y` / `yes`** — Use the `Skill` tool to invoke `audit-config` (the bare-slash canonical, which routes to aria-knowledge when both ports are loaded) with the same arguments the user provided to this invocation. Do not proceed with this skill's steps; the aria-knowledge variant takes over and runs to completion. This is the default-yes path — auto-redirect is the helpful action.
- **`n` / `no`** — Proceed with this (aria-cowork) variant anyway despite the runtime mismatch. The user has explicitly opted in.
- **No response / any other reply** — Treat as "do not proceed" and exit cleanly without running either variant.

**This gate applies even when `mode = auto`** per ADR-094 §Part 3. Auto mode's "implicit-yes on all gates" rule is suspended for the runtime-mismatch check — auto trusts that the user invoked the correct variant, and this gate enforces that precondition. All other auto-mode gates remain bypassed. The friction cost is now low: on `y`, the auto-redirect runs the correct variant with the original args.

If `Bash` is NOT available (normal Cowork runtime), proceed to Step 0.

## Step 0: Resolve Config

Read `<knowledge_folder>/aria-config.md` and extract `knowledge_folder` and `audit_cadence_config`. If the file doesn't exist, stop: *"aria-cowork is not configured. Run `/aria-setup` to get started."*

Use `{knowledge_folder}` as the base path for all knowledge file operations in subsequent steps.

## Step 1: Read the Audit Log and Determine Mode

Read `{knowledge_folder}/logs/config-audit-log.md`.

Note the "Last Audit" date and calculate days since.

**Determine how this skill was invoked:**

- **User-requested** (user said `/audit-config`, *"audit configs"*, *"check setup"*, etc.): **Always run the full audit**, regardless of how recently the last audit was. Skip directly to Step 2.
- **Cadence check at skill-invocation** (cowork has no SessionStart hook per #17n — the cadence check fires when the user invokes any aria-cowork skill that runs the cadence check at startup, typically `/aria-setup` or `/extract`):
  - If **cadence exceeded**: Prompt the user — *"It's been N days since the last config & docs audit. Want me to check for drift?"* If they agree, proceed to Step 2. If not, stop.
  - If **within cadence**: Report the last audit date and stop. *"Last config & docs audit was N day(s) ago (YYYY-MM-DD). Next check due in M days."*

**Cowork divergence vs aria-knowledge:** aria-knowledge's SessionStart hook fires the cadence check automatically at every session start, before any user input. Cowork's check is invocation-driven instead — fires when the user invokes the next skill that has the cadence check baked in. The user-experienced cadence is approximately the same (~14 days default); the trigger mechanism differs.

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

### 3a.1: Version-stamp ripple (cowork-scoped surfaces)

After a plugin/package release, version references typically touch 5+ surfaces: the manifest itself, the project's CLAUDE.md status header, any parent container CLAUDE.md table row, the project memory file's description + body + version-row, and the MEMORY.md index entry. Each is small; skipping any creates documentation drift.

**Cowork-scoped surfaces (per #17c):** for aria-cowork's own release cycle, the canonical 5-surface ripple is:

1. `aria-cowork/.claude-plugin/plugin.json` (canonical version)
2. `aria-cowork/CLAUDE.md` status header
3. `aria/CLAUDE.md` (parent container — sibling-plugin table row mentioning aria-cowork)
4. Memory file `project_aria_cowork.md` (description + body + version-row, in the attached knowledge folder's memory directory if present)
5. `MEMORY.md` index entry

Cowork can't reach `~/.claude/projects/.../memory/project_*.md` (aria-knowledge's memory location). Only memory files in the attached knowledge folder are scannable from cowork.

**Detection:**

1. For each plugin manifest (`plugin.json`) reachable from the knowledge folder + working tree, extract the canonical version string (e.g., `v0.3.0`, `v2.17.0`).
2. Glob CLAUDE.md files in the project + ancestor directories + any reachable `memory/project_*.md` files referencing the project's slug.
3. For each surface, grep for version strings matching the pattern `v?\d+\.\d+\.\d+` near a mention of the project name (e.g., `aria-cowork`, `aria-knowledge`).
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

### 3a.2: Adoption-state cascade (cowork-relevant phrases)

When a binary config value flips (e.g., `enabled=0` → `enabled=1` in a deploy script, or a placeholder folder becomes a built artifact), N referenced docs may still describe the prior state.

**Detection patterns to grep against CLAUDE.md / README.md / memory files:**

Shared patterns (apply to both plugins):

| Phrase pattern (case-insensitive) | Inverse-state check |
|-----------------------------------|---------------------|
| "currently disabled in {flag-name}" | Read the named flag/script; flag drift if value is now enabled |
| "NOT YET BUILT" / "(placeholder)" / "spec drafted, not yet built" | Check for plugin.json / package.json with non-zero version, or built artifact (e.g., `*.plugin` package) in the referenced folder |
| "pipeline built but not yet adopted" | Check whether the pipeline is enabled in the canonical config |
| "still has older prototype" / "render-broken `dist/` not regenerated" | Check file mtimes of the referenced folder (cowork can't run `git status` — file mtimes are the available signal) |
| "deferred to v{X.Y.Z}+" where X.Y.Z is now in the past | Check current manifest version against X.Y.Z |

Cowork-relevant phrase library (added per #17d — patterns common in aria-cowork's release tracking):

| Phrase pattern (case-insensitive) | Inverse-state check |
|-----------------------------------|---------------------|
| "local-only" / "non-git" | Check whether the referenced folder has been published to GitHub (e.g., the user's `mikeprasad/aria-cowork` repo exists publicly); if so, the doc is stale |
| "will become public when Phase 1 begins" | Check whether the public-repo or build-output exists; if it does, Phase 1 is no longer pending |
| "v0.X.X BUILT YYYY-MM-DD" with X.X older than current `plugin.json` version | Standard version-stamp ripple — references in this format are cowork-specific |
| "Phase N+ feature" or "Phase 2+ deferred" where the relevant feature has shipped | Cross-check the feature's presence in current skill bodies |
| "skills-only, no slash commands" if commands/ folder exists | Cross-check `commands/` folder existence (ADR-009 was skills-only-no-commands; if commands/ was later added, the language is stale) |
| "{INSTALLED_VERSION}" placeholder literal in a non-template file | Likely a copy-paste from a template that wasn't substituted — flag for hand-fix |

Surfaces to scan: CLAUDE.md files in the working tree, README.md files, project memory files in the reachable knowledge folder's memory directory (cowork can't reach `~/.claude/projects/.../memory/` per #17c — aria-knowledge's memory path).

**Conservative reporting:** Both 3a.1 and 3a.2 are pattern-based heuristics, so false positives are possible. Report under **Should Fix** (not **Critical**) and present the specific surface + the specific contradicting phrase + the underlying state — let the user judge whether each is real drift or intentional historical note.

## Step 3b: Missing-Known-Fields Cascade (cowork variant — CONFIG.md as field source)

After 3a's pattern-based drift checks, run a structural check for config-schema gaps: any user-facing field documented in `CONFIG.md` but missing from `<knowledge_folder>/aria-config.md`. This catches `/aria-setup` discipline failures retroactively — if the wizard ever silently skipped surfacing a new field (e.g., the `active_knowledge_surfacing` gap that bit aria-knowledge v2.15.1's first users), this audit cadence picks it up at the configured `audit_cadence_config` cadence (default 14 days).

**Cowork divergence per #17b + #17e:** aria-knowledge enumerates field names by parsing `${CLAUDE_PLUGIN_ROOT}/bin/config.sh` (its bash field-reader script). Cowork has no `bin/` — the canonical schema source is `CONFIG.md`, the human-readable schema doc cowork ships at repo root. Same audit logic; different parse target.

**Algorithm:**

1. Enumerate known user-facing field names by reading `${CLAUDE_PLUGIN_ROOT}/../CONFIG.md` (cowork's repo-root CONFIG.md). Parse the field tables:

   - **"Consumed by cowork"** table — fields cowork actively reads. Missing entries from this table surface as **Should Fix** (cowork's runtime relies on them).
   - **"Parse-tolerated by cowork"** table — fields cowork accepts but ignores. Missing entries from this table are NOT surfaced as findings (intentionally absent in cowork-only setups).

   For each row in either table, extract the field name from the first column. These names form `KNOWN_FIELDS_CONSUMED` and `KNOWN_FIELDS_TOLERATED` respectively.

2. For each field in `KNOWN_FIELDS_CONSUMED`, grep `<knowledge_folder>/aria-config.md` for `^{fieldname}:`. Zero hits → missing.

3. **Report:** under a new **Missing config fields** subsection in Step 6's findings, list each missing consumed-but-not-present field with:
   - Field name
   - Default value (from the corresponding `CONFIG.md` row's "Default" column; "empty" if no default documented)
   - Recommended action: *"Run `/aria-setup` to re-surface this field with `[NEW]` marker, OR hand-add `{fieldname}: {default}` to the config's frontmatter."*

4. **Classification:** report under **Should Fix** (consistent with 3a.1/3a.2 conservative reporting). Missing-field detection has effectively zero false-positive rate (deterministic check against CONFIG.md) but the FIX is user judgment — a missing field might be intentional (e.g., user removed it to fall back to default behavior).

5. **Present-but-unknown fields** (in user's aria-config.md but NOT in either CONFIG.md table) surface under **Possibly Stale** — could be a deprecated field from an older version or a hand-edited entry. Don't auto-remove.

**Why this check exists:** the `/aria-setup` wizard's Step 4c Advanced Options bundle is a *soft instruction* to Claude — it's not hook-enforced (cowork has no hook layer), so a fast/quiet `/aria-setup` run can silently skip surfacing new fields. Step 3b runs against the canonical CONFIG.md source-of-truth at audit cadence, surfacing gaps regardless of how the wizard got there. Pairs with `/aria-setup` Step 5b (Self-Validation Audit) as the setup-time safety net per defense-in-depth.

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

## Step 5a: Check Tracked Artifact Staleness (aria-knowledge-only — SKIPPED in cowork)

**Cowork-skip per #17f + D5:** aria-knowledge runs this step to surface CODEMAP.md / STITCH.md staleness per project. Cowork excludes `/codemap` and `/stitch` skills per ADR-005, so there are no tracked artifacts to check.

Cowork's `/audit-config` SKIPS this step entirely. The Step 6 report omits the Tracked Artifacts section silently (zero-finding section policy doesn't apply here — this is an architecturally-excluded check, not a zero-finding check).

For reference, aria-knowledge's check stats `{project_root}/CODEMAP.md` and `{project_root}/STITCH.md` for each configured project, classifying age against `codemap_staleness_threshold_days` (14) and `stitch_staleness_threshold_days` (30) into Critical (>2× threshold, refusal zone), Should Fix (>threshold), Low Priority (no CODEMAP), or Healthy.

If you want tracked-artifact staleness audited, run aria-knowledge's `/audit-config` from Claude Code.

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
