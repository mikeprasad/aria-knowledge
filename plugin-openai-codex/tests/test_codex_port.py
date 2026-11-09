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
import re
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


def test_246_parity_skills_are_codex_native_or_documented_gap() -> None:
    active = {path.parent.name for path in (PORT_ROOT / "skills").glob("*/SKILL.md")}
    for name in ("aria-assist", "audit", "audit-style", "audit-usage", "auto", "preflight", "roadmap"):
        assert name in active
        body = read(PORT_ROOT / "skills" / name / "SKILL.md")
        assert "Runtime Gate (per ADR-094)" not in body
        assert "/aria-cowork:" not in body

    assert "statusline" not in active
    assert "Codex Non-Equivalent: Statusline Meter" in read(PORT_ROOT / "CONFIG.md")


def test_rule35_and_reference_sources_template_are_synced() -> None:
    rules = read(PORT_ROOT / "template" / "rules" / "working-rules.md")
    refs = read(PORT_ROOT / "template" / "references" / "README.md")
    assert "### 35. Decision routing" in rules
    assert "references/sources/" in refs
    assert "verbatim graduated clippings" in refs


def test_manifest_and_hook_commands_use_codex_plugin_root() -> None:
    manifest = json.loads(read(PORT_ROOT / ".codex-plugin" / "plugin.json"))
    # Assert the version SHAPE, not a frozen literal — a hardcoded value goes stale on
    # every canonical parity bump (it did: this pinned an older codex release while the
    # manifest advanced, failing the whole test on the first line). The port
    # contract is: canonical "X.Y.Z" + the "-codex.N" prerelease suffix.
    assert re.fullmatch(r"\d+\.\d+\.\d+-codex\.\d+", manifest["version"]), manifest["version"]
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
    assert (PORT_ROOT / "skills" / "aria-assist" / "SKILL.md").exists()
    assert not (PORT_ROOT / "bin" / "pm-morning-run.sh").exists()
    assert not (PORT_ROOT / "bin" / "pm-schedule.sh").exists()
    assert "Codex Non-Equivalent: ARIA Assist Scheduler" in read(PORT_ROOT / "CONFIG.md")
    assert "manual-only" in read(PORT_ROOT / "CONFIG.md")


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


def test_pre_tool_use_shell_surfaces_preflight_warning() -> None:
    """Renamed 2026-08-26 when the STRING-matching pre-bash-write-check was retired.
    Its resolved-target REPLACEMENT is wired as of 2026-10-14 (see
    test_pre_tool_use_shell_records_in_place_write_to_bypass_ledger). This fixture's
    target lives under a temp directory, which the resolver exempts BY DESIGN, so
    "in place" must still be absent here — that is now a check of the temp exemption,
    not of the hook being unwired."""
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        subprocess.run(["git", "init"], cwd=root, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        (root / "src").mkdir()
        (root / "src" / "app.py").write_text("print('old')\n", encoding="utf-8")
        subprocess.run(["git", "add", "src/app.py"], cwd=root, check=True)
        knowledge = root / "knowledge"
        knowledge.mkdir()
        config = root / "aria-config.md"
        write_config(config, knowledge, "preflight_gate: warn\n")

        output = run_hook(
            "pre-tool-use",
            {
                "hook_event_name": "PreToolUse",
                "session_id": f"session-{root.name}",
                "turn_id": "turn-shell",
                "cwd": str(root),
                "tool_name": "Bash",
                "tool_input": {"command": "sed -i '' 's/old/new/' src/app.py && git commit -m test"},
                "last_assistant_message": "No marker here.",
            },
            env={"KT_CONFIG": str(config)},
        )
        context = output["hookSpecificOutput"]["additionalContext"]
        assert "PREFLIGHT" in context
        # The retired hook warned with the phrase "in place"; its absence is what
        # proves it is no longer wired. The command above still CONTAINS `sed -i`,
        # so asserting on that substring would test the fixture, not the hook.
        assert "in place" not in context


def test_pre_tool_use_shell_records_in_place_write_to_bypass_ledger() -> None:
    """The canonical resolved-target recorder (pre-bash-write-check.sh) is the only
    writer of the ledger /handoff and /wrapup read. The hook ANALYSES the command and
    never runs it, so a real tracked port file is a safe subject — and it must be
    outside temp, because the resolver exempts temp paths."""
    target = PORT_ROOT / "bin" / "config.sh"
    before = target.read_bytes()
    with tempfile.TemporaryDirectory() as tmp:
        ledger_dir = Path(tmp)
        sid = "session-bypass-ledger"

        def call(command: str, expect_json: bool) -> str:
            out = run_hook(
                "pre-tool-use",
                {
                    "hook_event_name": "PreToolUse",
                    "session_id": sid,
                    "turn_id": "turn-bypass",
                    "cwd": str(PORT_ROOT),
                    "tool_name": "Bash",
                    "tool_input": {"command": command},
                    "last_assistant_message": "No marker here.",
                },
                env={"TMPDIR": str(ledger_dir)},
                expect_json=expect_json,
            )
            hso = out.get("hookSpecificOutput", {}) if isinstance(out, dict) else {}
            return hso.get("additionalContext", "") if isinstance(hso, dict) else ""

        ledger = ledger_dir / f"aria-r22-bypass-{sid}"
        context = call("sed -i '' 's/a/b/' bin/config.sh", True)
        assert "in place" in context and "bin/config.sh" in context
        assert ledger.read_text(encoding="utf-8").strip() == "bin/config.sh"

        context = call("ls -la bin", False)
        assert "in place" not in context
        assert ledger.read_text(encoding="utf-8").strip() == "bin/config.sh"  # nothing appended
    assert target.read_bytes() == before  # analysed, never executed


def test_pre_tool_use_scheduler_denies_leading_slash_prompt() -> None:
    output = run_hook(
        "pre-tool-use",
        {
            "hook_event_name": "PreToolUse",
            "session_id": "session-cron",
            "turn_id": "turn-cron",
            "tool_name": "mcp__scheduled-tasks__create_scheduled_task",
            "tool_input": {"prompt": "/wrapup this task later"},
        },
    )
    hook = output["hookSpecificOutput"]
    assert hook["permissionDecision"] == "deny"
    assert "starts with a slash" in hook["permissionDecisionReason"]


def test_pre_tool_use_external_fetch_gate_runs_for_local_fetch_tools() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        knowledge = root / "knowledge"
        (knowledge / "guides").mkdir(parents=True)
        (knowledge / "guides" / "example.md").write_text("Use https://example.com/docs for this API.\n", encoding="utf-8")
        config = root / "aria-config.md"
        write_config(config, knowledge, "external_fetch_gate: on\n")

        output = run_hook(
            "pre-tool-use",
            {
                "hook_event_name": "PreToolUse",
                "session_id": f"session-{root.name}",
                "turn_id": "turn-fetch",
                "cwd": str(root),
                "tool_name": "WebFetch",
                "tool_input": {"url": "https://example.com/docs/new"},
            },
            env={"KT_CONFIG": str(config), "ARIA_EF_MEMDIR": str(root / "missing-memory")},
        )
        hook = output["hookSpecificOutput"]
        assert hook["permissionDecision"] == "deny"
        assert "example.com" in hook["permissionDecisionReason"]


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


def test_post_tool_use_apply_patch_warns_on_tautological_test_edit() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "tests").mkdir()
        (root / "tests" / "test_example.py").write_text("def test_example():\n    assert True\n", encoding="utf-8")
        knowledge = root / "knowledge"
        knowledge.mkdir()
        config = root / "aria-config.md"
        write_config(config, knowledge)

        output = run_hook(
            "post-tool-use",
            {
                "hook_event_name": "PostToolUse",
                "session_id": f"session-{root.name}",
                "turn_id": "turn-tautology",
                "cwd": str(root),
                "tool_name": "apply_patch",
                "tool_input": {
                    "command": "*** Begin Patch\n*** Update File: tests/test_example.py\n@@\n+    assert True\n*** End Patch\n"
                },
            },
            env={"KT_CONFIG": str(config)},
        )
        context = output["hookSpecificOutput"]["additionalContext"]
        assert "literal-true assertion" in context
        assert "Rule 36" in context


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


SURFACING_FIXTURE = PORT_ROOT.parent / "tests" / "repros" / "fixtures" / "surfacing" / "index.md"


def _surfacing_setup(root: Path) -> Path:
    knowledge = root / "knowledge"
    knowledge.mkdir()
    (knowledge / "index.md").write_text(SURFACING_FIXTURE.read_text(encoding="utf-8"), encoding="utf-8")
    config = root / "aria-config.md"
    write_config(
        config,
        knowledge,
        "projects_enabled: true\nprojects_list: proj-a:proj-a,proj-b:proj-b,proj-c:proj-c\n",
    )
    return config


def _prompt_payload(root: Path, prompt: str) -> dict[str, object]:
    return {
        "hook_event_name": "UserPromptSubmit",
        "session_id": f"session-{root.name}",
        "turn_id": "turn-prompt",
        "cwd": str(root),
        "prompt": prompt,
    }


def test_user_prompt_submit_ranks_through_the_shared_cli_project_first() -> None:
    # The fixture lists proj-c billing files FIRST under `payments`, so the retired Python
    # first-appearance rule would surface proj-c files; the shared matcher puts the matched
    # project's file first.
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        config = _surfacing_setup(root)
        output = run_hook(
            "user-prompt-submit",
            _prompt_payload(root, "fix the proj-b payments webhook"),
            env={"KT_CONFIG": str(config), "TMPDIR": tmp},
        )
        ctx = output["hookSpecificOutput"]["additionalContext"]
        assert ctx.startswith("ARIA ACTIVE — "), ctx[:80]
        assert "ARIA ACTIVE -" not in ctx, ctx[:80]
        files = re.findall(r"  - ([^;]+?)(?:;|\.? \()", ctx)
        assert files and files[0].strip() == "projects/proj-b/deposits.md", files
        assert "tags: payments proj-b" in ctx, ctx[:200]


def test_user_prompt_submit_ranks_a_prompt_that_starts_with_dashes() -> None:
    # The CLI treats a positional `--word` as an unknown option, so the hook must pass the
    # prompt on stdin (`-`), never as an argv element.
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        config = _surfacing_setup(root)
        output = run_hook(
            "user-prompt-submit",
            _prompt_payload(root, "--not-an-option fix the proj-b payments webhook"),
            env={"KT_CONFIG": str(config), "TMPDIR": tmp},
        )
        ctx = output["hookSpecificOutput"]["additionalContext"]
        assert "tags: payments proj-b" in ctx, ctx[:200]


def test_user_prompt_submit_is_silent_when_the_cli_is_missing_or_fails() -> None:
    # Two plain tags, so the prompt FIRES with a working CLI (control below) — otherwise the
    # silence asserted for the broken CLIs would carry no information.
    prompt = "fix the payments webhooks flow"
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        config = _surfacing_setup(root)
        control = run_hook(
            "user-prompt-submit",
            _prompt_payload(root, prompt),
            env={"KT_CONFIG": str(config), "TMPDIR": tmp},
        )
        assert "ARIA ACTIVE" in control["hookSpecificOutput"]["additionalContext"], control
    for mode in ("missing", "fails"):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            config = _surfacing_setup(root)
            fake_root = root / "fake-plugin"
            (fake_root / "bin").mkdir(parents=True)
            if mode == "fails":
                (fake_root / "bin" / "aria-surface.sh").write_text(
                    "#!/bin/sh\nprintf 'tags: payments proj-b\\nprojects/proj-b/deposits.md\\n'\nexit 3\n",
                    encoding="utf-8",
                )
            output = run_hook(
                "user-prompt-submit",
                _prompt_payload(root, prompt),
                env={"KT_CONFIG": str(config), "TMPDIR": tmp, "ARIA_CODEX_PLUGIN_ROOT": str(fake_root)},
                expect_json=False,
            )
            assert output == {}, (mode, output)


def test_user_prompt_submit_survives_an_unencodable_prompt() -> None:
    # F4 (final fix wave): the prompt goes to the CLI on stdin as text. A lone surrogate (valid in a
    # JSON \u escape, invalid in UTF-8) and a non-UTF-8 locale both made the encode raise a
    # UnicodeEncodeError -- a ValueError, which the OSError/SubprocessError handler did not catch --
    # so the hook crashed instead of ranking. Both must still rank the rest of the prompt.
    prompt = "fix the payments webhooks flow"
    cases = {
        "lone surrogate": (prompt + " \ud800", {}),
        "C locale, non-ASCII": (
            prompt + " café",
            {"LC_ALL": "C", "LANG": "C", "PYTHONUTF8": "0", "PYTHONCOERCECLOCALE": "0"},
        ),
    }
    for label, (text, extra) in cases.items():
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            config = _surfacing_setup(root)
            env = {"KT_CONFIG": str(config), "TMPDIR": tmp, **extra}
            output = run_hook("user-prompt-submit", _prompt_payload(root, text), env=env)
            ctx = output["hookSpecificOutput"]["additionalContext"]
            assert "ARIA ACTIVE" in ctx and "payments" in ctx, (label, ctx[:200])


def test_active_ledger_link_is_neither_read_nor_written() -> None:
    # F7 + (a) (final fix wave): the ledger lives at a predictable /tmp/aria-active-<session key>.
    # A link planted there must not filter the surfaced files (a read) or receive the record (a write).
    prompt = "fix the payments webhooks flow"
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        config = _surfacing_setup(root)
        env = {"KT_CONFIG": str(config), "TMPDIR": tmp}
        ledger = Path("/tmp") / f"aria-active-session-{root.name}"
        # The hook also keeps a 30 s per-session cooldown; clear it before each run so a silent run
        # is attributable to the ledger, never to the cooldown.
        cooldown = Path("/tmp") / f"aria-context-session-{root.name}"
        planted = root / "planted-ledger"

        def run(expect_json: bool = True) -> dict[str, object]:
            cooldown.unlink(missing_ok=True)
            return run_hook("user-prompt-submit", _prompt_payload(root, prompt), env=env, expect_json=expect_json)

        try:
            if ledger.is_symlink() or ledger.exists():
                ledger.unlink()
            first = run()
            assert "ARIA ACTIVE" in first["hookSpecificOutput"]["additionalContext"], first
            recorded = ledger.read_text(encoding="utf-8")
            assert recorded.strip(), "control: a regular ledger records the surfaced files"
            # Control: the same regular ledger filters a repeat (nothing new to surface).
            run(expect_json=False)
            planted.write_text(recorded, encoding="utf-8")
            ledger.unlink()
            ledger.symlink_to(planted)
            linked = run()
            assert "ARIA ACTIVE" in linked["hookSpecificOutput"]["additionalContext"], linked
            assert planted.read_text(encoding="utf-8") == recorded, "an append went through the link"
            assert ledger.is_symlink(), "the link was replaced"
        finally:
            if ledger.is_symlink() or ledger.exists():
                ledger.unlink()
            cooldown.unlink(missing_ok=True)


def test_post_compact_does_not_list_a_linked_ledger() -> None:
    # F7 (final fix wave): post-compact-check.sh shows the ledger's lines to the model.
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        knowledge = root / "knowledge"
        knowledge.mkdir()
        config = root / "aria-config.md"
        write_config(config, knowledge)
        sid = f"codex-f7-{root.name}"
        ledger = Path("/tmp") / f"aria-active-{sid}"
        planted = root / "planted"
        planted.write_text("planted/through-a-link.md\n", encoding="utf-8")
        payload = {"hook_event_name": "PostCompact", "session_id": sid}
        try:
            if ledger.is_symlink() or ledger.exists():
                ledger.unlink()
            ledger.symlink_to(planted)
            out = json.dumps(run_hook("post-compact", payload, env={"KT_CONFIG": str(config), "TMPDIR": tmp}))
            assert "planted/through-a-link.md" not in out, out[:300]
            ledger.unlink()
            ledger.write_text("regular/ledger-entry.md\n", encoding="utf-8")
            out = json.dumps(run_hook("post-compact", payload, env={"KT_CONFIG": str(config), "TMPDIR": tmp}))
            assert "regular/ledger-entry.md" in out, "control: a regular ledger is listed"
        finally:
            if ledger.is_symlink() or ledger.exists():
                ledger.unlink()


def test_codex_hook_carries_no_ranking_logic() -> None:
    source = read(PORT_ROOT / "bin" / "codex-hook.py")
    for retired in ("def tokenize(", "def index_section(", "len(tags) < 2", "ARIA ACTIVE - "):
        assert retired not in source, retired
    assert "aria-surface.sh" in source


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
            "last_setup_version: 2.46.2-codex.0\n"
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


def test_scope_line_is_not_a_pre_edit_marker() -> None:
    # v2.54.2: the POST-edit scope line ("[Rule 22 · Scope] PASS …") must not satisfy
    # the PRE-edit gate. Codex prompts for exactly that line after every edit, so an
    # agent answering each prompt used to pass the next edit's gate unassessed.
    hook = load_hook_module()
    for text in ("[Rule 22 · Scope] PASS - x", "[Rule 22 · scope] OK - planning doc",
                 "[Rule 22 · SCOPE] FAIL - x", "[Rule 22 · Scope check] PASS",
                 "[Rule 22 - Scope] PASS", "[Rule 22 ·  Scope] PASS", "[Rule 22·Scope] x"):
        assert not hook.has_rule22_marker(text), f"post-edit form accepted: {text!r}"
    for text in ("[Rule 22] Low Impact - x", "[Rule 22 · Planning] a.md",
                 "[Rule 22 · Batch 1/2] a.md", "[Rule 22 · Implementation] a.sh",
                 "[Rule 22 · Scoped change] a.sh"):
        assert hook.has_rule22_marker(text), f"pre-edit form rejected: {text!r}"


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


# Two Codex thread ids that share their first 8 characters. Codex ids are UUIDv7,
# whose leading characters are a timestamp, so sessions started close together
# share a prefix: measured, 37 of 57 local rollouts began `019e3929`.
OWN_ID = "019e3929-aaaa-7000-8000-00000000aaaa"
SIBLING_ID = "019e3929-bbbb-7000-8000-00000000bbbb"


def write_rollout(sessions: Path, thread_id: str, body: str, mtime: float, meta_id: str | None = None) -> Path:
    day = sessions / "2026" / "10" / "25"
    day.mkdir(parents=True, exist_ok=True)
    path = day / f"rollout-2026-10-25T10-00-00-{thread_id}.jsonl"
    meta = {"type": "session_meta", "payload": {"id": meta_id or thread_id}}
    path.write_text(json.dumps(meta, separators=(",", ":")) + "\n" + body + "\n", encoding="utf-8")
    os.utime(path, (mtime, mtime))
    return path


def run_save_transcript(home: Path, config: Path, env: dict[str, str], *args: str) -> subprocess.CompletedProcess[str]:
    run_env = {k: v for k, v in os.environ.items() if k not in {"CODEX_THREAD_ID", "CODEX_HOME", "CLAUDE_CODE_SESSION_ID"}}
    run_env.update({"HOME": str(home), "KT_CONFIG": str(config)})
    run_env.update(env)
    return subprocess.run(
        ["sh", str(PORT_ROOT / "bin" / "save-transcript.sh"), *args],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=run_env,
        check=False,
    )


def snapshot_fixture(root: Path) -> tuple[Path, Path, Path, Path]:
    home = root / "home"
    knowledge = root / "knowledge"
    knowledge.mkdir()
    config = root / "aria-config.md"
    write_config(config, knowledge)
    sessions = home / ".codex" / "sessions"
    write_rollout(sessions, OWN_ID, "OWN-SESSION", 1_000)
    # The sibling is newer, so a "newest rollout" picker would take it.
    write_rollout(sessions, SIBLING_ID, "SIBLING-SESSION", 2_000)
    return home, knowledge, config, knowledge / "intake" / "pre-compact-captures"


def test_snapshot_copies_this_codex_thread_not_the_newest_rollout() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        home, _, config, captures = snapshot_fixture(Path(tmp))
        proc = run_save_transcript(home, config, {"CODEX_THREAD_ID": OWN_ID})
        assert proc.returncode == 0, proc.stderr
        files = sorted(p.name for p in captures.glob("*.md"))
        assert len(files) == 1 and files[0].endswith("_0000aaaa.md"), files
        assert "OWN-SESSION" in read(captures / files[0])
        assert OWN_ID in proc.stdout and "GUESSED" not in proc.stdout

        # The sibling shares the first 8 characters; its capture must be a
        # separate file, not an overwrite of ours.
        proc = run_save_transcript(home, config, {"CODEX_THREAD_ID": SIBLING_ID})
        assert proc.returncode == 0, proc.stderr
        assert len(list(captures.glob("*.md"))) == 2
        assert "OWN-SESSION" in read(next(captures.glob("*_0000aaaa.md")))


def test_snapshot_reads_the_id_argument_and_codex_home() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        home, _, config, captures = snapshot_fixture(root)
        custom = root / "codex-home"
        write_rollout(custom / "sessions", OWN_ID, "CUSTOM-HOME", 3_000)
        proc = run_save_transcript(home, config, {"CODEX_HOME": str(custom)}, OWN_ID)
        assert proc.returncode == 0, proc.stderr
        assert "CUSTOM-HOME" in read(next(captures.glob("*_0000aaaa.md")))

        proc = run_save_transcript(home, config, {"CODEX_HOME": str(root / "absent")})
        assert proc.returncode == 1
        assert "CODEX_HOME" in proc.stderr


def test_snapshot_with_unknown_or_mismatched_id_writes_nothing() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        home, _, config, captures = snapshot_fixture(root)
        proc = run_save_transcript(home, config, {"CODEX_THREAD_ID": "019e3929-cccc-7000-8000-00000000cccc"})
        assert proc.returncode == 1
        assert "Nothing was written" in proc.stderr
        assert not list(captures.glob("*.md")) if captures.exists() else True

        # A file whose name carries the id but whose session_meta names another
        # thread is not this session's transcript.
        bad_id = "019e3929-dddd-7000-8000-00000000dddd"
        write_rollout(home / ".codex" / "sessions", bad_id, "RENAMED", 4_000, meta_id=SIBLING_ID)
        proc = run_save_transcript(home, config, {"CODEX_THREAD_ID": bad_id})
        assert proc.returncode == 1
        assert not list(captures.glob("*.md")) if captures.exists() else True


def test_snapshot_without_any_id_guesses_the_newest_and_says_so() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        home, _, config, captures = snapshot_fixture(Path(tmp))
        proc = run_save_transcript(home, config, {})
        assert proc.returncode == 0, proc.stderr
        assert "GUESSED" in proc.stdout
        assert "SIBLING-SESSION" in read(next(captures.glob("*_0000bbbb.md")))


def test_pre_compact_capture_uses_the_random_tail_of_the_thread_id() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        knowledge = root / "knowledge"
        knowledge.mkdir()
        config = root / "aria-config.md"
        write_config(config, knowledge)
        transcript = write_rollout(root / "sessions", OWN_ID, "OWN-SESSION", 1_000)
        run_hook(
            "pre-compact",
            {"hook_event_name": "PreCompact", "session_id": OWN_ID, "transcript_path": str(transcript)},
            env={"KT_CONFIG": str(config)},
        )
        names = [p.name for p in (knowledge / "intake" / "pre-compact-captures").glob("*.md")]
        assert len(names) == 1 and names[0].endswith("_0000aaaa.md"), names


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
