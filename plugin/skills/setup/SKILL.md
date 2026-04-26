---
description: "Configure aria-knowledge plugin. Creates or validates a knowledge folder, checks dependencies, sets audit cadences, and writes config. Run on first install or after plugin updates. Trigger: '/setup', 'setup aria-knowledge', 'configure knowledge'."
argument-hint: ""
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# /setup — Knowledge Tools Configuration

Walk the user through configuring their knowledge folder and plugin settings. Safe to re-run at any time — only touches what needs updating.

## Step 1: Check for Existing Config

Read `~/.claude/aria-knowledge.local.md`.

- **If it exists:** show current settings and say "aria-knowledge is already configured. I'll check for updates." Then proceed to Step 2 in **update mode** — scan for missing structure, re-diff templated files, check dependencies.
- **If it doesn't exist:** say "Let's set up aria-knowledge. This will configure your knowledge folder and preferences." Proceed to Step 2 in **fresh mode**.

## Step 2: Knowledge Folder Location

Ask the user:
> "Where would you like your knowledge folder? You can:
> (a) Provide a path to an existing folder
> (b) Create a new one — I'll ask where to put it"

If **(a) existing path:**
- Verify the path exists and is a directory
- Proceed to Step 3 in **existing mode**

If **(b) create new:**
- Ask for the desired location (parent directory + folder name)
- Create the directory
- Proceed to Step 3 in **create mode**

## Step 3: Folder Structure Validation

Read the expected structure from `${CLAUDE_PLUGIN_ROOT}/template/`.

**Expected directories:** `intake/`, `intake/notes/`, `intake/attachments/`, `intake/clippings/`, `intake/pre-compact-captures/`, `intake/ideas/`, `logs/`, `rules/`, `approaches/`, `decisions/`, `guides/`, `references/`, `archive/`

**Expected files:** `README.md`, `OVERVIEW.md`, `LOCAL.md`, `intake/insights-backlog.md`, `intake/decisions-backlog.md`, `intake/extraction-backlog.md`, `intake/rules-backlog.md`, `intake/ideas/README.md`, `logs/knowledge-audit-log.md`, `logs/config-audit-log.md`, `rules/working-rules.md`, `rules/user-rules.md`, `rules/change-decision-framework.md`, `rules/enforcement-mechanisms.md`, `guides/README.md`, `approaches/README.md`, `decisions/README.md`, `references/README.md`, `archive/README.md`

**User-owned files (created once from template, never overwritten or diffed):** `LOCAL.md` (project-specific guide), `rules/user-rules.md` (your custom rules — ARIA never touches this file), `guides/README.md`, `approaches/README.md`, `decisions/README.md`, `references/README.md`, `archive/README.md` (directory stubs users may customize).

**In create mode:** Create all directories and copy all template files. After creation, display a **one-time educational note** about the file-class model (this note is only shown on fresh installs — in update/existing mode, skip it):

> **First-setup note: Plugin-Managed vs User-Owned Files**
>
> Your knowledge folder now contains two classes of template files:
>
> - **Plugin-managed** — `README.md`, `OVERVIEW.md`, `rules/working-rules.md`, `rules/change-decision-framework.md`, `rules/enforcement-mechanisms.md` (and `projects/README.md` when the project tier is enabled). These are diffed on every `/setup` run. Customize them freely — your edits will appear as diff prompts when plugin updates ship. That's how you receive improvements without silent overwrites. Each managed file also carries a `<!-- plugin-managed: -->` comment header so you can spot them at edit time.
> - **User-owned** — `LOCAL.md`, `rules/user-rules.md`, intake backlogs (`insights-backlog.md`, `decisions-backlog.md`, `extraction-backlog.md`, `rules-backlog.md`) and the `intake/ideas/` directory (one file per idea since v2.11), audit logs under `logs/`, directory README stubs (`guides/`, `approaches/`, `decisions/`, `references/`, `archive/`), and per-project READMEs under `projects/{tag}/`. ARIA never diffs or overwrites these. Your customizations live here safely.
>
> See `OVERVIEW.md` "Plugin-Managed vs User-Owned Files" for details. This note appears only on first setup.

**In existing mode:** Scan what's present vs missing.
- For missing **directories**: create them silently.
- For missing **files**: copy from template and note what was added.
- For existing **files**: do NOT overwrite — collect for diffing in Step 4.
- Report: "Created N directories, added N files, found N existing files to check."

**Project tier scaffolding** (if `projects_enabled: true` in current or pending config) is deferred to **Step 7c** — it runs after the config is written so it uses the final values (including answers from Step 6 that aren't in the config file yet during Step 3).

## Step 3b: Legacy `ideas-backlog.md` Detection

ARIA v2.11 moved the ideas backlog from a single `intake/ideas-backlog.md` file to per-file storage under `intake/ideas/`. Users upgrading from v2.10.x or earlier have an orphaned legacy file that v2.11 skills don't read. This step catches the migration on the first post-upgrade `/setup` run.

**Check:** does `{knowledge_folder}/intake/ideas-backlog.md` exist?

- **If no:** skip this step silently. Fresh installs and already-migrated users land here.
- **If yes:** count active entries by running:

  ```bash
  awk '/^---$/{sep++; next} sep>=1 && /^### /{c++} END{print c+0}' "{knowledge_folder}/intake/ideas-backlog.md"
  ```

  - **If count is 0:** the legacy file has no active entries (cleared-history HTML comments only). Prompt: *"Empty pre-2.11 `ideas-backlog.md` found. Delete it? (y/n)"* — on yes, `rm` the file; on no, leave it.
  - **If count > 0:** report: *"Pre-2.11 `ideas-backlog.md` detected with {N} active entries. ARIA v2.11 uses per-file ideas in `intake/ideas/`. Options:"*
    - `(1) Migrate now` — run `bash ${CLAUDE_PLUGIN_ROOT}/bin/migrate-ideas-backlog.sh "{knowledge_folder}"` and report the output (N files written, original renamed to `ideas-backlog.md.pre-2.11-migration`)
    - `(2) Skip for now` — leave the file in place; `/setup` will prompt again on the next run. Note in the Step 8 summary that legacy entries are still stranded.
    - `(3) Never migrate` — write a sentinel file at `{knowledge_folder}/intake/ideas/.legacy-skipped` so future `/setup` runs stop prompting. Document that the user accepts stranded pre-2.11 entries.

**Never auto-migrate without user choice.** The migration renames the original file (doesn't delete), so it's reversible, but executing filesystem changes without confirmation violates the user-review principle `/setup` is built around.

**Report** in Step 8 summary: *"Legacy ideas-backlog.md: migrated N entries"* or *"Legacy ideas-backlog.md: skipped (N entries still pending)"* or *"Legacy ideas-backlog.md: not detected"* as appropriate.

## Step 4: File Diffing

For each templated file that already exists in the user's folder, compare against the plugin's shipped version in `${CLAUDE_PLUGIN_ROOT}/template/`.

**Files to diff:** `rules/working-rules.md`, `rules/change-decision-framework.md`, `rules/enforcement-mechanisms.md`, `README.md`, `OVERVIEW.md`, `projects/README.md` (plugin-managed if present)

**Never diff:** `LOCAL.md` (user-owned), `rules/user-rules.md` (user-owned — your custom rules), directory README stubs (`guides/README.md`, `approaches/README.md`, `decisions/README.md`, `references/README.md`, `archive/README.md`), backlog files (`intake/insights-backlog.md`, `intake/decisions-backlog.md`, `intake/extraction-backlog.md`, `intake/rules-backlog.md`) and the `intake/ideas/` directory (`intake/ideas/README.md` and all per-file ideas under `intake/ideas/**`), audit log files (`logs/knowledge-audit-log.md`, `logs/config-audit-log.md`), and per-project READMEs (`projects/{tag}/README.md` and any other content under `projects/{tag}/**`) — these contain user data or user-customizable content.

For each file with differences:
1. Notify: "[filename] differs from the plugin version."
2. Show a brief summary of what's different (not the full diff unless asked).
3. Offer options:
   - **Keep mine** — no change
   - **Use plugin version** — overwrite with template
   - **Show diff** — display the full diff, then ask again

If no files differ (or all are new), skip this step silently.

In **update mode** (re-run): always diff, even if the file was previously kept. The plugin version may have changed.

## Step 5: Dependency Check

Check if the `explanatory-output-style` plugin is installed:

```bash
find ~/.claude/plugins -name "explanatory-output-style" -type d 2>/dev/null | head -1
```

- **If found:** "explanatory-output-style plugin detected. Insight capture will be enabled."
- **If not found:** "The explanatory-output-style plugin generates Insight blocks that aria-knowledge can capture automatically. It's an official Anthropic plugin. Want to install it? (recommended, but optional)"
  - If user says yes: guide them to install it (the exact install mechanism depends on their Claude Code setup)
  - If user says no: "Insight capture will be disabled. You can enable it later by installing the plugin and re-running /setup."

Record the result as `true` or `false`.

## Step 6: Cadence Configuration

Present current or default cadences:
> "Audit cadences control how often you're prompted to review knowledge:
> - **Knowledge audit:** triggers when either (a) backlog accumulates 20+ entries (primary, activity-driven) or (b) 7 days have elapsed since the last audit (safety net for low-activity weeks). Tier messages differ by size: 20+ "suggested", 35+ "recommended", 50+ "overdue — multi-pass".
> - **Config audit:** every 14 days (checks configs and docs for drift)
> - **Update check:** every 30 days (prompts to run /setup for plugin template updates)
>
> Want to change any? (Enter new values or press enter to keep defaults. Knowledge audit has two knobs: `audit_trigger_threshold` (entries, default 20) and `audit_cadence_knowledge` (days, default 7).)"

Record the values.

### Advanced Options

**Always offer** the advanced-settings review on every `/setup` run — both fresh installs and re-runs. New users need to see what's tunable up front rather than discovering it later; returning users need to surface and adjust values they may not have configured initially (e.g., keys added by plugin updates since their last `/setup`). Auto-mode users still see the bundle; pressing enter to accept defaults is an explicit no-op rather than a silent skip.

**Highlight new-since-last-setup keys (re-runs only):** before showing the bundle below, compare each Advanced Option key against the existing config from Step 1. For any key that exists in this spec but is **not** present in the user's current config (the upgrade case — a plugin update added the key after the user's last `/setup`), append `[NEW]` to that bullet's title in the bundle and prepend a one-line note above the bundle:

> *"Some settings are new since your last `/setup` run — `[NEW]` markers below indicate keys added by plugin updates that aren't yet in your config. Consider whether to set them now."*

Detection is a per-key `grep -q '^{key}:' ~/.claude/aria-knowledge.local.md`; non-zero exit means the key is missing → flag with `[NEW]`. For fresh installs there is no prior config to compare against, so no `[NEW]` markers appear and no preamble note is shown — the bundle just renders defaults.

> "Advanced settings (defaults are fine for most users):
> - **Freeform tag promotion threshold:** 3 (suggest promoting a freeform tag to known after it appears on this many files)
> - **Staleness threshold:** 6 months (flag knowledge files not updated within this period)
> - **Ideas staleness threshold:** 7 days (during `/audit-knowledge`, mark idea files in `intake/ideas/` older than this with `[STALE — still relevant?]` to prompt Accept/Reject/Defer decisions)
> - **Auto-capture on compaction:** true (save transcript snapshot before context compaction)
> - **Critical paths:** (empty) comma-separated path patterns that always require HIGH impact assessment (e.g., auth/*,payments/*,migrations/*)
> - **Ticketing plugins:** (empty) comma-separated `tag:plugin-command` pairs mapping a project tag to its ticket-drafting plugin (e.g., `proj-a:foo-ticket,proj-b:bar-ticket`). When set, `/audit-knowledge` prints a hint to use that plugin's command when an idea's project matches a mapped tag during the `Accept → tracker` disposition. Hint only — never auto-invokes. Leave empty if you don't use a ticketing plugin or prefer to copy ideas into your tracker manually. Plugin commands are bare names — no leading `/`. Validate input: each pair must contain exactly one `:` separating tag from command; project tags cannot contain `:` or `,`; plugin commands cannot start with `/` (strip leading `/` and warn if found).
> - **Project-specific knowledge tier:** disabled (creates `projects/{tag}/` subdirectories for project-specific decisions and patterns; opt in if you want to organize knowledge by project alongside the cross-project tree. If enabled, you'll be asked an inline follow-up about auto-loading project context on session start.)
>
> Want to change any? (Enter new values or press enter to keep defaults)"

Record the values.

### Project Setup (only if user enables the project-specific knowledge tier)

If the user enables (or keeps enabled) the project-specific knowledge tier in Advanced Options, ask four follow-up questions. In **update mode** where values already exist in the config, show the current value for each question and let the user keep it (press enter) or enter a new value — this is the discoverable path for toggling `auto_load_project_context` on a re-run when the tier was previously enabled:

1. **Project list** — "Comma-separated `tag:relative-path` pairs (e.g., `proj-a:path/to/proj-a,proj-b:proj-b,lib:shared-lib`). Paths are relative to the parent of your knowledge folder (typically `~/Projects/`). Press enter to defer adding projects:"
2. **Project remotes (optional)** — "Optional git-remote URL patterns for fallback project detection when CWD doesn't match a configured path. Comma-separated `tag:url-substring` pairs (e.g., `proj-a:myorg/proj-a-repo`). Press enter to skip:"
3. **Promotion threshold** — "Minimum number of projects that must share a similar pattern before `/audit-knowledge` suggests cross-project promotion (default 2):"
4. **Auto-load project context on session start** — "When your CWD matches a configured project, should SessionStart automatically suggest `/context {tag}`? This is a runtime convenience — the project tier works fine without it, and you can change this later by editing `auto_load_project_context` in `~/.claude/aria-knowledge.local.md`. (y/n, default n):"

**Validate input:**
- Project tags cannot contain `:` or `,` (these are the parser delimiters). If invalid, show the offending tag and re-prompt.
- Promotion threshold must be a plain integer ≥ 1. If invalid, re-prompt.
- Auto-load answer must be `y`/`n` (or empty for default). If invalid, re-prompt.
- For each `tag:path` pair, warn (don't error) if the resolved path doesn't exist on disk yet — the user may be configuring projects they haven't created.

**Existing-folder detection:**

Before prompting, scan the user's knowledge folder for an existing `projects/` subdirectory:

- **If found AND `projects_enabled` is unset in config:** Skip the Advanced Options bullet for this feature; instead prompt directly: "Detected existing `projects/` folder with these subdirectories: [list]. Enable project-specific knowledge tier? (y/n)" — if yes, auto-populate `projects_list` from detected subdirectories (prompt for the path mapping per detected tag), then ask question 4 from the Project Setup flow above so the user can opt into `auto_load_project_context` at the same time.
- **If found AND `projects_enabled: false` explicitly in config:** Leave the existing folder untouched; note in verbose output: "An existing `projects/` folder was detected but the projects tier is disabled in config. Folder is preserved; automation is off."
- **If found AND `projects_enabled: true`:** Verify each detected subdirectory is in `projects_list`; prompt to add any missing ones. Then surface the current `auto_load_project_context` value as a status check: "Auto-load project context on session start is currently [on/off]. Change? (y/n, default n — keep current)." — this is the re-run discoverability path for toggling the flag when the tier was previously enabled.

**Never auto-delete or auto-rewrite existing `projects/` content.**

## Step 7: Write Config

Write `~/.claude/aria-knowledge.local.md` with the collected settings:

```yaml
---
knowledge_folder: [path from Step 2]
audit_cadence_knowledge: [value from Step 6, default 7]
audit_trigger_threshold: [value from Step 6, default 20]
audit_cadence_config: [value from Step 6]
explanatory_plugin: [true/false from Step 5]
audit_cadence_update: [value from Step 6, default 30]
freeform_promotion_threshold: [value from Step 6, default 3]
staleness_threshold_months: [value from Step 6, default 6]
ideas_staleness_threshold_days: [value from Step 6, default 7]
auto_capture: [true/false from Step 6, default true]
critical_paths: [comma-separated patterns from Step 6, default empty]
ticketing_plugins: [comma-separated tag:plugin-command pairs from Step 6, default empty]
projects_enabled: [true/false from Step 6, default false]
projects_list: [comma-separated tag:path pairs from Step 6, default empty]
projects_remotes: [comma-separated tag:url-pattern pairs from Step 6, default empty]
projects_promotion_threshold: [integer from Step 6, default 2]
auto_load_project_context: [true/false from Step 6, default false]
---
```

Add a markdown body below the frontmatter:

```markdown
# Knowledge Tools Configuration

Configured by /setup on [today's date].
```

In **update mode:** preserve any user-added content in the markdown body below the frontmatter when rewriting.

**Formatting rules** — the config file MUST follow these exact conventions or the hook scripts cannot parse it. The hooks parse this file using pure `grep + sed` (no jq/yq/python) — these constraints exist so the substitution patterns in `bin/config.sh` work correctly, and any deviation breaks parsing silently.
- Frontmatter delimiters must be exactly `---` on their own line (no leading spaces, no trailing content)
- Each key must start at column 1 with no indentation
- Keys use the exact names shown above (no quoting, no trailing spaces)
- Values must NOT be quoted — write `knowledge_folder: /path/to/folder`, not `knowledge_folder: "/path/to/folder"`
- **Empty values:** write `key:` with nothing after the colon (optionally one trailing space). Do NOT write `key: null`, `key: ""`, `key: none`, or `key: []` — the parser treats those as literal string values (`"null"`, `"\"\""`, etc.) and validators won't normalize them to empty
- `knowledge_folder` must be an absolute path (starts with `/`) and must not contain `..`
- Cadence values must be plain integers (no units, no quotes)
- `projects_enabled` must be exactly `true` or `false` (not `True`, `yes`, `1`, etc.)
- `projects_list`, `projects_remotes`, and `ticketing_plugins`: comma-separated `tag:value` pairs, no spaces around the colon or comma (e.g., `proj-a:path/to/proj-a,proj-b:proj-b` for paths; `proj-a:foo-ticket,proj-b:bar-ticket` for plugin commands)
- Project tags (used in `projects_list`, `projects_remotes`, `ticketing_plugins`) cannot contain colons or commas (the parser splits on these)
- `ticketing_plugins` plugin-command values are bare command names without the leading `/` (e.g., `foo-ticket`, not `/foo-ticket`) — `/audit-knowledge` prepends the slash when printing the hint
- `projects_promotion_threshold` must be a plain integer ≥ 1 (no units, no quotes)
- `auto_load_project_context` must be exactly `true` or `false` (not `True`, `yes`, `1`, etc.)
- No blank lines between frontmatter entries

## Step 7b: Verify Config Round-Trip

After writing the config file, read it back and verify that each value can be extracted using the same patterns that `config.sh` uses. This catches formatting issues before the user discovers them in the next session.

**Verification checks:**
1. Read `~/.claude/aria-knowledge.local.md`
2. Extract the frontmatter block (content between the first and second `---` lines)
3. For each key, verify the value matches what was intended:
   - `knowledge_folder` — grep for `^knowledge_folder:` and confirm the extracted path matches Step 2's value
   - `audit_cadence_knowledge` — confirm it's the integer from Step 6
   - `audit_trigger_threshold` — confirm it's the integer from Step 6 (default 20)
   - `audit_cadence_config` — confirm it's the integer from Step 6
   - `explanatory_plugin` — confirm it's `true` or `false`
   - `audit_cadence_update` — confirm it's the integer from Step 6
   - `freeform_promotion_threshold` — confirm it's the integer from Step 6
   - `staleness_threshold_months` — confirm it's the integer from Step 6
   - `ideas_staleness_threshold_days` — confirm it's the integer from Step 6
   - `auto_capture` — confirm it's `true` or `false`
   - `critical_paths` — confirm it's a comma-separated string of path patterns (or empty)
   - `ticketing_plugins` — confirm it's a comma-separated string of `tag:plugin-command` pairs (or empty); validate no project tag contains `:` or `,`; validate plugin-command values do not start with `/`
   - `projects_enabled` — confirm it's `true` or `false`
   - `projects_list` — confirm it's a comma-separated string of `tag:path` pairs (or empty); validate no project tag contains `:` or `,`
   - `projects_remotes` — confirm it's a comma-separated string of `tag:url-pattern` pairs (or empty); validate no project tag contains `:` or `,`
   - `projects_promotion_threshold` — confirm it's a plain integer ≥ 1 (matches Step 6 input)
   - `auto_load_project_context` — confirm it's `true` or `false`
   - **Empty-sentinel check** — for string-valued keys with an empty default (`critical_paths`, `ticketing_plugins`, `projects_list`, `projects_remotes`): confirm the raw extracted value is not the literal string `null`, `""`, `none`, or `[]`. If the key is intended to be empty, the value after the colon must be truly empty (nothing or a single trailing space). Rewrite the key as `key:` and re-verify.

**If any check fails:** rewrite the file with corrected formatting and verify again. Report which value failed and what was fixed.

**If all checks pass:** proceed to Step 7c silently.

## Step 7c: Project Tier Scaffolding

Runs only if the config just written has `projects_enabled: true` and a non-empty `projects_list`. Skip entirely otherwise — no action, no output.

Scaffold the project tier using the final config values:

1. **Create `projects/` directory** if it doesn't exist.
2. **Copy `${CLAUDE_PLUGIN_ROOT}/template/projects/README.md` to `projects/README.md`** if missing (plugin-managed; will be diffed on future `/setup` runs).
3. **For each entry in `projects_list` (parsed as `tag:path` pairs):**
   - Create `projects/{tag}/` if missing.
   - Create `projects/{tag}/decisions/`, `projects/{tag}/patterns/`, and `projects/{tag}/rules/` if missing. The `rules/` subdir is the destination for `/audit-knowledge` Step 7's project-tier rule promotion (`{knowledge_folder}/projects/{tag}/rules/working-rules.md`); it stays empty until the first rule is promoted.
   - If `projects/{tag}/README.md` does not exist, generate it from this per-project template:
     ```markdown
     ---
     Last updated: [today's date]
     tags: [{tag}, knowledge-structure]
     ---

     # {Project Display Name} Project Knowledge

     Project-specific architecture decisions, patterns, and gotchas for {project display name}.

     ## Structure

     - `decisions/` — Architecture Decision Records (ADRs) — numbered sequentially per project (001, 002, ...)
     - `patterns/` — Reusable patterns specific to this project
     - `rules/` — Project-specific working rules promoted from `intake/rules-backlog.md`; lands `working-rules.md` here
     - `guides/` (optional) — Operational knowledge specific to this project; create on demand
     - `references/` (optional) — External resources specific to this project; create on demand

     ## Promotion

     When a pattern in this folder is validated in another project, `/audit-knowledge` will surface it as a candidate to promote to `knowledge/approaches/`. See `knowledge/projects/README.md` for the full promotion ladder.

     ## Related
     - [../README.md](../README.md) — projects/ tier overview
     - [../../index.md](../../index.md) — tag index
     ```
     - **Project Display Name** is derived from the tag with hyphens converted to spaces and title-cased (e.g., `cs-builder` → `Cs Builder`). If the tag doesn't produce a sensible display name, use the tag as-is and prompt the user to edit the README header.
4. **Never overwrite** existing per-project READMEs or content under `projects/{tag}/` — these are user-owned.
5. **Report** what was scaffolded: "Project tier: created N directories, N per-project READMEs."

## Step 8: Confirm

Output a summary:

```
Setup complete!
- Knowledge folder: [path]
- Knowledge audit: every [N] days
- Config audit: every [N] days
- Update check: every [N] days
- Insight capture: [enabled/disabled]
- Auto-capture on compaction: [enabled/disabled]
- Ticketing plugins: [N mappings configured | not configured (empty — change anytime by re-running /setup; the advanced-options bundle always shows the current value)]
- Files added: [N]
- Files updated: [N]
- Files kept (user version): [N]

Two habits that make ARIA most effective:
- Run /extract before ending sessions — captures knowledge while the full conversation is in context
- Respond to "Knowledge audit due" prompts — promotes pending items so /context can surface them later
Everything else runs automatically via hooks.
```
