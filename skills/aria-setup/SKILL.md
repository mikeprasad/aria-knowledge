---
name: aria-setup
description: Configure aria-cowork on first run or after updates. Verifies your knowledge folder is reachable from this Cowork session, guides you through adding it to claude_desktop_config.json for persistent multi-session access if needed, scaffolds the folder structure, and writes the canonical aria-config.md. Safe to re-run anytime — only touches what.
compatibility: Requires Cowork desktop app. Default knowledge folder is `~/Projects/knowledge/`; users with non-default locations can override via inline prompt at first /aria-setup run. Works in any project workspace once the knowledge folder is granted via claude_desktop_config.json.
---

# /aria-setup — aria-cowork Configuration

Verify the knowledge folder is reachable, guide setup if it isn't, and scaffold structure. Safe to re-run anytime.

## Step 0: Read installed plugin version

**Read the installed plugin version first.** Parse `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` and extract the `version` field. Hold it as `INSTALLED_VERSION` for use in Step 5 (config write) and Step 6 (summary). Use grep + sed to stay consistent with the no-jq invariant aria-knowledge's hook scripts follow:

```bash
INSTALLED_VERSION=$(grep '"version"' "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" | head -1 | sed 's/.*"version": *"\([^"]*\)".*/\1/')
```

All references to the version below use `{INSTALLED_VERSION}` as a substitution placeholder — the agent expands it from the captured value at runtime, so the skill body doesn't need editing per release.

## Step 1: Determine the knowledge folder path

aria-cowork v{INSTALLED_VERSION} uses a **default-path convention**: the knowledge folder is `~/Projects/knowledge/` (expand `~` to the user's home directory at runtime, producing an absolute path like `/Users/<user>/Projects/knowledge`).

Hold the default as `DEFAULT_KNOWLEDGE_FOLDER` (e.g., `~/Projects/knowledge` — expand `~` to your home directory's absolute path).

**Override mechanism for non-default locations:**

Try reading `<DEFAULT_KNOWLEDGE_FOLDER>/aria-config.md` first.

- **If it exists**: read the `knowledge_folder:` field from its frontmatter. If that field's value differs from `DEFAULT_KNOWLEDGE_FOLDER`, use the override (the user has previously configured a non-default location). Hold as `KNOWLEDGE_FOLDER`.
- **If it doesn't exist** AND the default folder also doesn't exist on disk: this is a fresh install. Ask the user inline:

  > *"aria-cowork doesn't have a knowledge folder configured yet. The default location is `~/Projects/knowledge/`. Press enter to use the default, or type an alternate absolute path:"*

  If user accepts default or provides a path, use that as `KNOWLEDGE_FOLDER`. The `/aria-setup` flow will create it and scaffold structure.

- **If the default exists but `aria-config.md` is missing**: existing folder, no aria-cowork config yet. Use `DEFAULT_KNOWLEDGE_FOLDER` and write a fresh aria-config.md in Step 5.

Hold the resolved value as `KNOWLEDGE_FOLDER`.

## Step 1b: Access probe (added v0.3.0 — cowork-only per B1)

Cowork's persistent-grant model can fail in subtler ways than a simple read can detect — a read-only grant, a revoked write permission, or filesystem errors that only surface on write. Step 1b runs a full read+write+delete round-trip to verify true folder access before any scaffolding proceeds.

**Probe sequence:**

1. **Read existence check** — attempt to Read `<KNOWLEDGE_FOLDER>/aria-config.md`. File-not-found is recoverable (fresh install); access-denied is a probe failure.
2. **Write probe** — Write a temp file at `<KNOWLEDGE_FOLDER>/.aria-probe-{timestamp}` containing the literal line `aria-cowork access probe — safe to delete`. Use the current Unix timestamp as `{timestamp}` for filename uniqueness across concurrent probes.
3. **Round-trip read** — Read the just-written probe file back to confirm the write persisted and is readable.
4. **Cleanup** — delete the probe file. If delete fails, surface a warning (probe content was harmless, but the user may want to remove `.aria-probe-*` files manually).
5. **Report PASS** if all four steps succeeded. Continue to Step 2.

**Failure handling:**

| Failure mode | Diagnostic surfaced |
|---|---|
| Read access denied | *"`<KNOWLEDGE_FOLDER>` is not granted to this Cowork session. The folder may exist but Cowork can't reach it — likely a missing or revoked persistent grant. Continue to Step 3 for grant-recovery guidance."* |
| Read succeeds but write fails | *"`<KNOWLEDGE_FOLDER>` is read-only from this Cowork session. aria-cowork needs write access to scaffold structure and persist config. Likely a read-only mount or restricted grant scope — check the persistent grant in `claude_desktop_config.json` and ensure it covers write."* |
| Write succeeds but round-trip read fails | *"Cowork wrote to `<KNOWLEDGE_FOLDER>` but couldn't read the file back. Likely a filesystem sync issue or transient FS error. Re-run `/aria-setup` to retry; if the problem persists, check disk health."* |
| Delete fails after probe success | (Warning, not halt) *"Probe completed but couldn't remove the temporary probe file. Safe to delete manually: `<KNOWLEDGE_FOLDER>/.aria-probe-*`."* |

**On any halt-class failure (rows 1-3), stop and surface the diagnostic.** Do not proceed to Step 2 or beyond — Step 2's simpler read check would fail too, and Step 3's grant guidance is the actionable next step for read-denied failures.

This probe is unique to aria-cowork — aria-knowledge runs in Code with default filesystem access and doesn't need this check. The probe productizes the field-validation lessons from the 2026-04-30 probe arc (probes 2, 3, 11) as a per-setup invariant.

## Step 2: Verify reachability

Try reading a file at the expected path. Use either:

- `<KNOWLEDGE_FOLDER>/aria-config.md` if it already exists (returning user)
- `<KNOWLEDGE_FOLDER>/README.md` (created by template seed during fresh install)
- A directory listing of `<KNOWLEDGE_FOLDER>` (any of the standard subdirectories: `intake/`, `decisions/`, etc.)

**If the read succeeds**: the folder is granted to this Cowork session. Proceed to Step 4 (folder structure validation).

**If the read fails** with an error like *"outside this session's connected folders, so Read can't reach it"*: the folder isn't granted yet. Proceed to Step 3 (grant guidance).

**If the read fails because the path doesn't exist on disk** (different from the access-denied error): proceed to Step 4 in **fresh mode** — assume the user wants a new folder created at this path; continue with the scaffold flow.

## Step 3: Guide claude_desktop_config.json edit (if folder unreachable)

The user's knowledge folder needs persistent grant via Cowork's desktop config. Provide step-by-step instructions:

> *"To make `<KNOWLEDGE_FOLDER>` reachable from every Cowork session, add it to your Cowork desktop config. Here's how:*
>
> *1. Open or create the Cowork desktop config file. On macOS, this is typically at:*
>    *`~/Library/Application Support/Claude/claude_desktop_config.json`*
>
> *2. Add your knowledge folder to the additional directories list. The exact key may be `additionalDirectories`, `additional_directories`, or similar — check your existing config or Cowork's docs for the correct field name. Example shape:*
>
>    ```json*
>    {*
>      "additionalDirectories": [*
>        "<KNOWLEDGE_FOLDER>"*
>      ]*
>    }*
>    ```*
>
> *3. Save the file and restart Cowork (or reload the plugin) so the grant takes effect.*
>
> *4. Re-run `/aria-setup` to continue scaffolding.*
>
> *Alternative for one-off testing without persistent grant: run `/add-dir <KNOWLEDGE_FOLDER>` in this Cowork conversation to grant access for the current session only. Persistent grant via desktop config is recommended for normal use — it works across all your Cowork projects without re-granting."*

Stop here until the user re-runs `/aria-setup` after the grant.

## Step 4: Folder structure scaffold

The folder is reachable. Read the expected structure from `${CLAUDE_PLUGIN_ROOT}/template/`.

**Expected directories** (create if missing):
`intake/`, `intake/clippings/`, `intake/notes/`, `intake/attachments/`, `decisions/`, `approaches/`, `guides/`, `references/`, `archive/`, `rules/`, `logs/`

**Expected files** (copy from `${CLAUDE_PLUGIN_ROOT}/template/<file>` if missing):
`README.md`, `OVERVIEW.md`, `LOCAL.md`, `aliases.md` *(user-owned, added v0.3.0 — see "User-owned templates" below)*, `intake/insights-backlog.md`, `intake/decisions-backlog.md`, `intake/extraction-backlog.md`, `intake/rules-backlog.md`, `rules/working-rules.md`, `rules/change-decision-framework.md`, `rules/enforcement-mechanisms.md`, `rules/user-rules.md`, `rules/user-examples.md` *(user-owned, added v0.3.0 — see "User-owned templates" below)*, `logs/knowledge-audit-log.md`, `logs/config-audit-log.md`, plus the directory READMEs (`approaches/README.md`, `archive/README.md`, etc.).

**Excluded** (Code-only per ADR-005): `distill/`, `stitch/` — do NOT scaffold these in aria-cowork.

**User-owned templates** (added v0.3.0):

| File | Behavior |
|---|---|
| `aliases.md` | Bootstrap once from `template/aliases.md` if missing; on subsequent `/aria-setup` runs leave untouched (never overwrite, never diff-prompt). The HTML comment marker at the top signals user-owned status. Ships with 5 commented-out cowork-flavored seed aliases (meeting, brief, doc, action, customer) — uncomment to use or replace with your own. |
| `rules/user-examples.md` | Bootstrap once from `template/rules/user-examples.md` if missing; same never-overwrite lifecycle as `aliases.md`. Ships with 3 commented-out cowork-flavored example shapes (Rules 16/13/22) — replace with your own real before/after illustrations. `/rules N` discovers matching `## Rule N` examples here automatically. |
| `rules/user-rules.md` | Already bootstrapped (existed pre-v0.3.0). Same never-overwrite lifecycle. |

The "user-owned" lifecycle differs from plugin-managed templates (like `working-rules.md`, `change-decision-framework.md`, etc.) which get diff-prompts on plugin updates so users can pull in upstream changes. User-owned templates stay frozen at first bootstrap until the user edits them — `/aria-setup` never touches them again.

**In fresh mode** (folder didn't exist on disk before this run): create the directory + everything in it. After creation, show a one-time educational note about plugin-managed vs user-owned files (per the canonical convention; see `OVERVIEW.md`).

**In update mode** (folder existed; only some files/dirs missing): create only what's missing; never overwrite existing user-owned files. Report counts: *"Created N directories, added N files, found N existing files."*

## Step 4b: Validate aliases.md (added v0.3.0 — defense-in-depth with /aria-cowork:index)

After Step 4's scaffold completes, validate `<KNOWLEDGE_FOLDER>/aliases.md`. This catches alias chains and collisions at setup time so the user fixes them before `/aria-cowork:index` would also reject them — defense-in-depth per the Q-5 lock (validate at both `/aria-setup` and `/index`).

**Skip this step** if `aliases.md` doesn't exist (rare — Step 4 just bootstrapped it from template/aliases.md if missing).

**Skip parsing** if the file exists but contains only the shipped seed (all alias lines commented out per the user-owned bootstrap). Detect this by checking whether ANY non-commented `- \`<alias>\` → \`<canonical>\`` line exists; if none, no aliases are active and validation is a no-op.

**Parse the alias map:** each non-comment line matching the pattern `` - `<alias>` → `<canonical>` `` contributes one entry. Build a flat `alias → canonical` map.

**Chain check (internal to the alias map):** if any canonical name in the parsed map ALSO appears as an alias key in another entry of the same map, halt setup with:

> *"Alias chain detected in `aliases.md`: `x` → `y` → `z`. Aliases must point directly to a canonical tag, not to another alias. Fix the chain (typically: rewrite the intermediate alias to point at the final canonical) and re-run `/aria-setup`."*

**Collision check** is NOT run at /aria-setup time — it requires scanning all promoted files' `tags:` frontmatter, which is `/aria-cowork:index`'s job (defense-in-depth's other half). `/aria-setup` only catches chain errors (which are self-contained in aliases.md and don't need file scanning). Collision-detection runs at `/aria-cowork:index` per item #6 Step 2b.

**On halt:** the setup halts but the bootstrapped aliases.md file is left on disk for the user to fix. Re-running `/aria-setup` after the fix continues from this step.

## Step 4c: Advanced Options bundle (added v0.3.0)

Cowork's wizard surfaces user-facing config fields here. Per the v0.3.0 schema decision (item #5d option ii), only fields cowork actively consumes are surfaced; codemap/stitch threshold fields are parse-tolerated but not prompted.

### [NEW]-detection observability

Before prompting, emit one transcript-visible line indicating detection state. This makes the [NEW]-detection step observable — users can verify it ran rather than being silently skipped.

| Detection result | Emit |
|---|---|
| One or more fields flagged as `[NEW]` (added since `last_setup_version` recorded in aria-config.md) | *"[aria-setup] Detected N new config keys since your last setup (v{last_setup_version}). Surfacing in Advanced Options."* |
| No new keys (last setup was at current version OR ahead) | *"[aria-setup] No new config keys since last setup. Skipping Advanced Options bundle."* |
| Fresh install (no prior `last_setup_version` to compare) | *"[aria-setup] Fresh install detected. Showing all Advanced Options."* |

If the result is "No new keys," skip the rest of this step.

### Advanced Options prompts

For each [NEW] field (or all fields on fresh install), prompt with default value:

**`active_knowledge_surfacing`** *(added v0.3.0)*
- Type: `true` | `false`
- Default: `true`
- Description: *"When `true`, `/aria-cowork:prospect` and `/aria-cowork:retrospect` autonomously Read matched knowledge files before producing reports (active surfacing). When `false`, falls back to passive mode (suggests `/context` to the user). Recommended: `true` (active mode)."*
- Prompt: *"Enable active knowledge surfacing? (y/n, default y)"*
- Map `y` / blank → `true`; `n` → `false`.

Hold the user's answer as `ACTIVE_KNOWLEDGE_SURFACING`.

### Parse-tolerated fields (not prompted)

The following fields are accepted in aria-config.md if present but **not surfaced in the wizard** — cowork doesn't consume them:

- `codemap_staleness_threshold_days` (aria-knowledge consumer only; cowork excludes `/codemap` per ADR-005)
- `stitch_staleness_threshold_days` (aria-knowledge consumer only; cowork excludes `/stitch` per ADR-005)
- `critical_paths` (aria-knowledge hook consumer; cowork has no hook layer)
- `projects_remotes` (aria-knowledge hook consumer)
- `auto_load_project_context` (aria-knowledge hook consumer)

See `CONFIG.md` for the full schema + parse-tolerated field rationale.

## Step 5: Write or update aria-config.md

Write `<KNOWLEDGE_FOLDER>/aria-config.md` with the canonical schema:

```yaml
---
knowledge_folder: <KNOWLEDGE_FOLDER>
cowork_setup_version: {INSTALLED_VERSION}
last_setup_date: <today's YYYY-MM-DD>
last_setup_surface: cowork
active_knowledge_surfacing: {ACTIVE_KNOWLEDGE_SURFACING}
---

# aria-config — shared by aria-cowork and aria-knowledge

This file is the canonical configuration for the ARIA family of plugins. Both aria-cowork (running in Cowork) and aria-knowledge (running in Claude Code) read it.

Both plugins agree to:
- Add fields, never rename or remove (additive-only schema)
- Preserve unknown fields verbatim (forward compatibility)

aria-cowork v{INSTALLED_VERSION} uses default-path convention (`~/Projects/knowledge/`); users with non-default locations override via this file's `knowledge_folder:` field. aria-knowledge in Code reads this same file from the absolute path, with legacy fallback to `~/.claude/aria-knowledge.local.md` for migration through aria-knowledge v2.14.0.

Configured by aria-cowork v{INSTALLED_VERSION} /aria-setup on <today>.
```

In **update mode**, preserve user-added markdown body content below the frontmatter. Update only the frontmatter fields whose values changed (e.g., `last_setup_date`, `cowork_setup_version`).

**Formatting rules:**
- Frontmatter delimiters exactly `---` on their own line.
- Each key starts at column 1; no quoting; no indentation.
- `knowledge_folder` is an absolute path (must start with `/`); `~` should already be expanded.
- `cowork_setup_version` is a semver string of digits and dots, no `v` prefix.
- `last_setup_date` is `YYYY-MM-DD`.
- `active_knowledge_surfacing` is bare lowercase `true` or `false` — not `True`, `yes`, or `1`. Invalid values fall back to `true` per CONFIG.md.

## Step 5b: Self-validation audit (added v0.3.0 — defense-in-depth with /aria-cowork:audit-config)

After Step 5 writes aria-config.md, verify that every known field is present. This catches gaps where Step 4c's Advanced Options bundle silently skipped a field — e.g., the agent forgot to prompt for a newly-added field, or the user's response wasn't captured correctly. Defense-in-depth per item #11e — `/aria-cowork:audit-config` also runs this check at audit cadence (Step 3b of that skill, ships in Stage D of v0.3.0).

**Source of known fields:** Read `${CLAUDE_PLUGIN_ROOT}/../CONFIG.md` (cowork's repo-root CONFIG.md, the schema-documentation file shipped with the plugin). Parse the field tables to extract:

- All field names under "**Consumed by cowork**" table (cowork actively reads these)
- All field names under "**Parse-tolerated by cowork**" table (cowork ignores but accepts)

Together these form `KNOWN_FIELDS` — the complete set of valid keys in aria-config.md.

**Audit:** Re-read `<KNOWLEDGE_FOLDER>/aria-config.md` (the file just written in Step 5) and parse its frontmatter keys. Compare against `KNOWN_FIELDS`:

- **Missing-but-consumed:** field is in CONFIG.md's "Consumed by cowork" list but absent from the user's aria-config.md. Surface as **Should Fix**.
- **Missing-but-parse-tolerated:** field is in CONFIG.md's "Parse-tolerated" list but absent. No action — these are intentionally not written by cowork's `/aria-setup`.
- **Present-and-known:** field present and matches a known name. PASS.
- **Present-but-unknown:** field present but not in `KNOWN_FIELDS`. Surface as **Possibly Stale** (could be a deprecated field from an older version or a hand-edited entry — don't auto-remove).

**Output format:**

```
[aria-setup] Self-validation audit:
  Known fields: N (M consumed by cowork, K parse-tolerated)
  Present in your config: P
  Missing (Should Fix): {list with defaults}
    - active_knowledge_surfacing (default: true) — add to config? (y/n/select)
  Possibly stale: {list, no action prompted}
    - legacy_field_name (not in current schema)
```

**On Missing-but-consumed prompt:** user can `y` (add field with default), `n` (skip — accept gap), or `select` (pick specific fields to add from the missing list).

**On any addition:** Edit `<KNOWLEDGE_FOLDER>/aria-config.md` to add the field with its default value. Don't re-write the whole file — append the new line in the frontmatter section so user's body content is preserved.

**Audit-trail entry:** Append a one-line note to `<KNOWLEDGE_FOLDER>/logs/config-audit-log.md`:

```
- YYYY-MM-DD — /aria-setup self-validation audit: N missing fields added, K possibly-stale fields surfaced (no action).
```

## Step 6: Confirm

Output a summary:

```
aria-cowork v{INSTALLED_VERSION} setup complete.
- Knowledge folder: <KNOWLEDGE_FOLDER>
- Reachability: confirmed
- Files added: <N>
- Files updated: <N>
- Files kept (user version): <N>

aria-cowork is now available in any Cowork project workspace.
Capture/retrieve flow:
  /aria-cowork:clip <url>        — save a URL or snippet to intake
  /aria-cowork:context <topic>   — load knowledge by tag
  /aria-cowork:help              — see all commands

Knowledge captured here is shared with aria-knowledge in Claude Code (both plugins read this same folder).
```

## Failure modes and recovery

- **Default folder doesn't exist and user provided no override** (Step 1): walk user through creating the default folder OR re-running with a custom path. Inline prompt handles this gracefully.
- **Folder unreachable due to missing grant** (Step 2 → Step 3): walk through `claude_desktop_config.json` edit OR offer per-session `/add-dir` fallback; re-run after.
- **Folder doesn't exist on disk** (Step 2 alt): proceed in fresh mode, create the folder + scaffold inside it (assumes user explicitly chose a path that doesn't exist yet — they want a new folder there).
- **aria-config.md exists with `knowledge_folder` value differing from the default**: trust the override (the user previously configured a non-default location). Use the value from aria-config.md and continue. Re-running /aria-setup is non-destructive; user can edit aria-config.md directly if they want to change paths.
- **claude_desktop_config.json key/path differs from this skill's guess**: the skill's guidance includes "check your existing config or Cowork's docs for the correct field name" — user can adapt. If they get stuck, point them at Cowork's official plugin docs.

## Notes for the agent

- **All filesystem operations use Cowork's native Read/Write tools** with absolute paths (`<KNOWLEDGE_FOLDER>/...`). Never invoke a Filesystem MCP connector (per ADR-003).
- The skill is **idempotent**: safe to re-run; fresh-mode and update-mode both honor user-owned files.
- aria-cowork operates on the **persistent-grant pattern**: knowledge folder access lives in `claude_desktop_config.json`, available to every Cowork session. The user works in their actual project folder (cs/, ss/, df/, whatever) and aria-cowork is reachable alongside.
- See `~/Projects/knowledge/projects/aria-cowork/decisions/008-attached-folder-pattern-for-bidirectional-sharing.md` for the full architectural mechanism (note: filename retains "attached-folder" slug for cross-reference stability; v0.2.0 content describes persistent-grant pattern).
