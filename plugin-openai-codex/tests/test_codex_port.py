#!/usr/bin/env python3
"""Codex port parity checks.

These tests focus on Codex-specific packaging and adapter behavior. They are
kept inside plugin-openai-codex/ so they can evolve with the port without
modifying the cross-port test harness.
"""

from __future__ import annotations

import json
import importlib.util
import os
import subprocess
import sys
import tempfile
from pathlib import Path


PORT_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = PORT_ROOT.parent


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def load_hook_module():
    spec = importlib.util.spec_from_file_location("aria_codex_hook", PORT_ROOT / "bin" / "codex-hook.py")
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    previous = sys.dont_write_bytecode
    sys.dont_write_bytecode = True
    try:
        spec.loader.exec_module(module)
    finally:
        sys.dont_write_bytecode = previous
    return module


def parse_frontmatter(path: Path) -> dict[str, str]:
    text = read(path)
    assert text.startswith("---\n"), f"{path} missing opening frontmatter"
    end = text.find("\n---\n", 4)
    assert end != -1, f"{path} missing closing frontmatter"
    fields: dict[str, str] = {}
    for line in text[4:end].splitlines():
        if not line.strip():
            continue
        key, sep, value = line.partition(":")
        assert sep, f"{path} malformed frontmatter line: {line!r}"
        fields[key.strip()] = value.strip().strip('"')
    return fields


def run_hook(
    event: str,
    payload: dict[str, object],
    *,
    env: dict[str, str] | None = None,
    expect_json: bool = True,
) -> dict[str, object]:
    hook_env = os.environ.copy()
    hook_env["ARIA_CODEX_PLUGIN_ROOT"] = str(PORT_ROOT)
    hook_env["PLUGIN_ROOT"] = str(PORT_ROOT)
    hook_env["CLAUDE_PLUGIN_ROOT"] = str(PORT_ROOT)
    if env:
        hook_env.update(env)
    proc = subprocess.run(
        [sys.executable, str(PORT_ROOT / "bin" / "codex-hook.py"), event],
        input=json.dumps(payload, separators=(",", ":")),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=hook_env,
        check=False,
    )
    assert proc.returncode == 0, proc.stderr
    if not expect_json:
        assert proc.stdout.strip() == "", proc.stdout
        return {}
    assert proc.stdout.strip(), "hook produced no JSON output"
    return json.loads(proc.stdout)


def write_config(path: Path, knowledge_folder: Path, extra: str = "") -> None:
    path.write_text(
        f"""---
knowledge_folder: {knowledge_folder}
audit_cadence_knowledge: 7
audit_cadence_config: 14
auto_capture: true
active_knowledge_surfacing: true
{extra}---

# ARIA test config
""",
        encoding="utf-8",
    )


def test_all_skills_have_codex_metadata_and_concise_descriptions() -> None:
    for skill in sorted((PORT_ROOT / "skills").glob("*/SKILL.md")):
        fields = parse_frontmatter(skill)
        expected_name = skill.parent.name
        assert fields.get("name") == expected_name, f"{skill} should declare name: {expected_name}"
        description = fields.get("description", "")
        assert description, f"{skill} missing description"
        assert len(description) <= 420, f"{skill} description too long for Codex discovery"
        assert "Bare-slash canonical" not in description
        assert "RUNTIME GATE" not in description


def test_codex_skills_do_not_ship_adr094_runtime_gate_sections() -> None:
    for skill in sorted((PORT_ROOT / "skills").glob("*/SKILL.md")):
        body = read(skill)
        assert "## Runtime Gate (per ADR-094)" not in body, f"{skill} still has ADR-094 runtime gate"
        assert "/aria-cowork:" not in body, f"{skill} still routes to cowork runtime"


def test_review_skills_are_ported_with_bundled_process_doc() -> None:
    foundational = PORT_ROOT / "skills" / "foundational-review" / "SKILL.md"
    readiness = PORT_ROOT / "skills" / "readiness-audit" / "SKILL.md"
    chain = PORT_ROOT / "skills" / "foundational-review" / "foundational-review-chain.md"
    assert foundational.exists()
    assert readiness.exists()
    assert chain.exists()
    assert "Runtime Gate (per ADR-094)" not in read(foundational)
    assert "Runtime Gate (per ADR-094)" not in read(readiness)
    assert "${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}" in read(foundational)
    assert "${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}" in read(readiness)


def test_consolidated_intake_retires_old_capture_skills() -> None:
    active = {path.parent.name for path in (PORT_ROOT / "skills").glob("*/SKILL.md")}
    assert "intake" in active
    assert "clip" not in active
    assert "clip-thread" not in active
    assert "extract-doc" not in active
    assert (PORT_ROOT / "skills" / ".archived" / "clip" / "SKILL.md").exists()
    assert (PORT_ROOT / "skills" / ".archived" / "clip-thread" / "SKILL.md").exists()
    assert (PORT_ROOT / "skills" / ".archived" / "extract-doc" / "SKILL.md").exists()

    intake = read(PORT_ROOT / "skills" / "intake" / "SKILL.md")
    assert "## Clip-Whole Steps" in intake
    assert "## Thread Mode Steps" in intake
    assert "mode = extract" in intake
    assert "Absorbs the retired `/clip`" in intake


def test_interview_and_recap_are_codex_native_active_skills() -> None:
    for name in ("interview", "recap"):
        path = PORT_ROOT / "skills" / name / "SKILL.md"
        assert path.exists()
        fields = parse_frontmatter(path)
        assert fields["name"] == name
        body = read(path)
        assert "Runtime Gate (per ADR-094)" not in body
        assert "/aria-cowork:" not in body


def test_rule35_and_reference_sources_template_are_synced() -> None:
    rules = read(PORT_ROOT / "template" / "rules" / "working-rules.md")
    refs = read(PORT_ROOT / "template" / "references" / "README.md")
    assert "### 35. Decision routing" in rules
    assert "references/sources/" in refs
    assert "verbatim graduated clippings" in refs


def test_manifest_and_hook_commands_use_codex_plugin_root() -> None:
    manifest = json.loads(read(PORT_ROOT / ".codex-plugin" / "plugin.json"))
    assert manifest["version"] == "2.35.2-codex.0"
    assert manifest["hooks"] == "./hooks.json"
    assert manifest["mcpServers"] == "./.mcp.json"

    mcp = json.loads(read(PORT_ROOT / ".mcp.json"))
    assert "mcp_servers" in mcp
    assert "mcpServers" not in mcp
    assert "slack" in mcp["mcp_servers"]

    hooks = json.loads(read(PORT_ROOT / "hooks.json"))
    assert "UserPromptSubmit" in hooks["hooks"]
    assert "SubagentStart" in hooks["hooks"]
    assert "SubagentStop" in hooks["hooks"]
    commands: list[str] = []
    for groups in hooks["hooks"].values():
        for group in groups:
            for hook in group["hooks"]:
                commands.append(hook["command"])

    assert commands
    for command in commands:
        assert "${PLUGIN_ROOT}/bin/codex-hook.sh" in command
        assert "./bin/codex-hook.sh" not in command


def test_statusline_feature_is_documented_as_non_equivalent() -> None:
    assert not (PORT_ROOT / "skills" / "statusline").exists()
    assert not (PORT_ROOT / "bin" / "statusline-meter.sh").exists()
    assert not (PORT_ROOT / "bin" / "usage-threshold-inject.sh").exists()
    assert "Codex Non-Equivalent: Statusline Meter" in read(PORT_ROOT / "CONFIG.md")
    assert "usage_alert_threshold" in read(PORT_ROOT / "CONFIG.md")


def test_aria_assist_scheduler_is_documented_as_non_equivalent() -> None:
    assert not (PORT_ROOT / "skills" / "aria-assist").exists()
    assert not (PORT_ROOT / "bin" / "pm-morning-run.sh").exists()
    assert not (PORT_ROOT / "bin" / "pm-schedule.sh").exists()
    assert "Codex Non-Equivalent: ARIA Assist Scheduler" in read(PORT_ROOT / "CONFIG.md")


def test_codex_docs_and_setup_prefer_shared_config() -> None:
    setup = read(PORT_ROOT / "skills" / "setup" / "SKILL.md")
    readme = read(PORT_ROOT / "README.md")
    wrapper = read(PORT_ROOT / "bin" / "codex-hook.sh")

    assert "~/.claude/aria-knowledge.local.md" in setup
    assert "intentionally shares this config file" in setup
    assert "Write `~/.codex/aria-knowledge.local.md`" not in setup
    assert "Codex-specific installs may create" not in readme
    assert "$HOME/.claude/aria-knowledge.local.md" in wrapper
    assert wrapper.find("$HOME/.claude/aria-knowledge.local.md") < wrapper.find("$HOME/.codex/aria-knowledge.local.md")
    assert "session_stale_days" in setup
    assert "autonomy" in setup


def test_pre_tool_use_denies_apply_patch_with_current_codex_shape() -> None:
    payload = {
        "hook_event_name": "PreToolUse",
        "turn_id": "turn-1",
        "tool_name": "apply_patch",
        "tool_use_id": "tool-1",
        "tool_input": {"command": "*** Begin Patch\n*** End Patch\n"},
        "last_assistant_message": "I am editing now without the marker.",
    }
    output = run_hook("pre-tool-use", payload)
    hook = output["hookSpecificOutput"]
    assert hook["hookEventName"] == "PreToolUse"
    assert hook["permissionDecision"] == "deny"
    assert "permissionDecisionReason" in hook
    assert "additionalContext" not in hook


def test_pre_tool_use_ignores_stale_transcript_markers_from_previous_turns() -> None:
    with tempfile.NamedTemporaryFile("w", delete=False, encoding="utf-8") as fp:
        fp.write(json.dumps({"turn_id": "turn-0", "role": "assistant", "content": "[Rule 22] stale marker"}) + "\n")
        fp.write(json.dumps({"turn_id": "turn-1", "role": "assistant", "content": "No marker here"}) + "\n")
        transcript = fp.name
    try:
        payload = {
            "hook_event_name": "PreToolUse",
            "turn_id": "turn-1",
            "tool_name": "apply_patch",
            "tool_use_id": "tool-1",
            "tool_input": {"command": "*** Begin Patch\n*** End Patch\n"},
            "transcript_path": transcript,
        }
        output = run_hook("pre-tool-use", payload)
        assert output["hookSpecificOutput"]["permissionDecision"] == "deny"
    finally:
        os.unlink(transcript)


def test_transcript_reader_does_not_scan_without_turn_id() -> None:
    with tempfile.NamedTemporaryFile("w", delete=False, encoding="utf-8") as fp:
        fp.write(json.dumps({"role": "assistant", "content": "[Rule 22] stale marker"}) + "\n")
        transcript = fp.name
    try:
        hook = load_hook_module()
        assert hook.transcript_assistant_text(Path(transcript), "") == ""
    finally:
        os.unlink(transcript)


def test_apply_patch_parser_handles_multi_file_patches() -> None:
    hook = load_hook_module()
    command = """*** Begin Patch
*** Add File: docs/plans/example.md
+hello
*** Update File: src/app.py
@@
-old
+new
*** Delete File: tmp/old.txt
*** Move to: src/new_app.py
*** End Patch
"""
    assert hook.parse_apply_patch_files(command) == [
        "docs/plans/example.md",
        "src/app.py",
        "tmp/old.txt",
        "src/new_app.py",
    ]


def test_post_tool_use_apply_patch_emits_auto_prospect_nudge() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        knowledge = root / "knowledge"
        knowledge.mkdir()
        config = root / "aria-config.md"
        write_config(config, knowledge, "auto_prospect: nudge\n")
        payload = {
            "hook_event_name": "PostToolUse",
            "session_id": f"session-{root.name}",
            "turn_id": "turn-prospect",
            "cwd": str(root),
            "tool_name": "apply_patch",
            "tool_input": {
                "command": "*** Begin Patch\n*** Add File: docs/plans/example.md\n+plan\n*** End Patch\n"
            },
        }
        output = run_hook("post-tool-use", payload, env={"KT_CONFIG": str(config)})
        context = output["hookSpecificOutput"]["additionalContext"]
        assert "PLANNING PATH" in context
        assert "AUTO-PROSPECT (nudge)" in context


def test_post_tool_use_apply_patch_marks_session_in_progress() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        project = root / "project"
        (project / "src").mkdir(parents=True)
        (project / "AGENTS.md").write_text("# Project\n", encoding="utf-8")
        knowledge = root / "knowledge"
        knowledge.mkdir()
        config = root / "aria-config.md"
        write_config(config, knowledge, "session_state: true\nauthor_tag: codex-test\n")
        payload = {
            "hook_event_name": "PostToolUse",
            "session_id": f"session-{root.name}",
            "turn_id": "turn-session-state",
            "cwd": str(project),
            "tool_name": "apply_patch",
            "tool_input": {
                "command": "*** Begin Patch\n*** Add File: src/app.py\n+print('ok')\n*** End Patch\n"
            },
        }
        run_hook("post-tool-use", payload, env={"KT_CONFIG": str(config)})
        session = read(project / "SESSION.md")
        assert "lastEvent: in-progress" in session
        assert "by: codex-test" in session
        assert "sessionId: session-" in session


def test_user_prompt_submit_surfaces_index_matches_as_codex_context() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        knowledge = root / "knowledge"
        knowledge.mkdir()
        (knowledge / "index.md").write_text(
            """# Knowledge Index

## Tag Index

### stripe
- guides/stripe.md — Stripe integration guide

### webhooks
- guides/stripe.md — Stripe integration guide
- decisions/webhooks.md — Webhook retry ADR

## Other Tags
""",
            encoding="utf-8",
        )
        config = root / "aria-config.md"
        write_config(config, knowledge)
        payload = {
            "hook_event_name": "UserPromptSubmit",
            "session_id": f"session-{root.name}",
            "turn_id": "turn-prompt",
            "cwd": str(root),
            "prompt": "Fix the Stripe webhooks retry flow",
        }
        output = run_hook("user-prompt-submit", payload, env={"KT_CONFIG": str(config)})
        hook = output["hookSpecificOutput"]
        assert hook["hookEventName"] == "UserPromptSubmit"
        assert "ARIA ACTIVE" in hook["additionalContext"]
        assert "guides/stripe.md" in hook["additionalContext"]


def test_session_start_surfaces_autonomy_and_project_picker() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        knowledge = root / "knowledge"
        (knowledge / "logs").mkdir(parents=True)
        today = "2026-06-22"
        (knowledge / "logs" / "knowledge-audit-log.md").write_text(
            f"- **Date:** {today} — test audit\n", encoding="utf-8"
        )
        (knowledge / "logs" / "config-audit-log.md").write_text(
            f"- **Date:** {today} — test audit\n", encoding="utf-8"
        )
        config = root / "aria-config.md"
        write_config(
            config,
            knowledge,
            "last_setup_version: 2.35.2-codex.0\n"
            "projects_enabled: true\n"
            "projects_list: api:api-server,web:web-app\n"
            "projects_labels: api:API Server,web:Web App\n"
            "session_start_project_picker: true\n"
            "session_state: true\n"
            "session_stale_days: 3\n"
            "autonomy: balanced\n",
        )
        output = run_hook(
            "session-start",
            {"hook_event_name": "SessionStart", "session_id": f"session-{root.name}", "cwd": str(root)},
            env={"KT_CONFIG": str(config), "PWD": str(root)},
        )
        message = output["systemMessage"]
        assert "ARIA Project Picker" in message
        assert "api (API Server), web (Web App)" in message
        assert "session_stale_days (3 days by current config)" in message
        assert "DECISION ROUTING (balanced)" in message


def test_subagent_start_self_report_and_stop_capture() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        knowledge = root / "knowledge"
        knowledge.mkdir()
        config = root / "aria-config.md"
        write_config(
            config,
            knowledge,
            "subagent_capture: true\nsubagent_capture_types: Plan\nsubagent_selfreport_types: Explore\n",
        )

        start = run_hook(
            "subagent-start",
            {
                "hook_event_name": "SubagentStart",
                "session_id": f"session-{root.name}",
                "turn_id": "turn-subagent",
                "agent_id": "agent-start",
                "agent_type": "Explore",
            },
            env={"KT_CONFIG": str(config)},
        )
        assert start["hookSpecificOutput"]["hookEventName"] == "SubagentStart"
        assert "durable findings" in start["hookSpecificOutput"]["additionalContext"]

        transcript = root / "subagent.md"
        transcript.write_text("Durable finding: retry window matters.\n", encoding="utf-8")
        run_hook(
            "subagent-stop",
            {
                "hook_event_name": "SubagentStop",
                "session_id": f"session-{root.name}",
                "turn_id": "turn-subagent",
                "agent_id": "agent-stop",
                "agent_type": "Plan",
                "agent_transcript_path": str(transcript),
            },
            env={"KT_CONFIG": str(config)},
            expect_json=False,
        )
        captures = list((knowledge / "intake" / "subagent-captures").glob("*.md"))
        assert captures
        assert "retry window matters" in read(captures[0])


if __name__ == "__main__":
    failures = 0
    for name, fn in sorted(globals().items()):
        if not name.startswith("test_") or not callable(fn):
            continue
        try:
            fn()
        except Exception as exc:  # pragma: no cover - tiny self-runner
            failures += 1
            print(f"FAIL {name}: {exc}", file=sys.stderr)
        else:
            print(f"PASS {name}")
    raise SystemExit(1 if failures else 0)
