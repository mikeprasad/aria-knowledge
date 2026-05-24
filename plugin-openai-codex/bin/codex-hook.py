#!/usr/bin/env python3
"""Codex hook adapter for ARIA Knowledge."""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any


def emit(payload: dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(payload, separators=(",", ":")))


def run_legacy(script_name: str, hook_input: str) -> int:
    plugin_root = Path(os.environ["ARIA_CODEX_PLUGIN_ROOT"])
    script = plugin_root / "bin" / script_name
    if not script.exists():
        return 0
    proc = subprocess.run(
        ["sh", str(script)],
        input=hook_input,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=os.environ.copy(),
        check=False,
    )
    if proc.stdout:
        sys.stdout.write(proc.stdout)
    elif proc.stderr and proc.returncode != 0:
        sys.stderr.write(proc.stderr)
    return proc.returncode


def load_input() -> tuple[str, dict[str, Any]]:
    raw = sys.stdin.read()
    if not raw.strip():
        return raw, {}
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return raw, {}
    return raw, data if isinstance(data, dict) else {}


def nested_get(data: dict[str, Any], *keys: str) -> Any:
    cur: Any = data
    for key in keys:
        if not isinstance(cur, dict):
            return None
        cur = cur.get(key)
    return cur


def tool_name(data: dict[str, Any]) -> str:
    value = (
        data.get("tool_name")
        or nested_get(data, "invocation", "tool_name")
        or nested_get(data, "tool", "name")
        or data.get("name")
        or ""
    )
    return str(value)


def tool_input(data: dict[str, Any]) -> dict[str, Any]:
    value = (
        data.get("tool_input")
        or data.get("input")
        or data.get("arguments")
        or nested_get(data, "invocation", "input")
        or {}
    )
    return value if isinstance(value, dict) else {}


def last_assistant_text(data: dict[str, Any]) -> str:
    candidates = [
        data.get("last_assistant_message"),
        data.get("last_agent_message"),
        data.get("assistant_message"),
        nested_get(data, "turn_context", "last_assistant_message"),
    ]
    for candidate in candidates:
        if isinstance(candidate, str) and candidate.strip():
            return candidate
        if isinstance(candidate, list):
            parts: list[str] = []
            for item in candidate:
                if isinstance(item, str):
                    parts.append(item)
                elif isinstance(item, dict) and isinstance(item.get("text"), str):
                    parts.append(item["text"])
            if parts:
                return "\n".join(parts)

    transcript = data.get("transcript_path")
    if isinstance(transcript, str) and transcript:
        path = Path(transcript).expanduser()
        if path.exists():
            try:
                return "\n".join(path.read_text(errors="ignore").splitlines()[-80:])
            except OSError:
                return ""
    return ""


def has_rule22_marker(text: str) -> bool:
    return bool(re.search(r"\[Rule 22(?:\s*[·.-]\s*[^\]]+)?\]", text))


def hook_event(name: str, additional_context: str) -> dict[str, Any]:
    return {
        "hookSpecificOutput": {
            "hookEventName": name,
            "additionalContext": additional_context,
        }
    }


def deny(message: str) -> dict[str, Any]:
    return {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "additionalContext": message,
        },
        "systemMessage": message,
    }


def cwd_from(data: dict[str, Any]) -> Path:
    raw = data.get("cwd") or os.getcwd()
    return Path(str(raw)).expanduser()


def find_codemap(start: Path) -> Path | None:
    current = start if start.is_dir() else start.parent
    for _ in range(5):
        candidate = current / "CODEMAP.md"
        if candidate.exists():
            return candidate
        if current.parent == current:
            return None
        current = current.parent
    return None


def maybe_codemap_reminder(data: dict[str, Any], cmd: str) -> dict[str, Any] | None:
    first_word = cmd.strip().split(maxsplit=1)[0] if cmd.strip() else ""
    if first_word not in {"rg", "grep", "find"}:
        return None

    codemap = find_codemap(cwd_from(data))
    if codemap is None:
        return None

    session = str(data.get("session_id") or data.get("turn_id") or os.getpid())
    digest = hashlib.sha1(str(codemap.parent).encode()).hexdigest()[:12]
    ledger = Path("/tmp") / f"aria-codex-codemap-{session}-{digest}"
    if ledger.exists():
        return None
    try:
        ledger.write_text("seen\n")
    except OSError:
        pass

    return hook_event(
        "PreToolUse",
        f"ARIA: CODEMAP exists at {codemap}. Read its Directory section before broad exploration.",
    )


def writeish_exec_command(cmd: str) -> bool:
    lowered = cmd.lower()
    patterns = [" >", ">>", "tee ", "sed -i", "perl -i", "cat >", "cat <<"]
    return any(pattern in lowered for pattern in patterns)


def pre_tool_use(data: dict[str, Any]) -> None:
    name = tool_name(data)
    short_name = name.split(".")[-1]
    inputs = tool_input(data)
    last_text = last_assistant_text(data)

    if short_name == "apply_patch" or short_name.endswith("apply_patch"):
        if last_text and not has_rule22_marker(last_text):
            emit(
                deny(
                    "ARIA Rule 22: output the Low/High Impact decision block above the apply_patch call, then retry. The Codex port maps file edits to apply_patch."
                )
            )
        elif not last_text:
            emit(
                hook_event(
                    "PreToolUse",
                    "ARIA Rule 22: before apply_patch, output the Low/High Impact decision block above the tool call. Codex hook input did not expose prior assistant text, so this reminder is fail-open.",
                )
            )
        return

    if short_name == "exec_command" or short_name.endswith("exec_command"):
        cmd = str(inputs.get("cmd") or inputs.get("command") or "")
        reminder = maybe_codemap_reminder(data, cmd)
        if reminder is not None:
            emit(reminder)
            return
        if writeish_exec_command(cmd) and not has_rule22_marker(last_text):
            emit(
                hook_event(
                    "PreToolUse",
                    "ARIA: this shell command looks like it may write files. Prefer apply_patch for file edits, or output Rule 22 before any intentional write.",
                )
            )
        return


def post_tool_use(data: dict[str, Any]) -> None:
    name = tool_name(data)
    short_name = name.split(".")[-1]
    if short_name == "apply_patch" or short_name.endswith("apply_patch"):
        emit(
            hook_event(
                "PostToolUse",
                "POST-EDIT SCOPE CHECK - Output one line now: [Rule 22 · Scope] PASS|PASS CONDITIONAL|FAIL - verify scope held, no unrelated rewrites landed, and secondary impact on parents/siblings/dependents is understood.",
            )
        )


def main() -> int:
    event = sys.argv[1] if len(sys.argv) > 1 else ""
    raw, data = load_input()

    if event == "session-start":
        return run_legacy("session-start-check.sh", raw)
    if event == "pre-compact":
        return run_legacy("pre-compact-check.sh", raw)
    if event == "post-compact":
        return run_legacy("post-compact-check.sh", raw)
    if event == "pre-tool-use":
        pre_tool_use(data)
        return 0
    if event == "post-tool-use":
        post_tool_use(data)
        return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
