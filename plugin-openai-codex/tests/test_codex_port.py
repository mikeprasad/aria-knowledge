#!/usr/bin/env python3
"""Codex port parity checks.

These tests focus on Codex-specific packaging and adapter behavior. They are
kept inside plugin-openai-codex/ so they can evolve with the port without
modifying the cross-port test harness.
"""

from __future__ import annotations

import ast
import contextlib
import hashlib
import json
import importlib.util
import os
import re
import stat
import subprocess
import sys
import tempfile
import uuid
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
    expect_json: bool | None = True,
    timeout: float | None = None,
) -> dict[str, object]:
    """expect_json=None accepts either a JSON payload or no output at all ({})."""
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
        timeout=timeout,
        check=False,
    )
    assert proc.returncode == 0, proc.stderr
    if expect_json is None:
        return json.loads(proc.stdout) if proc.stdout.strip() else {}
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


def _system_temp_base() -> str:
    """The system temp root (macOS per-user temp dir, else /tmp), independent of $TMPDIR.

    For a fixture whose ASSERTION depends on living under a temp root: the bash-write resolver
    exempts /tmp and /var/folders by design, and $TMPDIR can point anywhere (measured 2026-11-14:
    TMPDIR inside a project made the temp-exemption check below fail for a reason unrelated to
    the hook)."""
    try:
        out = subprocess.run(["getconf", "DARWIN_USER_TEMP_DIR"], capture_output=True, text=True).stdout.strip()
    except OSError:
        out = ""
    return out if out and os.path.isdir(out) else "/tmp"


def test_pre_tool_use_shell_surfaces_preflight_warning() -> None:
    """Renamed 2026-08-26 when the STRING-matching pre-bash-write-check was retired.
    Its resolved-target REPLACEMENT is wired as of 2026-10-14 (see
    test_pre_tool_use_shell_records_in_place_write_to_bypass_ledger). This fixture's
    target lives under a temp directory, which the resolver exempts BY DESIGN, so
    "in place" must still be absent here — that is now a check of the temp exemption,
    not of the hook being unwired. The fixture is made under the SYSTEM temp root, not
    $TMPDIR, so the check holds wherever $TMPDIR points."""
    with tempfile.TemporaryDirectory(dir=_system_temp_base()) as tmp:
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
                # 2.58.0: the ledger lives in <base>/aria-knowledge-<uid>; KT_STATE_BASE outranks TMPDIR.
                env={"TMPDIR": str(ledger_dir), "KT_STATE_BASE": str(ledger_dir)},
                expect_json=expect_json,
            )
            hso = out.get("hookSpecificOutput", {}) if isinstance(out, dict) else {}
            return hso.get("additionalContext", "") if isinstance(hso, dict) else ""

        ledger = ledger_dir / f"aria-knowledge-{os.getuid()}" / f"aria-r22-bypass-{sid}"
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
    # F7 + (a) (final fix wave): the ledger name is predictable (aria-active-<session key>; in the private
    # state dir since 2.58.0, where ledger_is_ours is the second guard, spec D2). A link planted there
    # must not filter the surfaced files (a read) or receive the record (a write).
    prompt = "fix the payments webhooks flow"
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        config = _surfacing_setup(root)
        base = root / "state-base"
        base.mkdir()
        env = {"KT_CONFIG": str(config), "TMPDIR": tmp, "KT_STATE_BASE": str(base)}
        state_dir = base / _state_name()
        ledger = state_dir / f"aria-active-session-{root.name}"
        # The hook also keeps a 30 s per-session cooldown; clear it before each run so a silent run
        # is attributable to the ledger, never to the cooldown.
        cooldown = state_dir / f"aria-context-session-{root.name}"
        planted = root / "planted-ledger"

        def run(expect_json: bool = True) -> dict[str, object]:
            cooldown.unlink(missing_ok=True)
            return run_hook("user-prompt-submit", _prompt_payload(root, prompt), env=env, expect_json=expect_json)

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


def test_post_compact_does_not_list_a_linked_ledger() -> None:
    # F7 (final fix wave): post-compact-check.sh shows the ledger's lines to the model.
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        knowledge = root / "knowledge"
        knowledge.mkdir()
        config = root / "aria-config.md"
        write_config(config, knowledge)
        sid = f"codex-f7-{root.name}"
        # 2.58.0: post-compact-check.sh reads the ledger from the private state dir
        # (<KT_STATE_BASE>/aria-knowledge-<uid>), made here mode 700 so it can be planted first.
        base = root / "state-base"
        base.mkdir()
        state_dir = base / f"aria-knowledge-{os.getuid()}"
        state_dir.mkdir()
        state_dir.chmod(0o700)
        ledger = state_dir / f"aria-active-{sid}"
        hook_env = {"KT_CONFIG": str(config), "TMPDIR": tmp, "KT_STATE_BASE": str(base)}
        planted = root / "planted"
        planted.write_text("planted/through-a-link.md\n", encoding="utf-8")
        payload = {"hook_event_name": "PostCompact", "session_id": sid}
        try:
            if ledger.is_symlink() or ledger.exists():
                ledger.unlink()
            ledger.symlink_to(planted)
            out = json.dumps(run_hook("post-compact", payload, env=hook_env))
            assert "planted/through-a-link.md" not in out, out[:300]
            ledger.unlink()
            ledger.write_text("regular/ledger-entry.md\n", encoding="utf-8")
            out = json.dumps(run_hook("post-compact", payload, env=hook_env))
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


# --- 2.58.0: the private per-user state directory (aria_state_*) ---------------------------------
# Same contract as kt_state_* in lib-state-key.sh; tests/repros/state-dir-resolver.sh pins the two
# against each other (R_parity_py). Every test resolves under its own scratch KT_STATE_BASE.

class _StateEnv:
    """Set KT_STATE_BASE (and unset XDG_RUNTIME_DIR) for one block; restore everything after."""

    def __init__(self, base: Path, **extra: str | None) -> None:
        self.values: dict[str, str | None] = {"KT_STATE_BASE": str(base), "XDG_RUNTIME_DIR": None}
        self.values.update(extra)
        self.saved: dict[str, str | None] = {}

    def __enter__(self) -> None:
        for key, value in self.values.items():
            self.saved[key] = os.environ.get(key)
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value

    def __exit__(self, *exc: object) -> None:
        for key, value in self.saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


def _state_name() -> str:
    return f"aria-knowledge-{os.getuid()}"


def test_state_dir_accepts_a_fresh_base_with_mode_700() -> None:
    hook = load_hook_module()
    with tempfile.TemporaryDirectory() as tmp, _StateEnv(Path(tmp)):
        d, reason = hook.aria_state_resolve()
        assert reason == "" and d == Path(tmp) / _state_name(), (d, reason)
        st = os.lstat(d)
        assert (st.st_mode & 0o7777) == 0o700 and st.st_uid == os.getuid()
        assert hook.aria_state_dir() == d


def test_state_dir_refuses_link() -> None:
    hook = load_hook_module()
    with tempfile.TemporaryDirectory() as tmp, _StateEnv(Path(tmp) / "base"):
        target = Path(tmp) / "target"
        target.mkdir(mode=0o700)
        (Path(tmp) / "base").mkdir()
        (Path(tmp) / "base" / _state_name()).symlink_to(target)
        assert hook.aria_state_resolve() == (None, "is a link")
        assert hook.aria_state_dir() is None


def test_state_dir_refuses_mode_755() -> None:
    hook = load_hook_module()
    with tempfile.TemporaryDirectory() as tmp, _StateEnv(Path(tmp)):
        d = Path(tmp) / _state_name()
        d.mkdir()
        os.chmod(d, 0o755)
        assert hook.aria_state_resolve() == (None, "mode not 700")
        assert (os.lstat(d).st_mode & 0o777) == 0o755, "refusal must not chmod the directory"


def test_state_dir_refuses_file_at_name() -> None:
    hook = load_hook_module()
    with tempfile.TemporaryDirectory() as tmp, _StateEnv(Path(tmp)):
        (Path(tmp) / _state_name()).write_text("", encoding="utf-8")
        assert hook.aria_state_resolve() == (None, "not a directory")


def test_state_dir_refuses_unwritable_parent() -> None:
    if os.getuid() == 0:
        print("SKIP test_state_dir_refuses_unwritable_parent: root ignores mode 500")
        return
    hook = load_hook_module()
    with tempfile.TemporaryDirectory() as tmp:
        base = Path(tmp) / "ro"
        base.mkdir()
        os.chmod(base, 0o500)
        try:
            with _StateEnv(base):
                assert hook.aria_state_resolve() == (None, "not created")
        finally:
            os.chmod(base, 0o700)


def test_state_dir_refuses_foreign_owner() -> None:
    hook = load_hook_module()
    real_getuid = os.getuid
    fake = real_getuid() + 1
    with tempfile.TemporaryDirectory() as tmp, _StateEnv(Path(tmp)):
        hook.os.getuid = lambda: fake  # the module's os is the global os module
        try:
            d, reason = hook.aria_state_resolve()
        finally:
            hook.os.getuid = real_getuid
        assert (d, reason) == (None, "not owned by you"), (d, reason)
        assert (Path(tmp) / f"aria-knowledge-{fake}").is_dir()


def test_state_dir_mode_is_exact_under_umask() -> None:
    hook = load_hook_module()
    with tempfile.TemporaryDirectory() as tmp, _StateEnv(Path(tmp)):
        old = os.umask(0o777)
        try:
            d, reason = hook.aria_state_resolve()
        finally:
            os.umask(old)
        assert reason == "" and d is not None, reason
        assert (os.lstat(d).st_mode & 0o7777) == 0o700


def test_state_dir_never_falls_through() -> None:
    hook = load_hook_module()
    with tempfile.TemporaryDirectory() as tmp:
        broken = Path(tmp) / "broken"
        broken.mkdir()
        (broken / _state_name()).write_text("", encoding="utf-8")
        healthy_xdg = Path(tmp) / "xdg"
        healthy_tmp = Path(tmp) / "tmpdir"
        healthy_xdg.mkdir()
        healthy_tmp.mkdir()
        with _StateEnv(broken, XDG_RUNTIME_DIR=str(healthy_xdg), TMPDIR=str(healthy_tmp)):
            assert hook.aria_state_resolve() == (None, "not a directory")
        assert list(healthy_xdg.iterdir()) == [] and list(healthy_tmp.iterdir()) == []


def test_state_dir_refuses_acl() -> None:
    """G2-1: an ACL can grant access the mode bits do not show, so it is refused (fail safe)."""
    hook = load_hook_module()
    with tempfile.TemporaryDirectory() as tmp, _StateEnv(Path(tmp)):
        d = Path(tmp) / _state_name()
        d.mkdir(mode=0o700)
        if sys.platform == "darwin":
            cmd = ["chmod", "+a", "everyone allow list", str(d)]
        else:
            cmd = ["setfacl", "-m", "u:nobody:rx", str(d)]
        try:
            set_ok = subprocess.run(cmd, stderr=subprocess.DEVNULL, check=False).returncode == 0
        except OSError:
            set_ok = False
        if not set_ok:
            print("SKIP test_state_dir_refuses_acl: cannot set an ACL here")
            return
        assert hook.aria_state_resolve() == (None, "has an ACL")


def test_state_dir_unverifiable_permissions() -> None:
    """When the ACL check cannot be made, the reason says so — "mode not 700" would be false for
    a 0700 dir and invite a useless chmod. Forced here by an xattr read that fails with EIO."""
    import errno as _errno

    hook = load_hook_module()

    def failing_listxattr(*_args: object, **_kwargs: object) -> list[str]:
        raise OSError(_errno.EIO, "simulated xattr read failure")

    had = hasattr(hook.os, "listxattr")
    saved = getattr(hook.os, "listxattr", None)
    with tempfile.TemporaryDirectory() as tmp, _StateEnv(Path(tmp)):
        (Path(tmp) / _state_name()).mkdir(mode=0o700)
        hook.os.listxattr = failing_listxattr  # the module's os is the global os module
        try:
            result = hook.aria_state_resolve()
        finally:
            if had:
                hook.os.listxattr = saved
            else:
                del hook.os.listxattr
        assert result == (None, "permissions not verifiable"), result


def test_state_path_refuses_slash_dot_empty() -> None:
    hook = load_hook_module()
    d = Path("/nonexistent-state-dir")
    for name in ("a/../../x", "..", ".", "", "a/b"):
        assert hook.aria_state_path(d, name) is None, name
    assert hook.aria_state_path(None, "aria-active-x") is None
    assert hook.aria_state_path(d, "aria-active-x") == d / "aria-active-x"


# --- 2.58.0 Task 5: the Codex hook's own state lives in the private state dir (spec D7) -----------
# Its four names (aria-context-, aria-active-, aria-codex-codemap-, aria-session-inprogress-codex-)
# moved from /tmp into <KT_STATE_BASE>/aria-knowledge-<uid>; no state dir follows spec D3. Every test
# here resolves under its own scratch base and only READS the real /tmp and $TMPDIR (to prove no leak).

T5_PROMPT = "fix the payments webhooks flow"
T5_PATCH = "*** Begin Patch\n*** Add File: src/app.py\n+print('ok')\n*** End Patch\n"


@contextlib.contextmanager
def _env(**values: str | None):
    """Patch os.environ for one block (None unsets); restore everything after."""
    saved = {key: os.environ.get(key) for key in values}
    try:
        for key, value in values.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        yield
    finally:
        for key, value in saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


def _t5_key(label: str) -> str:
    return f"session-t5{label}-{uuid.uuid4().hex[:12]}"


def _real_tmp_names(key: str) -> list[str]:
    """Read-only scan of the real /tmp and $TMPDIR for entries whose name carries this test's key."""
    found: set[str] = set()
    for d in {"/tmp", os.environ.get("TMPDIR") or "/tmp", tempfile.gettempdir()}:
        try:
            names = os.listdir(d)
        except OSError:
            continue
        found.update(f"{d.rstrip('/')}/{n}" for n in names if key in n)
    return sorted(found)


def _tree_names(root: Path, key: str) -> list[str]:
    return sorted(str(p) for p in root.rglob("*") if key in p.name)


def _t5_config(root: Path) -> Path:
    """The surfacing fixture plus session_state, so one config drives all four names."""
    config = _surfacing_setup(root)
    write_config(
        config,
        root / "knowledge",
        "projects_enabled: true\nprojects_list: proj-a:proj-a,proj-b:proj-b,proj-c:proj-c\n"
        "session_state: true\nauthor_tag: codex-t5\n",
    )
    return config


def _t5_project(root: Path) -> Path:
    project = root / "project"
    (project / "src").mkdir(parents=True)
    (project / "AGENTS.md").write_text("# Project\n", encoding="utf-8")
    (project / "CODEMAP.md").write_text("# Codemap\n", encoding="utf-8")
    return project


def _t5_state_dir(base: Path) -> Path:
    base.mkdir(exist_ok=True)
    sdir = base / _state_name()
    sdir.mkdir()
    sdir.chmod(0o700)
    return sdir


def _ctx(output: object) -> str:
    hso = output.get("hookSpecificOutput", {}) if isinstance(output, dict) else {}
    return hso.get("additionalContext", "") if isinstance(hso, dict) else ""


def _t5_drive(project: Path, sid: str, env: dict[str, str], *, timeout: float | None = None) -> dict[str, str]:
    """Drive the three entry points that own the four names; return each one's additionalContext."""
    common = {"session_id": sid, "turn_id": "turn-t5", "cwd": str(project)}
    prompt = run_hook(
        "user-prompt-submit",
        {"hook_event_name": "UserPromptSubmit", "prompt": T5_PROMPT, **common},
        env=env, expect_json=None, timeout=timeout,
    )
    shell = run_hook(
        "pre-tool-use",
        {"hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": {"command": "rg payments"},
         "last_assistant_message": "No marker here.", **common},
        env=env, expect_json=None, timeout=timeout,
    )
    post = run_hook(
        "post-tool-use",
        {"hook_event_name": "PostToolUse", "tool_name": "apply_patch", "tool_input": {"command": T5_PATCH}, **common},
        env=env, expect_json=None, timeout=timeout,
    )
    return {"prompt": _ctx(prompt), "shell": _ctx(shell), "post": _ctx(post)}


def test_state_names_live_in_state_dir() -> None:
    sid = _t5_key("names")
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        config = _t5_config(root)
        project = _t5_project(root)
        base = root / "state-base"
        base.mkdir()
        sdir = base / _state_name()
        env = {"KT_CONFIG": str(config), "KT_STATE_BASE": str(base)}
        ctx = _t5_drive(project, sid, env)
        assert "ARIA ACTIVE" in ctx["prompt"], ctx
        assert "CODEMAP exists" in ctx["shell"], ctx
        assert "lastEvent: in-progress" in read(project / "SESSION.md")
        listing = sorted(p.name for p in sdir.iterdir()) if sdir.is_dir() else ["<no state dir>"]
        names = {
            "context": sdir / f"aria-context-{sid}",
            "active": sdir / f"aria-active-{sid}",
            "inprogress": sdir / f"aria-session-inprogress-codex-{sid}",
        }
        codemaps = sorted(sdir.glob(f"aria-codex-codemap-{sid}-*"))
        assert len(codemaps) == 1, listing
        names["codemap"] = codemaps[0]
        for label, path in names.items():
            assert path.exists(), (label, listing)
            st = os.lstat(path)
            assert stat.S_ISREG(st.st_mode) and (st.st_mode & 0o777) == 0o600, (label, oct(st.st_mode))
        assert str(project) in read(names["inprogress"])
        # One ledger for both languages: the Codex SHELL post-compact hook lists what the Python hook
        # recorded, because both resolve the same <state dir>/aria-active-<session_id>.
        first = read(names["active"]).splitlines()[0]
        post_compact = json.dumps(run_hook("post-compact", {"hook_event_name": "PostCompact", "session_id": sid}, env=env))
        assert first in post_compact, post_compact[:300]
        assert _real_tmp_names(sid) == [], _real_tmp_names(sid)


def test_no_state_dir_skips_surfacing_and_cooldown() -> None:
    hook = load_hook_module()
    sid = _t5_key("nostate")
    control_sid = _t5_key("control")
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        config = _t5_config(root)
        project = _t5_project(root)
        healthy = root / "healthy"
        healthy.mkdir()
        broken = root / "broken"
        broken.mkdir()
        (broken / _state_name()).write_text("", encoding="utf-8")  # spec D3: "not a directory"

        def prompt(base: Path, key: str) -> dict[str, object]:
            return run_hook(
                "user-prompt-submit",
                {"hook_event_name": "UserPromptSubmit", "session_id": key, "turn_id": "turn-t5",
                 "cwd": str(project), "prompt": T5_PROMPT},
                env={"KT_CONFIG": str(config), "KT_STATE_BASE": str(base)},
                expect_json=None,
            )

        def codemap(base: Path, key: str) -> object:
            payload = {"session_id": key, "cwd": str(project)}
            with _StateEnv(base):
                return hook.maybe_codemap_reminder(json.dumps(payload), payload, "rg payments")

        # Controls: with a state dir, the same inputs surface and remind -- so the silence below is
        # the missing directory, not a fixture that never fires.
        assert "ARIA ACTIVE" in _ctx(prompt(healthy, control_sid)), "control: surfacing fires"
        assert codemap(healthy, control_sid) is not None, "control: the codemap reminder fires"

        assert prompt(broken, sid) == {}, "no state dir: no ARIA ACTIVE, no CODEMAP line, nothing"
        assert codemap(broken, sid) is None, "no state dir: no codemap reminder"
        assert _tree_names(root, sid) == [], _tree_names(root, sid)
        assert _real_tmp_names(sid) == [], _real_tmp_names(sid)


def test_no_state_dir_still_marks_session_inprogress() -> None:
    sid = _t5_key("nostatemark")
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        config = _t5_config(root)
        project = _t5_project(root)
        broken = root / "broken"
        broken.mkdir()
        (broken / _state_name()).write_text("", encoding="utf-8")
        run_hook(
            "post-tool-use",
            {"hook_event_name": "PostToolUse", "session_id": sid, "turn_id": "turn-t5", "cwd": str(project),
             "tool_name": "apply_patch", "tool_input": {"command": T5_PATCH}},
            env={"KT_CONFIG": str(config), "KT_STATE_BASE": str(broken)},
        )
        session = read(project / "SESSION.md")
        assert "lastEvent: in-progress" in session and f"sessionId: {sid}" in session, session[:300]
        assert _tree_names(root, sid) == [], _tree_names(root, sid)  # no in-progress cache anywhere
        assert _real_tmp_names(sid) == [], _real_tmp_names(sid)


def test_state_name_with_slash_refused() -> None:
    """RF5: a session id holding "/" never addresses a path outside the state dir. Directories are
    planted at the first path component of each name, so a resolver that stopped refusing "/" WOULD
    reach <base>/x. A refused name is no usable state, so surfacing and the codemap reminder are
    silent, as in the shell ports (fix round 1, C3); the in-progress mark still happens."""
    sid = "a/../../x"
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        config = _t5_config(root)
        project = _t5_project(root)
        base = root / "state-base"
        sdir = _t5_state_dir(base)
        planted = ["aria-context-a", "aria-active-a", "aria-session-inprogress-codex-a", "aria-codex-codemap-a"]
        for name in planted:
            (sdir / name).mkdir()
        ctx = _t5_drive(project, sid, {"KT_CONFIG": str(config), "KT_STATE_BASE": str(base)})
        assert "ARIA ACTIVE" not in ctx["prompt"], ctx
        assert "CODEMAP" not in ctx["shell"], ctx
        assert "lastEvent: in-progress" in read(project / "SESSION.md")
        assert sorted(os.listdir(base)) == [_state_name()], sorted(os.listdir(base))
        for name in planted:
            assert list((sdir / name).iterdir()) == [], name


def test_fifo_at_a_state_name_is_no_state() -> None:
    """GUARD (green on 42e306c, whose names lived in /tmp; mutation-proven): a name that exists but is
    not a regular file is no state -- never read, never written, never blocked on (a FIFO would hang
    a plain open forever)."""
    sid = _t5_key("fifo")
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        config = _t5_config(root)
        project = _t5_project(root)
        base = root / "state-base"
        sdir = _t5_state_dir(base)
        digest = hashlib.sha1(str(project).encode()).hexdigest()[:12]
        fifos = [f"aria-context-{sid}", f"aria-active-{sid}", f"aria-session-inprogress-codex-{sid}",
                 f"aria-codex-codemap-{sid}-{digest}"]
        for name in fifos:
            os.mkfifo(sdir / name, 0o600)
        ctx = _t5_drive(project, sid, {"KT_CONFIG": str(config), "KT_STATE_BASE": str(base)}, timeout=30)
        assert "ARIA ACTIVE" in ctx["prompt"], ctx
        assert "CODEMAP exists" in ctx["shell"], ctx
        assert "lastEvent: in-progress" in read(project / "SESSION.md")
        for name in fifos:
            assert stat.S_ISFIFO(os.lstat(sdir / name).st_mode), name


def test_run_legacy_capture_survives_a_lone_surrogate() -> None:
    # A lone surrogate (valid in a JSON \u escape, invalid in UTF-8) made the text-mode encode raise
    # UnicodeEncodeError and crashed the hook; the surfacing call was fixed earlier (F4), this is the
    # same class at the legacy-script call.
    hook = load_hook_module()
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "bin").mkdir()
        (root / "bin" / "stub.sh").write_text("cat >/dev/null\nprintf ok\n", encoding="utf-8")
        with _env(ARIA_CODEX_PLUGIN_ROOT=str(root)):
            result = hook.run_legacy_capture("stub.sh", "\udcff")
    assert isinstance(result, tuple) and result[1] == "ok", result


def test_git_value_survives_a_missing_git() -> None:
    # Each text subprocess degrades to its caller's empty result when the program cannot start. Each
    # arm has a control with a working program, so the empty result is the missing program, not an
    # earlier return.
    hook = load_hook_module()
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        empty = root / "empty-path"
        empty.mkdir()
        stubs = root / "stubs"
        stubs.mkdir()
        (stubs / "git").write_text("#!/bin/sh\nprintf '5\\n'\n", encoding="utf-8")
        (stubs / "git").chmod(0o755)
        (root / "bin").mkdir()
        (root / "bin" / "stub.sh").write_text("printf ok\n", encoding="utf-8")
        data = {"cwd": tmp, "tool_response": {"stdout": "To origin\n   abc1234..def5678  main -> main\n"}}
        inputs = {"command": "git push origin main"}
        config = {"auto_retrospect": "nudge"}
        with _env(PATH=str(stubs)):
            assert hook.git_value(root, "rev-parse", "HEAD") == "5", "control: git_value reads git"
            assert "AUTO-RETROSPECT" in hook.auto_retrospect_message(data, inputs, config), "control"
        with _env(ARIA_CODEX_PLUGIN_ROOT=str(root)):
            assert hook.run_legacy_capture("stub.sh", "{}") == (0, "ok", ""), "control: sh runs the stub"
        with _env(PATH=str(empty), ARIA_CODEX_PLUGIN_ROOT=str(root)):
            assert hook.git_value(root, "rev-parse", "HEAD") == ""
            assert hook.auto_retrospect_message(data, inputs, config) == ""
            assert hook.run_legacy_capture("stub.sh", "{}") == (0, "", "")


def _text_runs_without_encoding(source: str) -> tuple[int, list[int]]:
    """(subprocess.run calls examined, lines of text-mode calls that name no encoding=)."""
    examined = 0
    flagged: list[int] = []
    for node in ast.walk(ast.parse(source)):
        if not (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == "run"
                and isinstance(node.func.value, ast.Name) and node.func.value.id == "subprocess"):
            continue
        examined += 1
        kws = {kw.arg: kw.value for kw in node.keywords if kw.arg}
        textish = any(isinstance(kws.get(k), ast.Constant) and kws[k].value is True for k in ("text", "universal_newlines"))
        if textish and "encoding" not in kws:
            flagged.append(node.lineno)
    return examined, flagged


def test_every_text_mode_subprocess_run_names_an_encoding() -> None:
    # Without encoding=, a text-mode run encodes with the locale: a non-UTF-8 locale or a lone
    # surrogate raises UnicodeEncodeError inside the hook.
    examined, flagged = _text_runs_without_encoding(read(PORT_ROOT / "bin" / "codex-hook.py"))
    assert examined > 0, "the walker examined no subprocess.run call"
    assert flagged == [], f"text-mode subprocess.run without encoding= at codex-hook.py lines {flagged}"
    # Positive controls: the walker flags the shape it exists to find, and passes the fixed shape.
    assert _text_runs_without_encoding('import subprocess\nsubprocess.run(["x"], text=True)\n') == (1, [2])
    assert _text_runs_without_encoding('import subprocess\nsubprocess.run(["x"], universal_newlines=True)\n') == (1, [2])
    assert _text_runs_without_encoding('import subprocess\nsubprocess.run(["x"], text=True, encoding="utf-8")\n') == (1, [])



def _text_file_io_without_encoding(source: str) -> tuple[int, list[int]]:
    """(text-mode read_text/write_text/open calls examined, lines that name no encoding=). Binary-mode
    opens and os.open are not text I/O and are not examined."""
    examined = 0
    flagged: list[int] = []
    for node in ast.walk(ast.parse(source)):
        if not isinstance(node, ast.Call):
            continue
        f = node.func
        kws = {kw.arg: kw.value for kw in node.keywords if kw.arg}
        if isinstance(f, ast.Attribute) and f.attr in ("read_text", "write_text"):
            pass
        elif isinstance(f, ast.Attribute) and f.attr == "open" and not (isinstance(f.value, ast.Name) and f.value.id == "os"):
            mode = node.args[0] if node.args else kws.get("mode")
            if isinstance(mode, ast.Constant) and "b" in str(mode.value):
                continue
        elif isinstance(f, ast.Name) and f.id == "open":
            mode = node.args[1] if len(node.args) > 1 else kws.get("mode")
            if isinstance(mode, ast.Constant) and "b" in str(mode.value):
                continue
        else:
            continue
        examined += 1
        if "encoding" not in kws:
            flagged.append(node.lineno)
    return examined, flagged


def test_every_text_file_read_and_write_names_an_encoding() -> None:
    # Without encoding=, Python uses the locale: under a non-UTF-8 locale a config path or a
    # SESSION.md line with non-ASCII text is misread (and SESSION.md is rewritten without it).
    examined, flagged = _text_file_io_without_encoding(read(PORT_ROOT / "bin" / "codex-hook.py"))
    assert examined > 0, "the walker examined no text file I/O"
    assert flagged == [], f"text file I/O without encoding= at codex-hook.py lines {flagged}"
    # Positive controls.
    assert _text_file_io_without_encoding("p.read_text()\n") == (1, [1])
    assert _text_file_io_without_encoding("p.write_text('x')\n") == (1, [1])
    assert _text_file_io_without_encoding("p.open('a')\n") == (1, [1])
    assert _text_file_io_without_encoding("open('x')\n") == (1, [1])
    assert _text_file_io_without_encoding("p.read_text(encoding='utf-8')\nopen('x', 'rb')\nos.open('x', 0)\n") == (1, [])


def test_session_md_keeps_non_ascii_text_under_a_c_locale() -> None:
    # The in-progress mark rewrites SESSION.md. Read with the locale and errors="ignore", a non-UTF-8
    # locale dropped every non-ASCII character (and any undecodable byte) from the user's file.
    sid = _t5_key("locale")
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        config = _t5_config(root)
        project = _t5_project(root)
        base = root / "state-base"
        base.mkdir()
        text = "Café — naïve résumé"
        (project / "SESSION.md").write_bytes(
            b"---\nlastEvent: handoff\n---\n\n## Where we left off\n\n" + text.encode("utf-8") + b"\nraw \xff byte\n"
        )
        env = {"KT_CONFIG": str(config), "KT_STATE_BASE": str(base),
               "LC_ALL": "C", "LANG": "C", "PYTHONUTF8": "0", "PYTHONCOERCECLOCALE": "0"}
        run_hook(
            "post-tool-use",
            {"hook_event_name": "PostToolUse", "session_id": sid, "turn_id": "turn-t5", "cwd": str(project),
             "tool_name": "apply_patch", "tool_input": {"command": T5_PATCH}},
            env=env,
        )
        after = (project / "SESSION.md").read_bytes()
        assert b"lastEvent: in-progress" in after, "control: the mark happened"
        assert text.encode("utf-8") in after and b"raw \xff byte" in after, after[-120:]


_PARITY_PY = """import importlib.util, sys
spec = importlib.util.spec_from_file_location("aria_codex_hook", sys.argv[1])
m = importlib.util.module_from_spec(spec); sys.dont_write_bytecode = True; spec.loader.exec_module(m)
d, reason = m.aria_state_resolve()
sys.stdout.write(("" if d is None else str(d)) + "\\n" + reason)"""

_PARITY_PY_BASE = """import importlib.util, sys
spec = importlib.util.spec_from_file_location("aria_codex_hook", sys.argv[1])
m = importlib.util.module_from_spec(spec); sys.dont_write_bytecode = True; spec.loader.exec_module(m)
sys.stdout.write(m.aria_state_base())"""

_PARITY_SH = '. "$1"; kt_state_resolve; printf "%s\\n%s" "$KT_STATE_DIR" "$KT_STATE_REASON"'


def _resolve_both(env: dict[str, str], *, python_first: bool = False) -> tuple[str, str]:
    full = {k: v for k, v in os.environ.items() if k not in ("KT_STATE_BASE", "XDG_RUNTIME_DIR", "TMPDIR")}
    full.update(env)

    def sh() -> str:
        return subprocess.run(
            ["sh", "-c", _PARITY_SH, "_", str(PORT_ROOT / "bin" / "lib-state-key.sh")], env=full,
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, encoding="utf-8", check=False,
        ).stdout

    def py() -> str:
        return subprocess.run(
            [sys.executable, "-I", "-c", _PARITY_PY, str(PORT_ROOT / "bin" / "codex-hook.py")], env=full,
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, encoding="utf-8", check=False,
        ).stdout

    if python_first:
        p = py()
        return sh(), p
    s = sh()
    return s, py()


def test_state_resolver_parity_sh_and_python() -> None:
    """GUARD (green on 42e306c; mutation-proven): given the same environment, the shell resolver
    (lib-state-key.sh) and the Python one (codex-hook.py) print the same directory and the same
    refusal reason, so a Codex Python hook and a Codex shell hook in one session share one directory
    and one ledger. "not owned by you" needs a second uid and is argued, not run here (the Python
    arm is test_state_dir_refuses_foreign_owner)."""
    name = _state_name()
    with tempfile.TemporaryDirectory() as tmp:
        t = Path(tmp)
        guard = t / "guard"  # TMPDIR in the base-override cases: a resolver that fell through would create here
        guard.mkdir()
        cases: list[tuple[str, dict[str, str], str, str, bool]] = []

        def nb(label: str) -> Path:
            b = t / label
            b.mkdir()
            return b

        b = nb("fresh-sh-first")
        cases.append(("fresh, sh creates", {"KT_STATE_BASE": f"{b}///", "TMPDIR": str(guard)}, f"{b}/{name}", "", False))
        b = nb("fresh-py-first")
        cases.append(("fresh, python creates", {"KT_STATE_BASE": str(b), "TMPDIR": str(guard)}, f"{b}/{name}", "", True))
        x, x2 = nb("xdg"), nb("xdg-tmpdir")
        cases.append(("XDG over TMPDIR", {"XDG_RUNTIME_DIR": str(x), "TMPDIR": str(x2)}, f"{x}/{name}", "", False))
        only = nb("tmpdir-only")
        cases.append(("TMPDIR only", {"TMPDIR": str(only)}, f"{only}/{name}", "", False))
        b = nb("link")
        target = t / "link-target"
        target.mkdir(mode=0o700)
        (b / name).symlink_to(target)
        cases.append(("link", {"KT_STATE_BASE": str(b), "TMPDIR": str(guard)}, "", "is a link", False))
        b = nb("file")
        (b / name).write_text("", encoding="utf-8")
        cases.append(("file", {"KT_STATE_BASE": str(b), "TMPDIR": str(guard)}, "", "not a directory", False))
        b = nb("mode755")
        (b / name).mkdir()
        os.chmod(b / name, 0o755)
        cases.append(("mode 755", {"KT_STATE_BASE": str(b), "TMPDIR": str(guard)}, "", "mode not 700", False))
        cases.append(("missing parent", {"KT_STATE_BASE": str(t / "missing" / "base"), "TMPDIR": str(guard)},
                      "", "not created", False))
        ro = None
        if os.getuid() != 0:
            ro = nb("ro")
            os.chmod(ro, 0o500)
            cases.append(("uncreatable parent", {"KT_STATE_BASE": str(ro), "TMPDIR": str(guard)}, "", "not created", False))
        b = nb("acl")
        (b / name).mkdir(mode=0o700)
        acl_cmd = (["chmod", "+a", "everyone allow list", str(b / name)] if sys.platform == "darwin"
                   else ["setfacl", "-m", "u:nobody:rx", str(b / name)])
        try:
            acl_ok = subprocess.run(acl_cmd, stderr=subprocess.DEVNULL, check=False).returncode == 0
        except OSError:
            acl_ok = False
        if acl_ok:
            cases.append(("ACL", {"KT_STATE_BASE": str(b), "TMPDIR": str(guard)}, "", "has an ACL", False))
        else:
            print("SKIP parity ACL case: cannot set an ACL here")
        if sys.platform == "darwin":
            # Both read the ACL with one `ls` on macOS; a broken ls must say the permissions could not
            # be verified in both. (Off Darwin, Python reads xattrs instead of running ls, so a broken
            # ls is not a shared input there.)
            b = nb("unverifiable")
            (b / name).mkdir(mode=0o700)
            stub = nb("stub-ls")
            (stub / "ls").write_text("#!/bin/sh\nexit 1\n", encoding="utf-8")
            (stub / "ls").chmod(0o755)
            cases.append(("unverifiable", {"KT_STATE_BASE": str(b), "TMPDIR": str(guard),
                                           "PATH": f"{stub}:/usr/bin:/bin"}, "", "permissions not verifiable", False))
            # Overlapping failures: the shell's `ls` read comes before its owner and mode checks, so an
            # unreadable result outranks "mode not 700" in both.
            b = nb("unverifiable-755")
            (b / name).mkdir()
            os.chmod(b / name, 0o755)
            cases.append(("unverifiable + mode 755", {"KT_STATE_BASE": str(b), "TMPDIR": str(guard),
                                                     "PATH": f"{stub}:/usr/bin:/bin"}, "", "permissions not verifiable", False))
            # An `ls` that exits 0 and prints nothing is unreadable too.
            b = nb("empty-ls")
            (b / name).mkdir(mode=0o700)
            os.chmod(b / name, 0o700)
            empty = nb("stub-ls-empty")
            (empty / "ls").write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            (empty / "ls").chmod(0o755)
            cases.append(("empty ls output", {"KT_STATE_BASE": str(b), "TMPDIR": str(guard),
                                             "PATH": f"{empty}:/usr/bin:/bin"}, "", "permissions not verifiable", False))
        try:
            for label, env, want_dir, want_reason, python_first in cases:
                sh_out, py_out = _resolve_both(env, python_first=python_first)
                want = f"{want_dir}\n{want_reason}"
                assert sh_out == want and py_out == want, (label, sh_out, py_out, want)
        finally:
            if ro is not None:
                os.chmod(ro, 0o700)
        assert list(guard.iterdir()) == [], "a resolver fell through to TMPDIR"
        # All three base variables unset: the base is the platform's (Darwin: getconf
        # DARWIN_USER_TEMP_DIR in sh, os.confstr(65537) in Python; else /tmp). That is the user's REAL
        # base, so only the computed base STRING is compared (kt_state_base / aria_state_base, which
        # never mkdir) -- creation there is not exercised.
        full = {k: v for k, v in os.environ.items() if k not in ("KT_STATE_BASE", "XDG_RUNTIME_DIR", "TMPDIR")}
        sh_base = subprocess.run(
            ["sh", "-c", '. "$1"; kt_state_base', "_", str(PORT_ROOT / "bin" / "lib-state-key.sh")], env=full,
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, encoding="utf-8", check=False,
        ).stdout.strip()
        py_base = subprocess.run(
            [sys.executable, "-I", "-c", _PARITY_PY_BASE, str(PORT_ROOT / "bin" / "codex-hook.py")], env=full,
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, encoding="utf-8", check=False,
        ).stdout.strip()
        assert sh_base and sh_base == py_base, ("all unset", sh_base, py_base)
        if sys.platform != "darwin":
            assert sh_base == "/tmp", sh_base


# --- Fix round 1: a session id the filesystem cannot encode, and output under a non-UTF-8 locale ----
SESSION_BEFORE = b"---\nlastEvent: handoff\n---\n\n## Where we left off\n\nkeep this text intact.\n"


def _surrogate_post(project: Path, env: dict[str, str]) -> None:
    # json.dumps escapes the lone surrogate as \ud800, which the hook decodes back into one.
    run_hook(
        "post-tool-use",
        {"hook_event_name": "PostToolUse", "session_id": "\ud800abc", "turn_id": "turn-t5", "cwd": str(project),
         "tool_name": "apply_patch", "tool_input": {"command": T5_PATCH}},
        env=env,
    )


def _assert_marked_without_the_id(project: Path) -> None:
    # 2.58.0 fix round 1: a surrogate session_id is a REJECTED id (session_key), so the project is marked
    # anyway (spec D3, as for "/" in test_state_name_with_slash_refused) with NO session id -- the
    # fixture carries no sessionId line, so writing the raw id would add one. The body survives intact.
    after = (project / "SESSION.md").read_text(encoding="utf-8")
    assert after.startswith("---\nlastEvent: in-progress\n"), after
    assert "keep this text intact." in after, after
    assert "sessionId:" not in after, after
    assert [p.name for p in project.iterdir() if p.name.startswith(".SESSION.md.")] == [], "temp file left"


def test_surrogate_session_id_without_state_dir_marks_without_the_id() -> None:
    # I1: write_text opened SESSION.md for writing (truncating it) and THEN failed to encode the lone
    # surrogate (surrogateescape carries only U+DC80-DCFF): the hook exited 1 and SESSION.md was empty.
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        config = _t5_config(root)
        project = _t5_project(root)
        broken = root / "broken"
        broken.mkdir()
        (broken / _state_name()).write_text("", encoding="utf-8")
        (project / "SESSION.md").write_bytes(SESSION_BEFORE)
        _surrogate_post(project, {"KT_CONFIG": str(config), "KT_STATE_BASE": str(broken)})  # asserts exit 0
        _assert_marked_without_the_id(project)


def test_surrogate_session_id_with_state_dir_exits_0() -> None:
    # I1: with a state dir the same id crashed earlier, in state_read (os.open on an unencodable name).
    # The name is refused, so this is no usable state: silent, as for an id holding "/" (C3); the
    # in-progress mark still happens, without the id (spec D3).
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        config = _t5_config(root)
        project = _t5_project(root)
        base = root / "state-base"
        base.mkdir()
        (project / "SESSION.md").write_bytes(SESSION_BEFORE)
        env = {"KT_CONFIG": str(config), "KT_STATE_BASE": str(base)}
        ctx = _t5_drive(project, "\ud800abc", env)  # each call asserts exit 0
        assert "ARIA ACTIVE" not in ctx["prompt"], ctx
        assert "CODEMAP" not in ctx["shell"], ctx
        _assert_marked_without_the_id(project)


def test_state_helpers_treat_an_unencodable_name_as_no_state() -> None:
    hook = load_hook_module()
    with tempfile.TemporaryDirectory() as tmp:
        bad = Path(tmp) / "aria-active-\ud800"
        assert hook.state_read(bad) is None
        assert hook.state_write(bad, "x") is False
        assert hook.ledger_is_ours(bad) is False
        assert hook.aria_state_path(Path(tmp), "aria-active-\ud800") is None
        assert hook.aria_state_path(Path(tmp), "aria-active-ok") == Path(tmp) / "aria-active-ok"  # control


def test_hook_output_survives_a_non_utf8_locale() -> None:
    # A legacy script's non-ASCII output was written to sys.stdout with the locale's codec: under a C
    # locale (ascii) the hook exited 1 with UnicodeEncodeError. It is now written as UTF-8 bytes.
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "bin").mkdir()
        (root / "bin" / "session-start-check.sh").write_text(
            'cat >/dev/null\nprintf "caf\\303\\251 \\342\\200\\224\\n"\n', encoding="utf-8")
        env = {**os.environ, "ARIA_CODEX_PLUGIN_ROOT": str(root), "KT_STATE_BASE": tmp,
               "LC_ALL": "C", "LANG": "C", "PYTHONUTF8": "0", "PYTHONCOERCECLOCALE": "0"}
        proc = subprocess.run([sys.executable, str(PORT_ROOT / "bin" / "codex-hook.py"), "session-start"],
                              input=b"{}", stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, check=False)
        assert proc.returncode == 0, proc.stderr.decode("utf-8", "replace")[-300:]
        assert proc.stdout == "café —\n".encode("utf-8"), proc.stdout


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
