#!/usr/bin/env python3
"""Port plugin-claude-code skills into plugin-cursor-template/.cursor/rules/*.mdc."""

from __future__ import annotations

import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CODE_SKILLS = REPO / "plugin-claude-code" / "skills"
RULES_DIR = REPO / "plugin-cursor-template" / ".cursor" / "rules"
TEMPLATE_RULES = REPO / "plugin-claude-code" / "template" / "rules"

COMMANDS_MDC = RULES_DIR / "aria-commands.mdc"
AUDIT_MDC = RULES_DIR / "aria-audit.mdc"
CONTEXT_MDC = RULES_DIR / "aria-context.mdc"
RULE22_MDC = RULES_DIR / "aria-rule-22.mdc"

COMMAND_SKILLS = [
    "extract",
    "index",
    "backlog",
    "stats",
    "ask",
    "clip",
    "clip-thread",
    "intake",
    "extract-doc",
    "meeting-notes",
    "digest",
    "sync-decisions",
    "codemap",
    "distill",
    "stitch",
    "handoff",
    "wrapup",
    "prospect",
    "retrospect",
    "snapshot",
    "setup",
    "help",
    "audit-share",
]

AUDIT_SKILLS = ["audit-knowledge", "audit-config"]
CONTEXT_SKILLS = ["context", "rules"]

SNAPSHOT_CURSOR_BODY = """# /snapshot — Task-Boundary Capture (Cursor-native)

Cursor-native command backed by `scripts/aria/capture-task-boundary.sh`. Writes a small markdown snapshot of the current session's repo + hook state to `{knowledge_folder}/intake/task-boundary-captures/`. The same script runs automatically on every `stop` event when `task_boundary_capture` is enabled in config — `/snapshot` is the on-demand entrypoint for invoking it mid-session.

**Explicitly not a raw transcript capture.** Cursor does not expose conversation transcripts to hooks or skills, so `/snapshot` captures only what is observable from outside the conversation:

- timestamp + session id + cwd
- git branch + `git status --short` + changed files + `git diff --stat`
- active batch manifest (if present)
- config path + knowledge_folder
- recent `/tmp/aria-hook-debug.log` lines

If you need narrative content (decisions made, insights worth keeping), use `/extract` instead — it's the right surface for capture-from-conversation.

## How to Run

```bash
echo '{"sessionId":"manual-snapshot"}' | bash scripts/aria/capture-task-boundary.sh
```

Or invoke from the agent: read `.cursor/aria-knowledge.local.md` for `knowledge_folder`, then run the script with a small JSON payload on stdin. The script is idempotent — each invocation writes a new timestamped file under `intake/task-boundary-captures/` and never overwrites.

## When to Use

- Pausing mid-task and want a self-describing record of where the working tree is.
- About to switch branches or run a destructive operation, and want a "what was the state right before" marker.
- Debugging hook behavior — the capture's `recent /tmp/aria-hook-debug.log` section is the cheapest way to confirm hooks are firing.

## Limitations

- No transcript content. If the value you want lives in the conversation (decisions, alternatives ranked, why-not's), this command will not capture it. Use `/extract`.
- Captures are advisory artifacts, not promoted knowledge. `/audit-knowledge` does not auto-promote from `intake/task-boundary-captures/`; treat them as a debugging / forensic surface.
"""

CURSOR_STEP_2D = """## Step 2d: Review Task-Boundary Captures (Cursor port)

Scan `{knowledge_folder}/intake/task-boundary-captures/` for `.md` files. **If the directory doesn't exist or is empty**, skip silently to Step 2e.

**If captures exist**, report the count and total size, then ask the user:

> "Found N task-boundary capture(s) (total ~X KB) from Cursor `stop` hook or `/snapshot`. These are structural snapshots (git + hook state) — **not transcripts**. Options:"
> 1. **Skim** — read filenames + timestamps for forensic context (default)
> 2. **Detailed** — read full capture bodies (~1-5K tokens each)
> 3. **Skip** — leave for a future audit
> 4. **Clear** — move to `{knowledge_folder}/archive/audit-{date}/task-boundary-captures/` with a brief REMOVED.md ledger, then delete from intake

Do **not** run `digest-transcript.sh` on these files — they are not conversation transcripts.

For each reviewed capture, note findings for Step 6 under a "Task-Boundary Captures" section. Approved structural notes may append to `extraction-backlog.md` if they contain actionable project context; otherwise treat as informational only.
"""

COMMANDS_PREAMBLE = """---
description: "ARIA workflow commands — /extract, /index, /backlog, /stats, /ask, /clip, /clip-thread, /intake, /extract-doc, /meeting-notes, /digest, /sync-decisions, /wrapup, /codemap, /distill, /stitch, /handoff, /prospect, /retrospect, /snapshot, /setup, /help, /audit-share. Use when the user invokes any of these slash commands or their natural-language equivalents."
globs: ["knowledge/**/*", "CODEMAP.md", "STITCH-*.md"]
alwaysApply: false
---

# ARIA — Commands

This file ports ARIA skill instructions for the **Cursor** port. Triggers are natural-language (e.g., "extract session knowledge", "map the codebase", "wrap up session") in addition to slash-command names. Skill aliases: `/share-audit` → `/audit-share`, `/knowledge-audit` → `/audit-knowledge`, `/config-audit` → `/audit-config`.

**Cursor port notes:** Config lives at `.cursor/aria-knowledge.local.md` (per-repo). Rule 22 uses the edit-intent marker (`scripts/aria/record-edit-intent.sh`) — see `AGENTS.md`. Connect MCP servers in **Cursor Settings → MCP** for `/clip-thread`, `/extract-doc`, `/meeting-notes`, `/digest`, and `/sync-decisions`. ADR-094 dual-port Runtime Gates are **not** used in Cursor (no aria-cowork collision in typical Cursor sessions).

---
"""

AUDIT_PREAMBLE = """---
description: "ARIA audit skills — /audit-knowledge (alias /knowledge-audit) and /audit-config (alias /config-audit). Use when user says 'audit knowledge', 'audit config', 'review setup', or runs the slash commands."
globs: ["knowledge/intake/**/*", "knowledge/index.md", ".cursor/aria-knowledge.local.md", "AGENTS.md"]
alwaysApply: false
---

# ARIA — Audit Skills

This file ports the `/audit-knowledge` and `/audit-config` skill instructions for the Cursor port. Triggers are natural-language ("audit knowledge", "audit config", "review setup") in addition to slash-command names. The `/knowledge-audit` and `/config-audit` aliases are accepted equivalents.

---
"""

CONTEXT_PREAMBLE = """---
description: "ARIA context surfacing — /context and /rules. Use whenever the user asks to load knowledge by topic, references a tag, or asks 'what do we know about X' or 'look up rule N'. Also fires the implicit task-start tag match described in AGENTS.md."
globs: ["knowledge/**/*.md"]
alwaysApply: false
---

# ARIA — Context & Rules Skills

This file ports the `/context` and `/rules` skill instructions for the Cursor port. Triggers are natural-language ("when the user asks to load knowledge about X", "look up rule N") in addition to the slash-command names.

---
"""

RULE22_FRONTMATTER = """---
description: "Rule 22 — change decision framework. Apply BEFORE every Edit/Write: emit a [Rule 22] block (Low Impact or High Impact 7-step) ABOVE the tool call in the same turn, then run scripts/aria/record-edit-intent.sh to log intent. Verify scope AFTER each edit."
globs: ["**/*"]
alwaysApply: true
---

"""

CURSOR_HOOK_IMPL = """## Hook Implementation (Cursor port)

These hooks enforce the framework in Cursor via `.cursor/hooks.json`:

- **beforeFileEdit** — advisory reminder + edit-intent marker check (`scripts/aria/pre-edit-check.sh`)
- **afterFileEdit** — scope verification reminder + intent marker consumption (`scripts/aria/post-edit-check.sh`)

### How It Works

1. Agent emits `[Rule 22]` block, runs `record-edit-intent.sh`, then Edit/Write
2. **beforeFileEdit** verifies marker recency / protected-file escalation
3. Edit is made
4. **afterFileEdit** prompts post-edit scope check and consumes the marker

Cursor does **not** have transcript-based deny (`permissionDecision: deny`). Enforcement is instruction-based + advisory hook wording. See `AGENTS.md` and `audit/ARIA_CURSOR_AUDIT_REPORT.md` §5.
"""

CURSOR_ORDERING_DENY = """**Cursor-native enforcement: record-edit-intent before each edit.** Before invoking Edit/Write, run `bash scripts/aria/record-edit-intent.sh <filePath> rule22-low|rule22-high "<rationale>"`. This writes `.cursor/aria-edit-intent.json`. The `beforeFileEdit` hook checks for a recent (≤10 min) matching marker. Missing / stale / mismatched markers escalate the advisory — protected files get explicit violation wording. `afterFileEdit` consumes the marker on success. Order: emit `[Rule 22]` block → `record-edit-intent.sh` → Edit/Write.

Every compliance block is marked with a `[Rule 22]` prefix on its header line. The marker is the detection target for instruction discipline; Cursor hooks are **advisory** (no transcript deny)."""


def strip_frontmatter(text: str) -> str:
    if text.startswith("---"):
        end = text.find("\n---", 3)
        if end != -1:
            return text[end + 4 :].lstrip("\n")
    return text


def strip_runtime_gate(text: str) -> str:
    pattern = re.compile(
        r"\n## Runtime Gate \(per ADR-094\).*?(?=\n## |\n# /|\n---\n\n## |\n### Step )",
        re.DOTALL,
    )
    return pattern.sub("\n", text)


def adapt_cursor(text: str) -> str:
    text = strip_runtime_gate(text)
    replacements = [
        ("~/.claude/aria-knowledge.local.md", ".cursor/aria-knowledge.local.md"),
        (
            "${CLAUDE_PLUGIN_ROOT}/template/intake/intake-doc.md",
            "knowledge/intake/docs/_TEMPLATE.md (or inline structure from Step D3 below if missing)",
        ),
        ("${CLAUDE_PLUGIN_ROOT}/template/", "knowledge/"),
        ("${CLAUDE_PLUGIN_ROOT}/bin/", "scripts/aria/"),
        ("bin/config.sh", "scripts/aria/config.sh"),
        ("bin/digest-transcript.sh", "scripts/aria/digest-transcript.sh"),
        ("bin/lib-tracked-artifacts.sh", "scripts/aria/lib-tracked-artifacts.sh"),
        ("CLAUDE.md files", "AGENTS.md files"),
        ("PROGRESS.md, CLAUDE.md", "PROGRESS.md, AGENTS.md"),
        ("Edit CLAUDE.md", "Edit AGENTS.md"),
        ("3b:** Edit CLAUDE.md", "3b:** Edit AGENTS.md"),
        ("primary CLAUDE.md path", "primary AGENTS.md path"),
        ("ss/CLAUDE.md", "ss/AGENTS.md"),
        ("nearest dir with CLAUDE.md/PROGRESS.md", "nearest dir with AGENTS.md/CLAUDE.md/PROGRESS.md"),
        ("whose `CLAUDE.md` indexes", "whose `AGENTS.md` or `CLAUDE.md` indexes"),
        ("Claude's available tool list", "Cursor's available MCP tool list"),
        (
            "Claude Code's MCP config (or Cowork Settings → Connectors)",
            "Cursor Settings → MCP",
        ),
        (
            "[CONNECTORS.md](../../CONNECTORS.md)",
            "`plugin-claude-cowork/CONNECTORS.md` in the aria-knowledge repo",
        ),
        (
            "(Claude Code variant — bare-slash canonical when both ports loaded; see ADR-094.)",
            "(Cursor port — MCP skills use Cursor Settings → MCP.)",
        ),
        ("If `Bash` is available, proceed to Step 0.\n\n", ""),
        ("If `Bash` is NOT available", "If required tools are NOT available"),
        ("~/.claude/agent-memory/", ".cursor/agent-memory/"),
        (".claude/agent-memory/", ".cursor/agent-memory/"),
        (
            "SessionStart, TaskCreated, PreToolUse:Bash with cd, PostCompact",
            "sessionStart, stop, beforeShellExecution with cd, beforeReadFile",
        ),
        (
            "Auto-capture on compaction:** true (save transcript snapshot before context compaction)",
            "Task-boundary capture:** true (save structural snapshot on agent `stop` via `task_boundary_capture`; Cursor has no PreCompact transcript hook)",
        ),
        (
            "Usage alert threshold (`usage_alert_threshold`):** 80 (the percentage at which the status-line meter's `UserPromptSubmit` hook injects a usage warning into Claude's context when context-window, 5-hour, or 7-day usage crosses it — fires once per 5-point band, escalates, rearms after a drop). Only active when the status-line meter is installed (Step 5b). Set `off` to disable injection — Claude still reads usage on demand from the snapshot. Valid range 1–100.",
            "Usage alert threshold (`usage_alert_threshold`):** off (Claude Code only — requires `/statusline` meter + snapshot file; Cursor has no equivalent. Leave `off` unless you add a custom integration.)",
        ),
        ("intake/pre-compact-captures/", "intake/task-boundary-captures/"),
        ("pre-compact-captures/", "task-boundary-captures/"),
        ("Pre-Compact Captures", "Task-Boundary Captures"),
        ("pre-compact snapshot", "task-boundary capture"),
        ("pre-compaction transcript snapshot", "task-boundary capture"),
    ]
    for old, new in replacements:
        text = text.replace(old, new)
    text = re.sub(r"\(Claude Code variant[^\)]*\)", "(Cursor port.)", text)

    # Setup Step 1 — VERSION from scripts/aria/VERSION (plain text)
    setup_ver_block = (
        "**Read the installed port version first.** Parse `scripts/aria/VERSION` "
        "(plain text, one line — e.g. `2.24.2-cursor.0`):\n\n"
        "```bash\n"
        'INSTALLED_VERSION=$(cat "scripts/aria/VERSION" 2>/dev/null | tr -d \'[:space:]\')\n'
        '[ -z "$INSTALLED_VERSION" ] && INSTALLED_VERSION="unknown"\n'
        "```"
    )
    text = re.sub(
        r"\*\*Read the installed plugin version first\.\*\* Parse.*?```bash\nINSTALLED_VERSION=.*?\n```",
        setup_ver_block,
        text,
        count=1,
        flags=re.DOTALL,
    )
    text = text.replace(
        "`last_setup_version` is a semver string read from `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` at Step 1",
        "`last_setup_version` is a semver string read from `scripts/aria/VERSION` at Step 1",
    )

    # Setup Step 5b — statusline is Claude Code only
    text = re.sub(
        r"## Step 5b: Status-line Meter \(optional\).*?(?=## Step 6:)",
        "## Step 5b: Status-line Meter (Cursor port — skip)\n\n"
        "The CLI status-line meter (`/statusline`) is **Claude Code only**. Cursor has no persistent usage meter or "
        "`~/.claude/aria-statusline-state.json` snapshot. **Skip this step silently** — do not offer install. "
        "Ensure `usage_alert_threshold: off` in the config template unless the user explicitly requests otherwise.\n\n",
        text,
        flags=re.DOTALL,
    )

    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip() + "\n"


def adapt_audit(text: str) -> str:
    text = adapt_cursor(text)
    text = re.sub(
        r"## Step 2d: Review Task-Boundary Captures.*?## Step 2e:",
        CURSOR_STEP_2D + "\n\n## Step 2e:",
        text,
        flags=re.DOTALL,
    )
    return text


def skill_body(name: str) -> str:
    if name == "snapshot":
        return SNAPSHOT_CURSOR_BODY
    path = CODE_SKILLS / name / "SKILL.md"
    if not path.is_file():
        raise SystemExit(f"missing skill: {path}")
    body = adapt_cursor(strip_frontmatter(path.read_text(encoding="utf-8")))
    if name in AUDIT_SKILLS:
        body = adapt_audit(body)
    return body


def skill_section(name: str, title: str | None = None) -> str:
    title = title or name
    return f"\n---\n\n## /{title}\n\n\n{skill_body(name)}"


def patch_help_table(text: str) -> str:
    old_clip = "| /clip [url or text] | Quick-save a URL or text snippet to intake for later review |\n| /intake [path or url] | Bulk import knowledge from files, directories, or URLs |"
    new_clip = """| /clip [url or text] | Quick-save a URL or text snippet to intake for later review |
| /clip-thread [url or id] | Capture a Slack/Teams/Gmail thread via connected MCP to intake/clippings/ |
| /intake [path or url] | Bulk import knowledge from files, directories, or URLs |
| /intake doc [url or title] | Structured single-doc capture under intake/docs/ |
| /extract-doc [url] | Decompose one external doc into intake backlog entries (~~docs MCP) |
| /meeting-notes [url or paste] | Fold meeting transcript into intake/meetings/ (MCP or paste) |
| /digest [--week] | Cross-tool weekly rollup into intake/digests/ (MCP composite) |
| /sync-decisions [slug] | Mirror approved decisions to external wiki (~~docs WRITE MCP) |"""
    if old_clip in text:
        text = text.replace(old_clip, new_clip)
    old_wrap = "| /wrapup | End-of-session handoff — update PROGRESS/AGENTS.md, prompt for commit, verify continuity |\n| /handoff [auto] | Express handoff — same coverage as /wrapup, one combined-go review (or `auto` for silent), always emits a paste-ready next-session opener |"
    new_wrap = "| /wrapup [auto] | Session close-out — update PROGRESS/AGENTS.md, commit, always-run /extract in auto mode |\n| /handoff [auto\\|brief] | Passoff package with paste-ready next-session opener (or coworker brief) |"
    text = text.replace(old_wrap, new_wrap)
    text = text.replace(
        "| /snapshot | Save the current session transcript to intake/task-boundary-captures/ on demand |",
        "| /snapshot | On-demand task-boundary capture (git + hook state) to intake/task-boundary-captures/ |",
    )
    return text


def build_commands_mdc() -> str:
    parts = [COMMANDS_PREAMBLE]
    for name in COMMAND_SKILLS:
        parts.append(skill_section(name))
    content = "".join(parts) + "\n"
    content = patch_help_table(content)
    if content.rstrip().endswith("```"):
        content = content.rstrip()[:-3].rstrip() + "\n"
    return content


def build_audit_mdc() -> str:
    parts = [AUDIT_PREAMBLE]
    for name in AUDIT_SKILLS:
        parts.append(skill_section(name))
    return "".join(parts) + "\n"


def build_context_mdc() -> str:
    parts = [CONTEXT_PREAMBLE]
    for name in CONTEXT_SKILLS:
        parts.append(skill_section(name))
    return "".join(parts) + "\n"


def build_rule22_mdc() -> str:
    template = TEMPLATE_RULES / "change-decision-framework.md"
    body = template.read_text(encoding="utf-8")
    # Drop duplicate HTML comment if present (re-added via frontmatter note)
    body = re.sub(r"^<!-- plugin-managed.*?-->\n\n", "", body, count=1)
    body = adapt_cursor(body)
    body = body.replace(
        "A process discipline system for Claude Code that enforces structured decision-making before code changes and scope verification after. Implemented via hooks in `.claude/settings.local.json`.",
        "A process discipline system for Cursor that enforces structured decision-making before code changes and scope verification after. Implemented via hooks in `.cursor/hooks.json`.",
    )
    # Replace Claude deny ordering with Cursor advisory
    body = re.sub(
        r"Every compliance block is marked with a `\[Rule 22\]` prefix.*?The discipline is mechanism-enforced, not Claude-side\.",
        CURSOR_ORDERING_DENY,
        body,
        count=1,
        flags=re.DOTALL,
    )
    body = re.sub(
        r"## Hook Implementation.*?## Reference-Based Builds",
        CURSOR_HOOK_IMPL + "\n\n---\n\n## Reference-Based Builds",
        body,
        count=1,
        flags=re.DOTALL,
    )
    comment = (
        "<!-- plugin-managed: /setup diffs this file on plugin updates. "
        "Customize freely — diff prompts on future `/setup` runs. "
        "User-owned: `rules/user-rules.md`, `LOCAL.md`. -->\n\n"
    )
    return RULE22_FRONTMATTER + comment + body


def verify_markers() -> None:
    cmds = COMMANDS_MDC.read_text(encoding="utf-8")
    checks = [
        ("ephemeral tag", "ephemeral tag" in cmds or "ephemeral tags" in cmds),
        ("subagent-captures extract", "subagent-captures" in cmds),
        ("SESSION.md wrapup", "SESSION.md" in cmds),
        ("Wrapup Checklist", "Wrapup Checklist" in cmds),
        ("index Step 4 filter", "^s\\d+$" in cmds or "`^s\\d+$`" in cmds),
    ]
    audit = AUDIT_MDC.read_text(encoding="utf-8")
    checks += [
        ("audit Step 2e", "Step 2e: Review Subagent Captures" in audit),
        ("audit Step 2d cursor", "Step 2d: Review Task-Boundary" in audit),
    ]
    setup_version = 'scripts/aria/VERSION' in cmds and 'cat "scripts/aria/VERSION"' in cmds
    checks.append(("setup VERSION read", setup_version))
    failed = [name for name, ok in checks if not ok]
    if failed:
        raise SystemExit(f"port verification failed: {', '.join(failed)}")


def main() -> None:
    COMMANDS_MDC.write_text(build_commands_mdc(), encoding="utf-8")
    AUDIT_MDC.write_text(build_audit_mdc(), encoding="utf-8")
    CONTEXT_MDC.write_text(build_context_mdc(), encoding="utf-8")
    RULE22_MDC.write_text(build_rule22_mdc(), encoding="utf-8")
    verify_markers()
    print(f"Updated {COMMANDS_MDC} ({COMMANDS_MDC.stat().st_size} bytes)")
    print(f"Updated {AUDIT_MDC} ({AUDIT_MDC.stat().st_size} bytes)")
    print(f"Updated {CONTEXT_MDC} ({CONTEXT_MDC.stat().st_size} bytes)")
    print(f"Updated {RULE22_MDC} ({RULE22_MDC.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
