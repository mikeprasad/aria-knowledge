#!/usr/bin/env python3
"""Port plugin-claude-code SKILL.md bodies into plugin-cursor-template/.cursor/rules/aria-commands.mdc."""

from __future__ import annotations

import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CODE_SKILLS = REPO / "plugin-claude-code" / "skills"
MDC = REPO / "plugin-cursor-template" / ".cursor" / "rules" / "aria-commands.mdc"

CURSOR_PREAMBLE = """---
description: "ARIA workflow commands — /extract, /index, /backlog, /stats, /ask, /clip, /clip-thread, /intake, /extract-doc, /meeting-notes, /digest, /sync-decisions, /wrapup, /codemap, /distill, /stitch, /handoff, /prospect, /retrospect, /snapshot, /setup, /help, /audit-share. Use when the user invokes any of these slash commands or their natural-language equivalents."
globs: ["knowledge/**/*", "CODEMAP.md", "STITCH-*.md"]
alwaysApply: false
---

# ARIA — Commands

This file ports ARIA skill instructions for the **Cursor** port. Triggers are natural-language (e.g., "extract session knowledge", "map the codebase", "wrap up session") in addition to slash-command names. Skill aliases: `/share-audit` → `/audit-share`, `/knowledge-audit` → `/audit-knowledge`, `/config-audit` → `/audit-config`.

**Cursor port notes:** Config lives at `.cursor/aria-knowledge.local.md` (per-repo). Rule 22 uses the edit-intent marker (`scripts/aria/record-edit-intent.sh`) — see `AGENTS.md`. Connect MCP servers in **Cursor Settings → MCP** for `/clip-thread`, `/extract-doc`, `/meeting-notes`, `/digest`, and `/sync-decisions`. ADR-094 dual-port Runtime Gates are **not** used in Cursor (no aria-cowork collision in typical Cursor sessions).

---
"""

NEW_SKILLS = [
    "clip-thread",
    "extract-doc",
    "meeting-notes",
    "digest",
    "sync-decisions",
]


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
        ("${CLAUDE_PLUGIN_ROOT}/template/intake/intake-doc.md", "knowledge/intake/docs/_TEMPLATE.md (or inline structure from Step D3 below if missing)"),
        ("${CLAUDE_PLUGIN_ROOT}/template/", "knowledge/"),
        ("bin/config.sh", "scripts/aria/config.sh"),
        ("CLAUDE.md files", "AGENTS.md files"),
        ("CLAUDE.md", "AGENTS.md"),
        ("PROGRESS.md, CLAUDE.md", "PROGRESS.md, AGENTS.md"),
        ("Edit CLAUDE.md", "Edit AGENTS.md"),
        ("3b:** Edit CLAUDE.md", "3b:** Edit AGENTS.md"),
        ("primary CLAUDE.md path", "primary AGENTS.md path"),
        ("ss/CLAUDE.md", "ss/AGENTS.md"),
        ("Claude's available tool list", "Cursor's available MCP tool list"),
        (
            "Claude Code's MCP config (or Cowork Settings → Connectors)",
            "Cursor Settings → MCP",
        ),
        ("[CONNECTORS.md](../../CONNECTORS.md)", "`plugin-claude-cowork/CONNECTORS.md` in the aria-knowledge repo"),
        (
            "(Claude Code variant — bare-slash canonical when both ports loaded; see ADR-094.)",
            "(Cursor port — MCP skills use Cursor Settings → MCP.)",
        ),
        ("If `Bash` is available, proceed to Step 0.\n\n", ""),
        ("If `Bash` is NOT available", "If required tools are NOT available"),
    ]
    for old, new in replacements:
        text = text.replace(old, new)
    text = re.sub(r"\(Claude Code variant[^\)]*\)", "(Cursor port.)", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip() + "\n"


def skill_section(name: str) -> str:
    path = CODE_SKILLS / name / "SKILL.md"
    body = adapt_cursor(strip_frontmatter(path.read_text(encoding="utf-8")))
    return f"\n---\n\n## /{name}\n\n\n{body}"


def patch_extract_project_match(text: str) -> str:
    old = """3. For each pair, check if the CWD contains the configured path as a substring. If so, set `current_project` to that tag and stop iterating (first match wins)."""
    new = """3. For each pair, check if the CWD contains the configured path as a substring. Track every matching tag and keep the tag whose configured path is the **longest** substring match (nested sub-projects win over parent workspace paths)."""
    if old in text:
        text = text.replace(old, new)
    old_ex = """- CWD = `~/Projects/myproject/sub-module/file.md`, `projects_list: myproject:myproject,other:other` → `current_project = myproject` (substring match on `myproject`)"""
    new_ex = """- CWD = `~/Projects/aria/aria-core/file.md`, `projects_list: aria:aria,aria-core:aria/aria-core` → `current_project = aria-core` (longest path match wins over `aria`)"""
    text = text.replace(old_ex, new_ex)
    return text


def patch_wrapup_handoff(text: str) -> str:
    # wrapup Step 7-9 (cursor still had handoff labels)
    text = text.replace(
        "## Step 7: Verify Handoff Readiness\n\nRun through a checklist and report status:\n\n```\n## Handoff Checklist",
        "## Step 7: Verify Wrapup Readiness\n\nRun through a checklist and report status:\n\n```\n## Wrapup Checklist",
        1,
    )
    text = text.replace(
        "**If `mode = auto`:** invoke the `/extract` skill without prompting. It handles its own config resolution and execution. (Captures session knowledge so the close-out is fully documented.)\n\n**Otherwise (gated mode):** Ask: \"Run /extract to capture session knowledge before ending? (yes / no)\"\n\n- **yes** — invoke the /extract skill (it handles its own config resolution and execution)\n- **no** — skip",
        "**If `mode = auto`:** ALWAYS invoke the `/extract` skill. No judgment-skip allowed — even if the session feels short, conversational, or seems to have nothing new to extract, run `/extract` anyway. The model running this step must not pre-judge whether extraction is worthwhile; `/extract` has its own dedup logic (per its Rules section: \"Never ask for confirmation — scan and dump\") that correctly handles the \"nothing to add\" case by reporting `No uncaptured knowledge found`. Auto mode's \"implicit-yes on all gates\" rule converts to **\"extract always runs\"** here — there is no skip path in auto mode.\n\n**Otherwise (gated mode):** Ask: \"Run /extract to capture session knowledge before ending? (yes / no)\"\n\n- **yes** — invoke the /extract skill. Once the user has said yes, the same \"always run\" rule applies — do not subsequently skip based on session-content judgment.\n- **no** — skip",
        1,
    )
    text = text.replace(
        "## Session Handoff Complete\n\n[1-2 lines: what was updated]\n\n**Next session pickup:** Read [path to PROGRESS.md or AGENTS.md]\n```",
        "## Session Wrapup Complete\n\n[1-2 lines: what was updated]\n\n**Next session pickup:** Read [path to PROGRESS.md or AGENTS.md]\n```\n\nUse the heading **`Session Wrapup Complete`** for `/wrapup` runs — distinct from `/handoff`'s closing headings. The two skills have distinct intents per the v2.19.0 intent split.",
        1,
    )
    # handoff step 6
    text = text.replace(
        "Invoke `/extract` programmatically. `/extract` is already non-interactive by design (per its Rules section: \"Never ask for confirmation — scan and dump\"), so no user prompt is needed in either mode. Capture its summary report for inclusion in Step 8.",
        "ALWAYS invoke `/extract` programmatically. This applies to default mode (after the user has approved the combined-go review in Step 4) AND `auto` mode unconditionally. No judgment-skip allowed — even if the session feels short, conversational, or seems to have nothing new to extract, run `/extract` anyway. Capture `/extract`'s summary report for inclusion in Step 8.\n\n(Brief mode never reaches Step 6 — it exits at Step 2B before any handoff side-effects.)",
        1,
    )
    return text


def replace_section(content: str, name: str, new_body: str) -> str:
    start_marker = f"## /{name}\n"
    start = content.find(start_marker)
    if start == -1:
        raise SystemExit(f"section not found: {name}")
    next_section = content.find("\n---\n\n## /", start + len(start_marker))
    if next_section == -1:
        raise SystemExit(f"next section not found after: {name}")
    return content[:start] + f"## /{name}\n\n\n{new_body.strip()}\n" + content[next_section:]


def upsert_section(content: str, name: str, body: str, before: str | None = None) -> str:
    """Replace section if present; otherwise insert before `before` marker."""
    marker = f"## /{name}\n"
    block = f"\n---\n\n## /{name}\n\n\n{body.strip()}\n"
    if marker in content:
        return replace_section(content, name, body)
    if before is None:
        raise SystemExit(f"cannot upsert {name}: section missing and no insert point")
    insert_at = content.find(before)
    if insert_at == -1:
        raise SystemExit(f"insert point not found for {name}: {before!r}")
    return content[:insert_at] + block + content[insert_at:]


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
    text = text.replace(old_clip, new_clip)
    old_wrap = "| /wrapup | End-of-session handoff — update PROGRESS/AGENTS.md, prompt for commit, verify continuity |\n| /handoff [auto] | Express handoff — same coverage as /wrapup, one combined-go review (or `auto` for silent), always emits a paste-ready next-session opener |"
    new_wrap = "| /wrapup [auto] | Session close-out — update PROGRESS/AGENTS.md, commit, always-run /extract in auto mode |\n| /handoff [auto\\|brief] | Passoff package with paste-ready next-session opener (or coworker brief) |"
    return text.replace(old_wrap, new_wrap)


def fix_wrapup_closing_fence(text: str) -> str:
    """Remove stray ``` after wrapup Step 9 note (patch_wrapup_handoff must not add one)."""
    bad = (
        "Use the heading **`Session Wrapup Complete`** for `/wrapup` runs — distinct from `/handoff`'s closing headings. "
        "The two skills have distinct intents per the v2.19.0 intent split.\n```\n\n## Rules"
    )
    good = (
        "Use the heading **`Session Wrapup Complete`** for `/wrapup` runs — distinct from `/handoff`'s closing headings. "
        "The two skills have distinct intents per the v2.19.0 intent split.\n\n## Rules"
    )
    return text.replace(bad, good)


def main() -> None:
    content = MDC.read_text(encoding="utf-8")
    # Replace file header through first skill
    first_skill = content.find("## /extract\n")
    if first_skill == -1:
        raise SystemExit("## /extract not found")
    content = CURSOR_PREAMBLE + content[first_skill:]

    content = patch_extract_project_match(content)
    content = patch_wrapup_handoff(content)
    content = fix_wrapup_closing_fence(content)
    content = patch_help_table(content)

    # Full intake replace
    intake_body = adapt_cursor(strip_frontmatter((CODE_SKILLS / "intake" / "SKILL.md").read_text(encoding="utf-8")))
    content = replace_section(content, "intake", intake_body)

    # MCP skills (idempotent upsert before /setup)
    setup_marker = "\n---\n\n## /setup\n"
    for name in NEW_SKILLS:
        body = adapt_cursor(strip_frontmatter((CODE_SKILLS / name / "SKILL.md").read_text(encoding="utf-8")))
        content = upsert_section(content, name, body, before=setup_marker)

    # Fix trailing stray fence from audit-share
    content = content.rstrip()
    if content.endswith("```"):
        content = content[:-3].rstrip()

    MDC.write_text(content + "\n", encoding="utf-8")
    print(f"Updated {MDC} ({MDC.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
