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


def run_hook(event: str, payload: dict[str, object], *, env: dict[str, str] | None = None) -> dict[str, object]:
    hook_env = os.environ.copy()
    hook_env["ARIA_CODEX_PLUGIN_ROOT"] = str(PORT_ROOT)
    hook_env["PLUGIN_ROOT"] = str(PORT_ROOT)
    hook_env["CLAUDE_PLUGIN_ROOT"] = str(PORT_ROOT)
    if env:
        hook_env.update(env)
    proc = subprocess.run(
        [sys.executable, str(PORT_ROOT / "bin" / "codex-hook.py"), event],
        input=json.dumps(payload),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=hook_env,
        check=False,
    )
    assert proc.returncode == 0, proc.stderr
    assert proc.stdout.strip(), "hook produced no JSON output"
    return json.loads(proc.stdout)


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


def test_manifest_and_hook_commands_use_codex_plugin_root() -> None:
    manifest = json.loads(read(PORT_ROOT / ".codex-plugin" / "plugin.json"))
    assert manifest["version"] == "2.20.2-codex.0"
    assert manifest["hooks"] == "./hooks.json"
    assert manifest["mcpServers"] == "./.mcp.json"

    mcp = json.loads(read(PORT_ROOT / ".mcp.json"))
    assert "mcp_servers" in mcp
    assert "mcpServers" not in mcp
    assert "slack" in mcp["mcp_servers"]

    hooks = json.loads(read(PORT_ROOT / "hooks.json"))
    commands: list[str] = []
    for groups in hooks["hooks"].values():
        for group in groups:
            for hook in group["hooks"]:
                commands.append(hook["command"])

    assert commands
    for command in commands:
        assert "${PLUGIN_ROOT}/bin/codex-hook.sh" in command
        assert "./bin/codex-hook.sh" not in command


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
