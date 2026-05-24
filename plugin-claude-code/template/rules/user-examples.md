# Your Per-Rule Examples

**Last updated:** (update when you edit this file)

This file is for **your** project-specific before/after examples illustrating the rules in `working-rules.md`. ARIA ships and maintains the rule definitions; this file is yours to own. ARIA never overwrites it, never diffs it, never touches it on `/setup` updates.

## Why Examples Are User-Specific

Examples earn their illustrative value by being grounded in *your* context — file paths, commits, dates, project conventions that are real to you. A "universal Rule N example" tends to drift back toward being part of the rule itself, OR a separate canonical pattern (in `retrospect-patterns.md` / `prospect-patterns.md`).

That's why ARIA ships zero example content. The plugin defines the format and the discovery mechanism; you author examples grounded in your own work.

## How `/rules` Finds Your Examples

When you run `/rules N`, the skill reads this file and returns any example whose heading matches `## Rule N`. No forward-link maintenance in `working-rules.md` needed — discovery is automatic.

## Format

Use a `## Rule N` heading per example. Required sub-sections: `### Before` and `### After`. Everything else is optional — use whatever helps the example land.

**Required:**

- `## Rule N — {short title}` heading
- `### Before` with code or scenario showing the failure mode
- `### After` with code or scenario showing the rule applied

**Optional (use as helpful, omit otherwise):**

- `**Calibrated against:** {project / commit / date / incident}` — what makes this example real for you
- `### Why this example` — 1–2 sentences naming the load-bearing decision
- Inline citations to file paths, commits, deploys

## When to Add an Example

When you've shipped a fix or made a decision that vividly illustrates one of the rules — and future-you would benefit from seeing the before/after side-by-side. Don't force examples for every rule. Let them emerge from real cases.

-----

## Skeleton Template

*(replace this skeleton with your first real example, or delete it once you've added one above)*

## Rule N — (rule number + short title)

### Before
```language
// code that ignored or failed the rule
```

### After
```language
// code that applied the rule
```

**Calibrated against:** project / commit / date — what makes this example real for you
