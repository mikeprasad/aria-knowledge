---
description: "Quick lookup into working rules. Use when user says '/rules', '/rules 22', '/rules dependencies', 'look up rule about...', 'what rule covers...', or references a specific rule number. (Claude Code variant — bare-slash canonical when both ports loaded; see ADR-094.)"
argument-hint: "[number or keyword]"
allowed-tools: Read, Grep
---

# /rules — Quick Rule Lookup

Look up rules from both the plugin's `working-rules.md` and the user's optional `user-rules.md`.

## Runtime Gate (per ADR-094)

**Canonical resolution:** This is the Claude Code variant. When both `plugin-claude-code` and `plugin-claude-cowork` are loaded in the same session (most common in Claude Desktop), bare `/rules` resolves to this skill — aria-knowledge (Code) is the canonical owner of all 24 dual-port skills per ADR-094 §Part 1. The Cowork variant is namespaced-only: `/aria-cowork:rules`.

**Before Step 0:** Check that the `Bash` tool is available in this session. If `Bash` is NOT available (you are running in Claude Cowork or another non-Code runtime), surface the following notification and wait for explicit user confirmation:

> ⚠️ **Runtime mismatch — you invoked aria-knowledge's `/rules` from a non-Code runtime.**
>
> Behavior is largely the same in both runtimes (both look up `working-rules.md` + `user-rules.md`); for the Cowork-native variant (reads from the attached knowledge folder), use `/aria-cowork:rules`.
>
> **Use `/aria-cowork:rules` instead?** (`y` / `n`)

Wait for an explicit reply:

- **`y` / `yes`** — Use the `Skill` tool to invoke `aria-cowork:rules` with the same arguments the user provided to this invocation. Do not proceed with this skill's steps; the cowork variant takes over and runs to completion. This is the default-yes path — auto-redirect is the helpful action.
- **`n` / `no`** — Proceed with this (aria-knowledge) variant anyway despite the runtime mismatch. The user has explicitly opted in.
- **No response / any other reply** — Treat as "do not proceed" and exit cleanly without running either variant.

**This gate applies even when `mode = auto`** per ADR-094 §Part 3. Auto mode's "implicit-yes on all gates" rule is suspended for the runtime-mismatch check — auto trusts that the user invoked the correct variant, and this gate enforces that precondition. All other auto-mode gates remain bypassed. The friction cost is now low: on `y`, the auto-redirect runs the correct variant with the original args.

If `Bash` is available, proceed to Step 0.

## Step 0: Resolve Config

Read `~/.claude/aria-knowledge.local.md` and extract `knowledge_folder`. If the file doesn't exist, stop: "aria-knowledge is not configured. Run /setup to get started."

Set two rules file paths:
- **Plugin rules:** `{knowledge_folder}/rules/working-rules.md`
- **User rules:** `{knowledge_folder}/rules/user-rules.md` (optional — may not exist for users on pre-v2.8.1 setups)

If the plugin rules file doesn't exist, stop: "No working-rules.md found in your knowledge folder. Run /setup to repair the structure."

If the user rules file doesn't exist, proceed with plugin rules only — this is the normal state for users who haven't added any custom rules.

## Step 1: Parse Argument

Check what argument was provided:
- **No argument:** go to Step 2 (index mode)
- **Number with optional U prefix** (e.g., `22`, `U1`): go to Step 3 (lookup by identifier)
- **Keyword** (e.g., `dependencies`): go to Step 4 (search mode)

## Step 2: Index Mode

Read both files. Extract all rule headings (lines matching `### N. [title]` or `### UN. [title]`). Output a grouped list:

```
## Working Rules Index

### Plugin Rules (working-rules.md)
1. Scope tasks tightly, but keep the whole system in view
2. Let errors guide where you add context
...

### Your Rules (user-rules.md)
U1. Always run the linter locally before committing
U2. Test data lives in test/fixtures/, not scattered next to tests
...
```

If user-rules.md doesn't exist, omit the "Your Rules" section entirely. If user-rules.md exists but contains only the shipped sample rules (U1-U4 with the original sample text), note: "(Your Rules section contains only the shipped sample rules — replace them with your own.)"

## Step 3: Lookup by Identifier

Read both files (plugin rules always, user rules if present). Find the heading matching the requested identifier:
- **Plain number** (e.g., `22`) → search both files for `### 22.` AND `### U22.`
- **U-prefixed** (e.g., `U1`) → search user-rules.md for `### U1.`

For each match, extract the full rule text (heading through next heading or section end) and present it with a clear source label:

```
## Plugin Rule 22 — Follow the change decision framework
[full rule text]
```

or

```
## User Rule U1 — Always run the linter locally before committing
[full rule text]
```

**Collision handling:** If the same plain number matches in both files (e.g., user's `### 30.` collides with plugin's `### 30.`), present BOTH and warn:
> "Number collision: Rule 30 exists in both `working-rules.md` and `user-rules.md`. Consider renaming the user version with a `U` prefix to avoid this — see user-rules.md naming convention."

If no match in either file: "Rule [identifier] not found. Plugin has rules 1-[max plugin]; user-rules.md has [list of user rule identifiers, or 'no custom rules' if file missing/empty]. Run /rules to see the full index."

**Examples lookup (since v2.14.2):** After returning the rule body, also check for a user-authored example in `{knowledge_folder}/rules/user-examples.md`.

If `user-examples.md` exists, search for a heading matching `## Rule N` (where N is the requested plain-number identifier — examples currently target plugin rules only, not user rules). If found, extract the example body (heading through next `## Rule` heading or end of file) and append it to the output as a separate section:

```
## Plugin Rule 25 — Check secondary impact on every change
[full rule text]

---

## Example (from your user-examples.md)

## Rule 25 — Check secondary impact
[example body — Before / After / etc.]
```

If `user-examples.md` doesn't exist, or exists but has no matching `## Rule N` heading, omit the example section silently. This is the normal state for users who haven't authored examples for that rule yet.

Multiple examples for the same rule (e.g., two `## Rule 25` headings) are all returned in document order, separated by `---`.

## Step 4: Search Mode

Read both files. Search rule titles and bodies for the keyword. Return all matching rules with their full text, grouped by source:

```
## Search results for '[keyword]'

### Plugin Rules
[matching rules from working-rules.md]

### Your Rules
[matching rules from user-rules.md]
```

If no matches in either: "No rules match '[keyword]'. Run /rules to see the full index."

If matches in only one file, omit the empty section heading.
