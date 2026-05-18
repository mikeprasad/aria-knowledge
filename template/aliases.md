<!-- aria: user-owned. Edit freely; /aria-setup will not diff-prompt on this file. -->

# Tag Aliases

Maps alternate names to canonical tags. `/context` resolves alias queries to
their canonical form before matching (`/context meeting` → resolves to
`meetings` → matches files tagged `meetings`).

Format: one alias per line, using the arrow notation:

```
- `<alias>` → `<canonical>`
```

The canonical name must be a tag that's actually used somewhere in your
knowledge folder. Aliases are unidirectional: querying the alias resolves to
the canonical, but querying the canonical does not match alias-only declarations.

Rules:
- **No chains:** `meeting` → `meetings`, `meetings` → `sync-meetings` is invalid. Aliases must point directly to a canonical tag, not to another alias.
- **No collisions:** if an alias is also used as a tag on any file's `tags:` frontmatter, `/index` aborts with an error. Either remove the alias here or rename the tag in the file.
- **Resolution runs before project expansion:** if `kw-fc` is an alias for project tag `commonspace-feedback`, querying `/context kw-fc` resolves to `commonspace-feedback` and then expands relevant tags.

## Aliases

<!-- Cowork-flavored starter aliases (uncomment to use, or replace with your own):
- `meeting` → `meetings`
- `brief` → `briefing`
- `doc` → `docs`
- `action` → `action-item`
- `customer` → `client`
-->
