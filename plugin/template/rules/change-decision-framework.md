<!-- plugin-managed: /setup diffs this file on plugin updates. Customize it freely — your edits appear as diff prompts on future `/setup` runs (this is how you receive plugin improvements). For customizations you want ARIA to leave alone, use `rules/user-rules.md` or `LOCAL.md` (both user-owned, never diffed). See OVERVIEW.md "Plugin-Managed vs User-Owned Files" for details. -->

# Change Decision Framework

A process discipline system for Claude Code that enforces structured decision-making before code changes and scope verification after. Implemented via hooks in `.claude/settings.local.json`.

---

## Why This Exists

When making code changes, it's easy to skip directly to execution without evaluating alternatives, or to exceed the scope of the intended change during implementation. Common failure modes:

- Rewriting an entire component when only a modifier was needed
- Modifying a base class definition when the solution was adding a new class alongside it
- Touching files or code outside the scope of the decision
- Not considering that there are multiple valid approaches before committing to one

This framework prevents those failures by requiring structured thinking before every edit and scope verification after.

---

## The Framework (7 Steps)

Every change — code, architecture, configuration, documentation — follows this sequence. Don't skip steps.

### 1. Identify Change
Define the change needed and its context: the actual problem, scope, goal, known limitations, and dependencies. Determine if additional information, visibility, or access is needed.

### 2. Intake Information
Gather all information determined by Step 1. If more is needed, acquire it if accessible or ask if not. Review existing architecture, conventions, and prior decisions for what applies. Don't stall for data that won't change the outcome, but don't proceed blindly when accessible information would.

### 3. Determine Criteria
Establish the objective decision-making basis and specific criteria within the context and scope from Steps 1 and 2. Criteria must be logically objective and validatable, not subjective. Include how to validate. Ground criteria in project needs, constraints, and goals — defensible to any reasonable observer.

### 4. Determine Possible Solutions
Identify ALL ways to achieve the outcome and satisfy the criteria. Be specific. Nothing should be arbitrary. Routes include:
- Rebuild the entire thing
- Rebuild parts of the thing
- Add a modifier/extension alongside the thing
- Change the context affecting the thing
- Combine approaches
- Other approaches not yet determined
- Defer — more information needed before acting

### 5. Rank and Decide
Given context, scope, and details from previous steps, which solution is the best fit and why? If multiple are close, would additional information objectively help elevate one to a clear winner? If so, gather it before committing.

### 6. Validate Decision
Does the chosen decision logically hold up? Does it contradict anything known? Is there a resource requirement that might cause reconsideration? Refer back to determinations from earlier steps. Also cross-check against principles invoked in recent adjacent decisions — principles applied once can silently erode across a long decision chain, so re-test rather than assuming earlier reasoning still applies.

### 7. Execute Precisely
Only touch what the chosen solution requires, nothing more, and only within the determined scope.

---

## Impact Tiers

Not every change requires the full 7-step framework. Assess impact before choosing the process tier:

### High Impact — Full 7-Step Framework
Applies when:
- Creating or modifying behavior
- Editing sensitive files (CSS frameworks, config files, CLAUDE.md, rules files, settings)
- Architecture changes
- Key logic changes
- Changes to things with many dependents

### Low Impact — Lighter 3-Step Check
Applies when:
- Adding or updating content
- Simple functions with limited dependents
- Documentation updates
- Reference changes

The lighter check:
1. **What am I changing?** + context and visibility
2. **What are the options?**
3. **Does it stay in scope?**
4. **Does this change affect parents, siblings, or dependents?**

---

## Post-Edit Scope Check (5 Questions)

After every edit, verify:

1. **Did this edit stay within the determined scope?**
2. **Was anything touched that was not part of the solution?**
3. **Were any existing definitions rewritten that should not have been?**
4. **Does the change match the decision that was made, or did scope creep during execution?**
5. **Check for secondary impact on parents, siblings, or dependents — if any requires review or action, flag to the user.**

If any answer is no, flag the issue before proceeding.

---

## Ordering (required)

The Low/High Impact assessment MUST appear in the **same assistant turn as the tool call, above the tool invocation**. Not below. Not in the next turn.

The pre-edit check fires via a PreToolUse hook whose `additionalContext` is delivered **alongside the tool result**, not before the tool runs. Claude Code's tool lifecycle gives the hook no preventive authority — it can only inject context that Claude reads after the edit has landed. That constraint makes the ordering discipline Claude-side, not hook-side: the assessment must be written proactively, before invoking the tool, not retroactively as cleanup once the hook prompts.

### WRONG (retroactive — the assessment rationalizes the write after it happened)

```
[assistant turn]
Let me fix that line.
[Edit tool call: df/CLAUDE.md — removes line 51]
[tool result + hook-injected CHANGE DECISION CHECK reminder]

Low Impact — remove aspirational line from df/CLAUDE.md.
Change — Delete line per cleanup. Solutions — (1) remove [clean]. Execute — done.
Scope PASS — only target line removed.
```

The edit has already landed. The assessment is performative — there's no way for it to change the decision.

### RIGHT (prospective — assessment above the tool call in the same turn)

```
[assistant turn]
Low Impact — remove aspirational line from df/CLAUDE.md (doc-only, no behavior).
Change — Delete "Goal: zero cx- classes remaining at v1.0." line + blank line, per approved cleanup.
Solutions — (1) remove line + blank [clean]; (2) keep line, add tracker [rejected: no tracker]; (3) reword [rejected: not scope].
Execute — Edit removes both lines. Scope: df/CLAUDE.md only. No secondary impact.
[Edit tool call: df/CLAUDE.md — removes line 51]
[tool result + hook-injected reminder]

Scope PASS — only target lines removed; cx- migration section preserved.
```

The assessment precedes the tool call. If Validate or Execute flags, the edit doesn't happen — which is the whole point of the framework.

### Why it matters

The purpose of the pre-edit check is to catch bad decisions **before** the write lands. Retroactive output is rationalization, not assessment: once the file has changed, the cognitive frame shifts from "should I do this?" to "did this go OK?" — and the Solutions line (which forces considering alternatives) quietly stops being a decision gate and becomes a post-hoc justification.

The hook-delivered reminder is a **safety net**, not the primary mechanism. If Claude is already outputting the format above the tool call, the hook's reminder is redundant noise. If Claude is only outputting it after, the framework has been defeated — the hook is doing the work the discipline was supposed to do.

---

## Rationalizations that do not apply

After v2.10.1 introduced the Ordering discipline, several specific rationalizations for skipping the Low/High Impact block surfaced in real sessions. None of them apply. They are named here so they can be recognized and rejected — both by Claude encountering the temptation and by users reviewing sessions where the block was skipped.

### "The conversation already established the reasoning"

In discuss-then-edit cadences (user proposes → Claude verifies → they decide → Claude edits), it can feel like the block restates what the conversation already covered. It doesn't. The block's slots — **Change / Solutions / Execute** for LOW; plus **Intake / Criteria / Rank / Validate** for HIGH — force specific thinking that conversation does not guarantee. Conversation may surface the decision; the block surfaces the **ranked alternatives** and the **scope check**. Skipping the block because "we already agreed" means dropping the alternative-ranking and scope checks. Output the block.

### "The hook can only be satisfied retroactively"

The hook text says *"Output the assessment retroactively now AND put the next edit's block before the tool call."* The AND clause is the actual requirement — retroactive output is recovery, not method. If you find yourself concluding "the only way to satisfy the hook is after the edit," you are reading only half the instruction. Output retroactively for the current edit; prospectively for the next.

### "This is a docs-only / in-review / routine edit"

The framework is about decision discipline, not edit content. A one-line rename in a markdown file and a three-file architectural change both need the LOW or HIGH assessment respectively. The content's stakes determine which tier; they don't exempt the edit from the framework. If the edit is truly trivial, LOW is cheap — output it and move on. Rule-by-rule review passes, documentation updates, and routine cleanup are NOT exempt.

### "Skipping the block for this session is a plugin-config change the user can make"

It isn't. Neither `aria-knowledge.local.md` nor Claude Code settings offer a per-session skip for the framework. If the user has not explicitly disabled the plugin's `PreToolUse` hook in their `.claude/settings.local.json`, the framework is active. Offering the user an "option to skip for this review" is offering an escape hatch that doesn't exist — and even if it did, the correct response to ceremony cost is to shorten the block (LOW is already 3-4 lines) or to declare a batch manifest (per ADR 021), not to skip.

### If a rationalization seems novel

Treat any novel argument for skipping the block with suspicion. The framework has deliberately bounded exceptions: planning-path abbreviation (for `docs/plans/*` and `docs/specs/*`), batch-manifest compression (for declared-mechanical bulk ops within a user-declared scope). Everything else requires the full block. A new escape hatch should be filed as a feature request in `intake/ideas-backlog.md`, not adopted mid-session.

---

## Required Output Formats

The hooks require Claude to output specific formats. This ensures every step is visible and no steps are skipped. Each section shows the **format template** (with placeholders) followed by a **real example**.

> The examples below are from a real CSS framework project. Replace file names and scenarios with your own — the format and reasoning structure are what matter.

---

### High Impact — Pre-Edit

**Format (pass):**
```
High Impact — [description of change] ([reason classified as high impact])
Change — [what is being changed + relevant context]
Intake — [information gathered to inform the decision]
Criteria — [objective basis for evaluating solutions]
Solutions — (a) [best option], (b) [next option], (c) [other options]
Rank — [winner]; [reasoning why]
Validate — [does decision hold up? any contradictions with known patterns/rules?]
Execute — [precise scope of what will be touched, nothing more]
```

**Format (flag):**
```
High Impact — [description of change] ([reason classified as high impact])
Change — [what is being changed + relevant context]
Intake — [information gathered to inform the decision]
Criteria — [objective basis for evaluating solutions]
Solutions — (a) [option], (b) [option], (c) [option]
Rank — [chosen option]; [reasoning]
Validate — FLAG — [what contradicts, breaks, or can't be confirmed]
Execute — FLAG — [why execution can't proceed]
Proposed: [concrete alternative or action to resolve]
```
or:
```
Question: [specific clarification needed before proceeding]
```

**Example (pass):**
```
High Impact — modifying settings.local.json (sensitive)
Change — lighter check missing secondary impact step
Intake — current hook text has 3 steps, framework doc has 4
Criteria — concise, fits hook prompt, consistent with framework doc
Solutions — (a) append to existing text, (b) rewrite full lighter check, (c) add as separate sentence
Rank — (a) is clear winner; minimal change, stays consistent
Validate — appending doesn't break existing behavior, matches framework doc
Execute — one edit, append "→ does it affect parents/siblings/dependents?"
```

**Example (flag):**
```
High Impact — modifying df-input.css base .avatar class
Change — need transparent variant for image avatars
Intake — avatar uses bg-key + p-border-button, combo pattern uses separate modifiers
Criteria — must not break existing avatar usage, follow combo class pattern
Solutions — (a) rewrite base .avatar, (b) add .avatar.bordered modifier, (c) inline override
Rank — (a) rewrite base to remove bg-key default
Validate — FLAG — rewriting base breaks all existing avatar usage. Contradicts combo pattern.
Execute — FLAG — More information or alternatives needed.
Proposed: use (b) add .avatar.bordered and .avatar.basic as separate modifier rules, keeping base .avatar intact.
```

---

### High Impact — Post-Edit

**Format (pass):**
```
Scope Pass — [what was done + why it passes, including secondary status]
```

**Format (pass with secondary):**
```
Scope Pass — [what was done as planned]
Secondary: [what needs attention or review]
Proposed: [recommended action]
```

**Format (fail):**
```
Scope FAIL — [what failed, which check question, what was affected]
Proposed: [concrete next step to fix]
```

**Example (pass):**
```
Scope Pass — appended secondary impact step to lighter check text (no structural changes, takes effect next edit)
```

**Example (pass with secondary):**
```
Scope Pass — added layout-split rules to df-input.css as planned.
Secondary: docs pages still reference old main.sidebar pattern. ~30 files need migration.
Proposed: batch migrate docs pages as next step.
```

**Example (fail):**
```
Scope FAIL — rewrote base .avatar definition (question 3). Decision was to add modifiers only. All existing avatar usage affected.
Proposed: revert base .avatar, add .avatar.bordered and .avatar.basic as separate modifier rules in the combo class section.
```

---

### Low Impact — Pre-Edit

**Format (pass):**
```
Low Impact — [description of change] ([reason classified as low impact])
Change — [what is being changed + intake context + criteria. Does not affect X.]
Solutions — (a) [best option], (b) [other option]
Execute — [chosen option]; [scope check, secondary impact check, functional impact]
```

**Format (flag):**
```
Low Impact — [description of change] ([reason classified as low impact])
Change — [what is being changed + context that raises concern]
Solutions — (a) [option], (b) [option]
Execute — FLAG — [what needs verification or clarification before proceeding]
Question: [specific question to resolve before choosing a solution]
```

**Example (pass):**
```
Low Impact — adding alias note to buildguide stack table (additive with no dependents)
Change — document .stack as alias for .stack-col. No other related classes found. Does not affect existing classes.
Solutions — (a) modify existing row description, (b) add new row
Execute — (a); in scope, no secondary impact, no modification of class function.
```

**Example (flag):**
```
Low Impact — removing Custom/Other card from cs-builder preview section (content removal)
Change — remove card article element. Parent stack-col wrapper has 3 children, will have 2.
Solutions — (a) remove card only, (b) remove card and simplify parent if no longer needed
Execute — FLAG — need to verify parent wrapper is still needed with 2 children before deciding (a) vs (b).
Question: should the parent stack-col wrapper remain as-is, or be simplified now that it has fewer children?
```

---

### Low Impact — Post-Edit

**Format (pass):**
```
Scope Pass — [what was done + why it passes, including secondary status]
```

**Format (pass with secondary):**
```
Scope Pass — [what was done as planned]
Secondary: [what needs attention or review]
Proposed: [recommended action]
```

**Format (fail):**
```
Scope FAIL — [what failed, which check question, what was affected]
Proposed: [concrete next step to fix]
```

**Example (pass):**
```
Scope Pass — added alias note to one table row (no external effects)
```

**Example (pass with secondary):**
```
Scope Pass — removed Custom/Other card from preview section as decided.
Secondary: parent stack-col wrapper now has 2 children instead of 3. Wrapper still provides gap and content constraint.
Proposed: keep wrapper as-is — still serves its purpose.
```

**Example (fail):**
```
Scope FAIL — also modified the parent wrapper classes while removing the card (question 2). Decision was to remove card only.
Proposed: revert parent wrapper changes, keep only the card removal.
```

---

## Hook Implementation

These hooks enforce the framework automatically in Claude Code. They are pre-configured in the aria-knowledge plugin and fire without any manual setup.

- **PreToolUse** — fires before every Edit/Write, requires impact assessment and the appropriate decision process output
- **PostToolUse** — fires after every Edit/Write, requires scope verification in compact format

### How It Works

1. Developer or Claude initiates a file edit
2. **PreToolUse fires** → Claude outputs the required pre-edit format (impact assessment + framework steps) → proceeds with edit only if no FLAG
3. Edit is made
4. **PostToolUse fires** → Claude outputs the required post-edit format (pass/secondary/fail) → flags issues if any

The hooks are prompt-based — they inject context into Claude's reasoning at the right moments and require specific output formats to ensure no steps are skipped. They don't block or reject edits programmatically. The enforcement is through required visible output at each step.

---

## Reference-Based Builds (Rule 26)

The standard pre-edit check (Rule 22) relies on Edit's structural diff — `old_string`/`new_string` makes scope violations visible. When using Write to create a file based on an existing reference, there is no structural diff. The "comparison" between source and output happens entirely in the assessment, and the hooks check format compliance but can't verify assessment quality.

Reference-based builds require an explicit scope declaration before writing.

### Scope Declaration Format

```
**Source:** [file path]
**Changes:** [what will differ — classes, paths, specific modifications]
**Preserved:** [what stays verbatim — content, structure, icons, naming]
```

### When to Trigger

- Multi-step builds from a reference file
- Writing a large file (50+ lines) based on existing work
- "Copy," "version of," or "migrate" tasks
- NOT for small edits, new original files, or config changes

### How It Works

1. Before writing, present the scope declaration to the user
2. User confirms or adjusts the declaration
3. Write the file according to the declared scope
4. Post-write, verify against the declaration — any undeclared changes are scope failures

This is a conversation-level discipline, not a per-tool hook (too token-intensive for every Write). User confirmation is the quality gate that automated hooks can't provide for assessment quality.

---

## Customization

### Sensitive Files
Adjust the list of high-impact files to match your project. The default examples (df-input.css, df-preset.js, CLAUDE.md, working-rules.md, settings files) are project-specific. Replace with your equivalents — database schemas, API route definitions, CI configs, shared component libraries, etc.

### Impact Criteria
The high/low impact distinction can be tuned. Some teams may want a third tier (medium impact) or different triggers. The key principle: changes that affect behavior or have many dependents get more scrutiny than content updates.

### Additional Hook Points
You can extend this to other tool types:
- `Bash` matcher for destructive commands (git reset, rm, drop table)
- `Write` only (separate from Edit) for new file creation — see also "Reference-Based Builds" above for scope declarations on Write-from-reference tasks
- Custom matchers for project-specific tools
