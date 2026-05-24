<!-- plugin-managed: /setup diffs this file on plugin updates. Customize it freely — your edits appear as diff prompts on future `/setup` runs (this is how you receive plugin improvements). For customizations you want ARIA to leave alone, use `rules/user-rules.md` or `LOCAL.md` (both user-owned, never diffed). See OVERVIEW.md "Plugin-Managed vs User-Owned Files" for details. -->

# Claude Code Enforcement Mechanisms

How to ensure Claude follows a process, rule, or constraint. Ranked from softest to hardest enforcement.

---

## Soft Enforcement (Prompt-Driven)

These rely on Claude processing a prompt and choosing to comply. They're auditable but not guaranteed.

### 1. CLAUDE.md Rules
Rules loaded into context at session start. Persistent across the session but can drift as context gets long or compaction removes earlier conversation that reinforced them.

**Reliability:** Moderate. Works well for broad conventions. Can be forgotten under context pressure or in long sessions.

**Best for:** Coding conventions, workflow preferences, project context, architectural rules.

### 2. Hook Prompts (PreToolUse / PostToolUse)
Inject context at tool boundaries — before or after every Edit, Write, Bash, etc. Fires every time the matched tool is used. The prompt appears as a system reminder that Claude processes during its response.

**Reliability:** High for timing (always fires), moderate for compliance (still prompt-based). More reliable than CLAUDE.md rules because the reminder appears at the moment of action, not just at session start.

**Best for:** Decision frameworks, scope checks, impact assessments — anything that needs to happen at the point of execution.

### 3. Required Output Format
The hook prompt specifies an exact output format with labeled fields that Claude must produce. Each field forces a reasoning step to happen visibly. Missing or incomplete output is visible to both Claude and the user.

**Reliability:** Highest soft enforcement. The output creates an auditable contract — if the format is wrong or missing, it's immediately visible. The accountability loop (Claude sees its own output, user sees it too) is what makes it effective.

**Best for:** Multi-step decision processes where skipping a step causes errors. The change decision framework (Rule 22) uses this approach.

**Key insight:** If Claude isn't required to output its reasoning, steps may be skipped. The output IS the enforcement mechanism — not just a record of it.

**Why the full format fires on every edit (not compressed after the first):** Context compaction erases earlier conversation — including any prior hook injection that contained the full template. A "full on first edit, short thereafter" model would work within a single pre-compaction window, then silently degrade after compaction when Claude loses the reference. ARIA's change decision framework trades ~11K tokens/session of overhead for reliability that survives compaction. The full format is not redundancy — it's the only way to guarantee the framework still applies to edit #40 after compaction happened at edit #25.

---

## Hard Enforcement (System-Level)

These block actions programmatically. Claude cannot override them.

### 4. Hook Scripts That Block
A PreToolUse hook can return an error or rejection that prevents the tool from executing. Unlike prompt-based hooks, these actually stop the action — Claude must adjust its approach.

**Reliability:** Very high. The tool call is rejected at the system level.

**Best for:** Preventing specific dangerous operations (e.g., blocking writes to certain files, preventing force pushes).

**Not currently used** in this project — all hooks are prompt-based. Available if needed.

### 5. Permission Deny Lists
Configured in `settings.json` under `permissions.deny`. These block tool execution at the Claude Code system level. Claude cannot bypass them even if instructed to.

**Reliability:** Absolute. System-level block.

**Best for:** Hard safety boundaries — destructive operations, sensitive file access, commands that should never be auto-approved.

---

## Choosing the Right Mechanism

| Need | Mechanism | Why |
|------|-----------|-----|
| "Follow this convention" | CLAUDE.md rule | Persistent context, broad applicability |
| "Think through this before every edit" | Hook prompt + required output | Fires at point of action, auditable |
| "Never do this" | Permission deny list | Absolute block, can't be overridden |
| "Check this after every edit" | PostToolUse hook + required output | Fires after action, catches scope creep |
| "Block this specific action" | Hook script that rejects | Prevents execution, forces adjustment |

## Layering

Mechanisms can and should be layered:
- CLAUDE.md states the rule (why it matters)
- Hook prompt enforces it at the moment of action (when to apply it)
- Required output format makes compliance visible (proof it happened)
- Deny list blocks the worst case (hard stop if all else fails)

The change decision framework (Rule 22) uses layers 1-3: the rule is in `working-rules.md`, the hooks fire on every edit, and the compact required output format forces every step to be visible.

**Rule 34 (plan-level framework application)** uses Layer 1 only at this stage — the rule text in `working-rules.md` plus discipline-emitted `[Rule 34]` markers when triggers fire. Hook enforcement (Layers 2-3) is deferred pending real-world calibration of trigger heuristics: which triggers fire most, where the rule helps vs annoys, and where the marker is routinely forgotten. Rule 22's own evolution validates this arc — text shipped first, hooks added once usage data clarified the trigger surface. See `change-decision-framework.md` "Plan-Level Application (Rule 34)" for the framework's plan-level application and marker format.

## Related
- [change-decision-framework.md](change-decision-framework.md) — the primary consumer of these enforcement patterns (Rule 22 implementation)
