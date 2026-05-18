# Archive

Retired or superseded content. When a rule, approach, or decision is replaced, move the old version here and add a pointer from the original location. Nothing is deleted — only archived.

---

## Two archive shapes

### General archive (everything else)

`archive/` itself holds free-form retired content. Move old files here and add a pointer from the original location ("see archive/{filename}.md for the v1 version"). No naming convention beyond the original filename. This is the catch-all for ad-hoc archival.

### Audit-cohort archive (produced by `/audit-knowledge` and `/backlog clear`)

`archive/audit-{YYYY-MM-DD}/` and `archive/backlog-cleared-{type}-{YYYY-MM-DD-HHmmss}.md` are structured archive surfaces. They are the **canonical preservation surface for items the audit moves or removes** — git is no longer assumed as a recovery path (works for non-git knowledge folders too).

Both plugins (aria-knowledge and aria-cowork) write to this same shape. Cross-plugin readability is guaranteed: any item produced by one plugin's audit can be read and disposition-checked by the other.

---

## Audit-cohort archive — `archive/audit-{YYYY-MM-DD}/`

Created by `/audit-knowledge` runs. One folder per audit date. Contains:

- `MANIFEST.md` — cohort summary + per-item disposition list
- Individual archived files preserving full bodies of items the audit moved (with disposition-attribution frontmatter)
- `pre-compact-captures/` subfolder (if any pre-compact snapshots were archived)

### MANIFEST.md schema

```yaml
---
audit_date: 2026-05-18
plugin_version: aria-cowork@0.3.0   # OR aria-knowledge@2.17.0 — identifies the audit's runtime
total_items: 47
touched: 12      # examined, no disposition change
moved: 23        # Accept-with-full-body-move
archived: 12     # Accept-summary / Reject / Reclassify / Bundle
deferred: 0      # Defer disposition (no-op)
---

# Audit Manifest — 2026-05-18

## Moved (to destination, body preserved)
- 2026-04-18-mipr-x-y-z.md → _project-knowledge/2026-04-18-mipr-x-y-z.md (accept)
- ...

## Archived in this folder
- 2026-04-22-mipr-foo.md (dismissal-reason: "covered by existing rule")
- 2026-04-23-mipr-bar.md (reclassified-to: insights-backlog)
- 2026-04-24-mipr-baz.md (bundled-into: 2026-05-15-mipr-cluster-baz.md)
- 2026-04-25-mipr-summary-target.md (demoted-to: cross/notes.md, summary-only)

## Touched (examined, no disposition change)
- 2026-04-26-mipr-keepers.md
- ...
```

### Disposition-attribution frontmatter (on archived files)

Files moved into `archive/audit-{date}/` carry frontmatter explaining WHY they were archived:

| Field | Used when |
|---|---|
| `dismissal-reason: "<text>"` | Reject disposition — why this item didn't make it |
| `demoted-to: "<destination>"` | Accept-summary-only — item moved to destination as summary, full body archived |
| `reclassified-to: "<target-backlog>"` | Reclassify disposition — moved to different staging backlog |
| `bundled-into: "<merged-filename>"` | Bundle disposition — this was a source in a bundle merge |
| `originally_at: "<source-path>"` | Cross-project pattern Remove (Step 5e) — moved file's audit trail |

These fields are the audit trail. Future audits or manual inspection can reconstruct what happened.

### Verify-no-loss check

Before any **Accept disposition's move-to-destination**, the audit inventories the original item's substantive content across four facets:

| Facet | What counts |
|---|---|
| **Why** | The motivating problem, scenario, or pain |
| **Motivation** | The driving force / urgency / stakes |
| **Implementation** | Concrete proposed change, code path, mechanism |
| **Source** | Origin context — session, conversation, doc, ADR, etc. |

Three verdicts based on destination coverage:

- **Full coverage** → move to destination
- **Insufficient coverage** → archive alongside (don't move; full body preserved in archive)
- **Partial coverage** → surface options to user, let them decide

The rule is "no useful substantive content is lost," **not** "body byte-identical." Editing, restructuring, and compression during the move are fine if substantive coverage holds.

### Ledger-vs-full-archive policy

| Content shape | Archive treatment |
|---|---|
| **Derived content** (canonical source exists elsewhere) | **Ledger pattern** — write `REMOVED.md` with pointers, body removed |
| **User-authored content** (no canonical source elsewhere) | **Full archive** — body preserved verbatim in archive |

**Plugin-specific divergence on pre-compact snapshots:**
- aria-knowledge auto-creates snapshots via its `pre-compact-check.sh` hook; the canonical source is `~/.claude/projects/{cwd-encoded}/{session-id}.jsonl`. Snapshots there use the **ledger pattern** — REMOVED.md with `canonical_source_pattern: "~/.claude/projects/{...}"` pointers.
- aria-cowork has no canonical-jsonl equivalent (no hook layer; Cowork transcript MCP surface is limited). Snapshots produced by cowork's `/snapshot` are full-archived — they ARE the canonical record.

Both produce structurally-compatible `audit-{date}/` cohorts. The disambiguator is whether the archived snapshot has a `canonical_source_pattern` frontmatter field.

### Same-day collision handling

If both plugins run `/audit-knowledge` on the same day, they write to the same `archive/audit-{date}/` cohort. The cohort is **merged**, not duplicated:

- The second invocation appends to the existing `MANIFEST.md` (extends `Moved`/`Archived`/`Touched` lists; increments counts in frontmatter)
- Adds a `## Appended {timestamp} by aria-cowork@{version}` section header so cohort authorship is traceable
- Filename collisions inside the folder are vanishingly rare (per-idea filenames are date-stamped + slugged + unique)

Same-day audits are treated as **one coherent cohort**, not two parallel ones. The merge logic is idempotent — re-running the same audit produces the same MANIFEST state.

---

## `/backlog clear` archive — `archive/backlog-cleared-{type}-{YYYY-MM-DD-HHmmss}.md`

Single file (not folder) per `/backlog clear` invocation. Each invocation produces a fresh archive file with a timestamped filename.

### Frontmatter

```yaml
---
archived_at: 2026-05-18T14:30:00
source_backlog: insights-backlog
cleared_through_date: 2026-05-10
entry_count: 23
reason: /backlog clear user-invoked
plugin_version: aria-cowork@0.3.0
---
```

Body contains the verbatim entries that were cleared.

**Full archive (not ledger):** `/backlog clear` operates on user-authored backlog entries with no canonical source elsewhere. Bodies are preserved verbatim.

---

## User-override clause (all never-delete sites)

If the user explicitly approves a destructive bypass via phrases like *"delete without archiving"*, *"really delete this"*, *"skip the archive"*:

| Property | Rule |
|---|---|
| **Permission scope** | One-off per invocation. Does NOT flip default for subsequent files in same audit |
| **Surface requirement** | Before confirming, the skill MUST surface what would have been preserved (filename, key content excerpt, archive location it would have written to) so the user has full informed consent |
| **Legitimate use cases** | Sensitive content the user doesn't want traceable, archive-growth aversion, test/spam entries that don't deserve archive space |

The override exists but the **default safety floor is archive-on-disk**. Users opt out per-item, not globally.

---

## Cross-plugin schema guarantee

Both aria-knowledge and aria-cowork:
- Write to the same `archive/audit-{date}/` and `archive/backlog-cleared-*.md` paths
- Use the same MANIFEST.md schema (only `plugin_version` field varies by writer)
- Use the same disposition-attribution frontmatter taxonomy
- Apply the same verify-no-loss check and user-override clause semantics
- Apply ledger-vs-full-archive policy based on content shape (with the snapshot-source divergence noted above)

A user running both plugins against the same knowledge folder sees one coherent audit history across surfaces.
