# Design: Clippings Graduate to References (Step 2f revision)

**Date:** 2026-06-21
**Status:** Design — pending /prospect, then writing-plans
**Scope:** `plugin-claude-code` only (Cowork parity filed separately)
**Author:** mipr

## Problem

`intake/clippings/` is currently a transient scratch buffer. The shipped `/audit-knowledge` **Step 2f: Review Clippings** mines a clipping for knowledge, promotes the distilled bits to the backlogs, then **ledger-clears (deletes) the source**. There is no path to preserve the verbatim source as a durable, citable reference.

Mike's intent: everything dropped into `intake/clippings/` should be **mined for knowledge AND have its verbatim source preserved into `references/`** — clippings become a durable-source on-ramp, not throwaway scratch.

## Decisions (locked during brainstorm 2026-06-21)

1. **Graduate is the DEFAULT and ONLY processing disposition** (Approach C, then tightened). The Step 2f menu becomes **Graduate (default) / Skip**. The old "mine-and-discard the source" path is **removed entirely** — there is no deliberate source-discard. (Skip still defers an uncertain clip to the next audit.)
2. **Two-tier reference layout:**
   - **Verbatim full source** → `{knowledge_folder}/references/sources/{file}.md` (raw artifact, preserved whole).
   - **Mined reference-type fragments** → top-level `{knowledge_folder}/references/` (curated, smaller, independently `/context`-findable notes).
   - This split is what makes "mine all six buckets including references" safe: the whole source and its fragments live in distinct tiers rather than colliding in one namespace.
3. **Mine all six buckets** (insights, decisions, feedback, project context, references, ideas) — not a reduced set. Insights/decisions/feedback/ideas route to their normal backlogs; reference fragments become top-level `references/` notes.
4. **Ledger as `graduated`**, not deleted. Write a `REMOVED.md` entry recording `disposition: graduated` + the `references/sources/` destination, preserving the "where did clipping X go?" archive trail symmetric with other dispositions. (The source isn't lost — `git mv` relocates it.)
5. **Tags derived from content + confirmed.** The audit proposes tags (matched against existing tag vocabulary, mirroring `/index`) and shows them for confirm/edit before writing frontmatter. If the clipping already carries `/intake` frontmatter tags, carry them over; else derive. Confirm either way.
6. **No-minable-content case:** the source STILL graduates to `references/sources/` (archival value even with zero fragments). Ledger notes `graduated (source only, no fragments mined)`. This inverts the old "nothing extractable → reject+delete" branch.

## Three surfaces this change touches

This is not a Step-2f-only change. Introducing a new indexed location (`references/sources/`) requires three coordinated edits:

### Surface 1 — `/audit-knowledge` Step 2f (the behavior)

Rewrite Step 2f in `plugin-claude-code/skills/audit-knowledge/SKILL.md`:

- **Menu:** `1. Graduate (default)` / `2. Skip`.
- **Under Graduate, per clipping:**
  1. Derive tags from content → show for confirm/edit (carry over existing `/intake` tags if present).
  2. Write `Last updated:` + confirmed `tags:` frontmatter; `git mv` the whole clipping to `{knowledge_folder}/references/sources/{file}.md` (create `sources/` if absent).
  3. Mine all six buckets → append to backlogs. Reference-type fragments destined for top-level `references/` (distinct tier from the `sources/` raw file).
  4. Ledger: append to `archive/audit-{date}/clippings/REMOVED.md` with `disposition: graduated` + `references/sources/{file}.md` destination.
  5. No-minable-content: still graduate source; ledger `graduated (source only, no fragments mined)`.
- Update the Step 6 "Clippings" presentation section to reflect graduate-not-clear.

### Surface 2 — `/index` (so graduated sources are discoverable) — CONFIRMED MANDATORY

**Sourced during /prospect (2026-06-21):** `index/SKILL.md` Step 1 scans `approaches/`, `decisions/`, `guides/ (recursive — includes subdirectories)`, `references/`. Only `guides/` carries the recursive annotation — `references/` is scanned **flat (top-level only)**. Therefore `references/sources/*.md` is **invisible to `/index` today**, and graduated sources would sit unindexed (the exact gap this work exists to avoid). This is not "confirm/maybe" — it is a required edit.

**The edit:** add the `(recursive — includes subdirectories)` annotation to the `references/` line in `index/SKILL.md` Step 1, mirroring the existing `guides/` idiom, so the indexer walks `references/sources/`.

### Surface 3 — `references/README.md` + convention (TEMPLATE ONLY)

Document the two tiers in the **plugin template's** `references/README.md` only:
- `references/sources/` — verbatim graduated clippings (raw artifacts; preserved whole).
- top-level `references/` — curated fragments / notes / research docs.

**Scope resolved during /prospect (2026-06-21):** update the plugin template `references/README.md` ONLY. The user's live `knowledge/references/README.md` is user-owned (file-class model — never auto-synced from template changes) and is explicitly OUT of scope for this change; Mike updates it separately if/when desired (or `/setup` surfaces the template diff).

## Components & data flow

```
intake/clippings/{file}.md
        │  (Step 2f: Graduate)
        ├─► derive+confirm tags ─► write frontmatter ─► git mv ─► references/sources/{file}.md   [whole source, indexed]
        ├─► mine 6 buckets:
        │       insights/decisions/feedback/ideas ─► intake backlogs ─► (promote to approaches//memory)
        │       reference fragments              ─► intake backlogs ─► (promote to top-level references/)   [curated notes, indexed]
        └─► ledger ─► archive/audit-{date}/clippings/REMOVED.md  (disposition: graduated, dest path)
```

## Corpus-schema is canonical now; Cowork step-port is deferred (per ADR-013 + ADR-014)

This change introduces a new **output-schema** element to the shared knowledge corpus: the `references/sources/` destination directory and the `graduated` ledger disposition. Per **ADR-013** (Cowork-modified skills produce schema-identical outputs — *input-discovery is per-surface; output-schema is per-corpus*), this schema is **canonical across the corpus the moment it ships in Code**, regardless of which plugin writes it. Any future Cowork clippings step MUST graduate to the same `references/sources/` path with the same `graduated` ledger shape — it may NOT invent a divergent destination.

Per **ADR-014** (bidirectional feature flow), clippings-graduation is a **row-3 (bidirectional)** capability: it solves a corpus-level workflow that benefits both Code and Cowork users. aria-knowledge ships first (schema source-of-truth per ADR-014 step 2); Cowork ports later in a parity-sync release. So Cowork parity is a *sanctioned, scheduled* follow-up, not an open question.

What is **deferred** (the step port), not the schema:

- **Cowork-port parity:** `plugin-claude-cowork` has NO clippings step at all (its Step 2 sequence ends at 2d — missing both 2e Subagent Captures and 2f Clippings). Porting the clippings step to Cowork is a separate, larger job (porting a missing feature; Cowork lacks Bash file ops, so the `git mv` graduation must become a copy-or-MCP equivalent per ADR-013's input-discovery-diverges rule). Filed as a follow-up idea. **The `references/sources/` schema this spec defines is what that future port must conform to.**
- **antigravity / openai-codex ports** (currently 2.30.x, version-skewed behind code's 2.35.0): step-port out of scope; follow their normal sync cadence; same corpus-schema applies when they port.

## CHANGELOG attribution (per ADR-014)

Code-port CHANGELOG notes this as an aria-knowledge-originated corpus-schema addition. When Cowork ports the step, its CHANGELOG references this spec as the schema source.

## Versioning

Code-port plugin version bump on implementation (minor — additive feature with a behavior change to clippings default). `last_setup_version` reconcile happens on the user's next `/setup`, not here.

## Testing / validation

- Dry-run Step 2f against a fixture clipping: confirm source lands whole in `references/sources/` with frontmatter, fragments append to backlogs, ledger entry written `graduated`.
- No-minable-content fixture: confirm source still graduates, ledger notes source-only.
- `/index` run after graduation: confirm the `references/sources/` file appears in `index.md` under its tags.
- README renders the two-tier explanation.

## Open questions for /prospect

- Does `/index` currently glob `references/*.md` non-recursively (would miss `sources/`)? Verify the exact glob and whether `references/sources/` needs an explicit walk.
- Does any OTHER skill read `references/` with a flat-glob assumption that `sources/` would break (e.g. `/context`, active-surfacing hooks)? Enumerate reference-readers before shipping.
- Frontmatter on graduated sources: does the existing `references/` frontmatter schema (`Last updated:` + `tags:`) suffice, or should graduated sources carry provenance (original clip source URL/date) too?
