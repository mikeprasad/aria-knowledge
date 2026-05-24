<!-- aria: user-owned. Edit freely; /setup will not diff-prompt on this file. -->

# Tag Aliases

Maps alternate names to canonical tags. `/context` resolves alias queries to
their canonical form before matching (`/context rn` → resolves to `react-native`
→ matches files tagged `react-native`).

Format: one alias per line, using the arrow notation:

```
- `<alias>` → `<canonical>`
```

The canonical name must be a tag that's actually used somewhere in your
knowledge folder. Aliases are unidirectional: querying the alias resolves to
the canonical, but querying the canonical does not match alias-only declarations.

Rules:
- **No chains:** `js` → `javascript`, `javascript` → `ecmascript` is invalid. Aliases must point directly to a canonical tag, not to another alias.
- **No collisions:** if an alias is also used as a tag on any file's `tags:` frontmatter, `/index` aborts with an error. Either remove the alias here or rename the tag in the file.
- **Resolution runs before project expansion:** if `seer` is an alias for project tag `ss`, querying `/context seer` resolves to `ss` and then expands relevant tags.

## Aliases

<!-- Add aliases below. Examples:
- `rn` → `react-native`
- `reactnative` → `react-native`
- `ts` → `typescript`
- `k8s` → `kubernetes`
- `kube` → `kubernetes`
-->
