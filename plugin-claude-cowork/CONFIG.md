# ARIA Cowork Configuration Schema

Canonical reference for `{knowledge_folder}/aria-config.md` — every field, what reads it, what's safe to hand-edit. Run `/aria-setup` to configure interactively, or edit directly using the rules below.

## File location (cross-plugin divergence)

| Plugin | Config file path |
|---|---|
| **aria-cowork** | `{knowledge_folder}/aria-config.md` (in the persistent-granted folder) |
| **aria-knowledge** | `~/.claude/aria-knowledge.local.md` |

The **schema is unified** between both plugins — same field names, same value formats, same shape constraints. The **files are separate** because Cowork's persistent-grant model can't reach `~/.claude/` (see [`~/Projects/knowledge/guides/claude/cowork-plugin-validation.md`](../knowledge/guides/claude/cowork-plugin-validation.md) and ADR-008).

A user running both plugins on the same machine maintains two config files. Sync them by hand or accept that they may diverge on plugin-specific fields (e.g., aria-knowledge's hook-tier fields don't apply in cowork).

## File shape

YAML frontmatter between `---` delimiters, optional markdown body for human notes. Keys are at column 1. Values are unquoted. Empty values are bare `key:` (never `null`, `""`, `none`, or `[]`).

```yaml
---
knowledge_folder: /absolute/path/to/knowledge
audit_cadence_knowledge: 7
…
projects_groups:
  acme:
    backend: acme-server
    web: acme-web
---

# Knowledge Tools Configuration

Configured by /aria-setup on YYYY-MM-DD.
```

The column-1 constraint mirrors aria-knowledge's hook-parser requirements even though cowork has **no hook layer** — preserved for cross-plugin compatibility so a Cowork-written config remains readable by aria-knowledge's bash parsers if the same file is shared.

## Field tiers (cross-plugin)

In aria-knowledge, fields split into "hook-parsed" and "skill-only" tiers based on which runtime reads them. In aria-cowork, **all fields are read by Claude in skill context** — cowork has no hook layer. The tier distinction is preserved as a documentation aid (so cross-plugin readers know which fields aria-knowledge's bash hooks care about), but doesn't gate cowork's parser behavior.

## Fields

### Consumed by cowork (skills implement the behavior)

| Field | Type | Default | Read by (cowork) |
|---|---|---|---|
| `knowledge_folder` | absolute path | (required) | All cowork skills |
| `audit_cadence_knowledge` | integer (days) | 7 | `/audit-knowledge`, `/aria-setup` |
| `audit_trigger_threshold` | integer (entries) | 20 | `/audit-knowledge` |
| `audit_cadence_config` | integer (days) | 14 | `/audit-config`, `/aria-setup` |
| `audit_cadence_update` | integer (days) | 30 | `/aria-setup` |
| `last_setup_version` | semver string | (set by `/aria-setup`) | `/aria-setup` |
| `freeform_promotion_threshold` | integer | 3 | `/audit-knowledge` |
| `staleness_threshold_months` | integer | 6 | `/audit-knowledge` |
| `ideas_staleness_threshold_days` | integer | 7 | `/audit-knowledge` |
| `auto_capture` | `true` \| `false` | true | `/extract` |
| `active_knowledge_surfacing` | `true` \| `false` | true | `/prospect` Step 0.5, `/retrospect` Step 0.5 |
| `ticketing_plugins` | `tag:command` pairs | empty | `/audit-knowledge` |
| `projects_enabled` | `true` \| `false` | false | `/audit-knowledge`, `/context` |
| `projects_list` | `tag:path` pairs | empty | `/context`, `/audit-knowledge` |
| `projects_promotion_threshold` | integer ≥ 1 | 2 | `/audit-knowledge` |
| `explanatory_plugin` | `true` \| `false` | (detected by `/aria-setup`) | `/extract` |

### Parse-tolerated by cowork (consumed by aria-knowledge only)

Cowork **accepts these fields without error** if they appear in `aria-config.md` (so a shared schema doesn't break), but does not read or act on them. They exist for aria-knowledge's hooks and the codemap/stitch skill family that cowork excludes per ADR 005.

| Field | Why parse-tolerated in cowork |
|---|---|
| `critical_paths` | Read by aria-knowledge's `pre-edit-check.sh` hook; cowork has no hook layer |
| `auto_load_project_context` | Read by aria-knowledge's `session-start-check.sh` hook |
| `codemap_staleness_threshold_days` | Read by aria-knowledge's CODEMAP staleness logic; cowork excludes `/codemap` per ADR 005 |
| `stitch_staleness_threshold_days` | Read by aria-knowledge's STITCH staleness logic; cowork excludes `/stitch` per ADR 005 |
| `projects_remotes` | Read by aria-knowledge's `session-start-check.sh` hook for remote-aware project resolution |
| `projects_groups` | Read by aria-knowledge's `/distill` and `/stitch`; cowork excludes both per ADR 005 |

A field being parse-tolerated does **not** mean cowork errors silently — it means cowork's `/audit-config` and `/aria-setup` skip the field during validation cascades (5d Wizard scope; 5b parse-tolerance principle).

### Format rules (cross-plugin)

- Each key starts at column 1, no indentation, exact name match
- Values unquoted: `knowledge_folder: /path` not `"/path"`
- Empty values: bare `key:` only — `null` / `""` / `none` / `[]` are parsed as literal strings
- Booleans: lowercase `true` / `false` only (not `True`, `yes`, `1`)
- Cadences and integers: bare digits, no units
- `last_setup_version`: bare semver (`0.3.0`), no `v` prefix, no quotes
- `tag:value` pair fields: no spaces around `:` or `,`; tags may not contain `:` or `,` (parser delimiters)
- `ticketing_plugins` command values: bare names without leading `/` (the audit prepends the slash)
- No blank lines between frontmatter entries

## `/aria-setup` wizard scope

Per the locked scope decision (item #5d option ii), cowork's `/aria-setup` prompts only for fields cowork consumes. The other fields are parse-tolerated but not surfaced in the wizard — to set them you can either:

- Run `/setup` from aria-knowledge's side (writes to `~/.claude/aria-knowledge.local.md`)
- Hand-edit `aria-config.md` directly

This keeps cowork's wizard focused and prevents UX noise from fields with no cowork consumer.

## Invalid-value fallback

| Field | Invalid → falls back to |
|---|---|
| `active_knowledge_surfacing` | `true` (active mode is the safe default) |
| `auto_capture` | `true` |
| Cadence integers | aria-knowledge's defaults (7/14/30 days) where applicable; cowork honors aria-knowledge's defaults for cross-plugin consistency |
| Other parse-tolerated fields | Silently ignored (no fallback needed; cowork doesn't read them) |

## Hand-editing checklist

Before saving manual edits to `{knowledge_folder}/aria-config.md`:

1. Keys at column 1, no indentation
2. No quotes on values; no `null` / `""` for empty
3. `tag:` keys consistent across `projects_list`, `ticketing_plugins`, etc. (the same tag means the same project everywhere)
4. Re-run `/aria-setup` afterward — Step 7b round-trip verification catches formatting issues before the next session does
5. If you also use aria-knowledge, keep `knowledge_folder` synchronized between the two plugins' config files

## Related

- [README.md](README.md) — cowork plugin overview
- [QUICKSTART.md](QUICKSTART.md) — first-three-sessions guide for cowork (lands at Stage F)
- [`aria-knowledge`'s CONFIG.md](https://github.com/mikeprasad/aria-knowledge/blob/main/plugin/CONFIG.md) — the schema source-of-truth; cowork's CONFIG.md mirrors this with cowork-specific Read-by annotations
- ADR-002 (shared schema with additive-only deprecation window)
- ADR-008 (persistent-grant + default-path attached-folder pattern)
- ADR-010 (default-path + aria-config.md as cross-surface schema bridge)
