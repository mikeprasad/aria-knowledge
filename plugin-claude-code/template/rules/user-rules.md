# Your Rules

**Last updated:** (update when you edit this file)

This file is for **your** custom rules — project-team conventions, personal working preferences, domain-specific guidelines. ARIA ships and maintains the core plugin rules in `working-rules.md`; this file is yours to own. ARIA never overwrites it, never diffs it, never touches it on `/setup` updates.

## What Belongs Here vs `intake/ideas/`

ARIA captures two kinds of "what should be different" signals during sessions — they route to different places:

- **Behavioral observations → HERE.** Patterns Claude has drifted into that you want to prevent in future sessions. *Examples:* "Claude keeps inventing framework labels like 'Batched'", "Claude skips post-edit scope checks on Bash appends", "Claude paraphrases my instructions when executing." These stay resident in ARIA, loaded as session-shaping context indefinitely.
- **Feature proposals / bug reports / design ideas → `intake/ideas/` (one file per idea).** Code, skill, or template changes you want to schedule. *Examples:* "`/setup` should distinguish user-ahead from user-diverged", "Hook matcher should cover Bash file-edit patterns", "Add `additional_signal_patterns` config field." These route out of ARIA to your external tracker (Linear, GitHub Issues, Jira) when ready to ship.

`/extract` auto-routes based on language signals — behavioral drift verbs ("invented", "spontaneously", "keeps doing") → here; feature-change verbs ("should", "could be better if", "missing handling") → a new file in `intake/ideas/`. If you're filing by hand, follow the same split. For ambiguous cases (an observation that is both a behavioral pattern *and* a code-change proposal), file in both with cross-references.

## Why a separate file?

The plugin's `working-rules.md` evolves — new rules get added, numbered sequentially. If you added your own rules directly to `working-rules.md`, every plugin update could create numbering collisions (your Rule 30 vs plugin's new Rule 30) and force painful manual reconciliation via `/setup` diffs.

This file solves that: `/setup` never touches it. You can add, retire, and renumber freely.

## Naming Convention (recommended)

Use a `U` prefix for your rule numbers — `U1`, `U2`, `U3`... — to clearly distinguish from plugin rules and avoid any temptation to collide with them. Any convention works, but this is the simplest.

Rule numbers are permanent IDs. When a rule is retired, keep the number and mark `[RETIRED]` — same convention as plugin rules.

## How they're used

- **`/rules` and `/rules [number]`** — the skill searches both `working-rules.md` and this file. Index mode shows them grouped separately.
- **CLAUDE.md** — typical pattern is `"See knowledge/rules/working-rules.md"` at the top of your project CLAUDE.md. Add a second pointer to `user-rules.md` if you want Claude to load your custom rules at session start too.
- **Enforcement** — plugin hooks only enforce Rule 22 (change decision framework). User rules are not hook-enforced; they're loaded context that shapes Claude's reasoning.

-----

## Sample Format

*(delete these samples once you've added your own rules)*

## Team Rules

### U1. Always run the linter locally before committing

Our pre-commit setup catches issues the CI lint doesn't, and vice versa. Running both locally before pushing prevents the "green locally, red in CI" surprise that eats time on red-light debugging.

**Origin:** YYYY-MM-DD — three commits in one day had to be force-reverted because CI lint caught issues a misconfigured local `.eslintrc` missed. Root cause was fixed; the rule remains to keep the habit.

### U2. Test data lives in `test/fixtures/`, not scattered next to tests

Consolidating fixtures makes refactors cheaper and prevents duplicate test data drifting into different shapes across files.

## Personal Conventions

### U3. Write explicit return types for exported functions

TypeScript can infer it, but inferred types on exported APIs change silently when the implementation changes. Explicit return types lock the contract and make breaking changes visible in diffs.

## Retired Rules

### U4. [RETIRED] Use `yarn` instead of `npm`

Retired YYYY-MM-DD — migrated to pnpm across the team. See `approaches/package-manager-migration.md`.
