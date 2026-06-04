#!/usr/bin/env python3
"""Codex hook adapter for ARIA Knowledge."""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def emit(payload: dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(payload, separators=(",", ":")))


def run_legacy_capture(script_name: str, hook_input: str, cwd: Path | None = None) -> tuple[int, str, str]:
    plugin_root = Path(os.environ["ARIA_CODEX_PLUGIN_ROOT"])
    script = plugin_root / "bin" / script_name
    if not script.exists():
        return 0, "", ""
    proc = subprocess.run(
        ["sh", str(script)],
        input=hook_input,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=os.environ.copy(),
        cwd=str(cwd) if cwd else None,
        check=False,
    )
    return proc.returncode, proc.stdout, proc.stderr


def run_legacy(script_name: str, hook_input: str) -> int:
    returncode, stdout, stderr = run_legacy_capture(script_name, hook_input)
    if stdout:
        sys.stdout.write(stdout)
    elif stderr and returncode != 0:
        sys.stderr.write(stderr)
    return returncode


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


def tool_response(data: dict[str, Any]) -> Any:
    return (
        data.get("tool_response")
        or data.get("response")
        or nested_get(data, "invocation", "response")
        or {}
    )


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
                return transcript_assistant_text(path, str(data.get("turn_id") or ""))
            except OSError:
                return ""
    return ""


def extract_text(value: Any) -> str:
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        parts: list[str] = []
        for item in value:
            if isinstance(item, str):
                parts.append(item)
            elif isinstance(item, dict):
                if isinstance(item.get("text"), str):
                    parts.append(item["text"])
                elif isinstance(item.get("content"), str):
                    parts.append(item["content"])
        return "\n".join(parts)
    if isinstance(value, dict):
        for key in ("text", "content", "message"):
            text = extract_text(value.get(key))
            if text:
                return text
    return ""


def transcript_assistant_text(path: Path, turn_id: str) -> str:
    """Best-effort transcript reader.

    Codex documents transcript_path as convenient but unstable. Keep this
    conservative: prefer events from the active turn_id, and fall back to an
    empty string instead of scanning prior turns where stale Rule 22 markers can
    create false compliance.
    """
    if not turn_id:
        return ""

    texts: list[str] = []
    for line in path.read_text(errors="ignore").splitlines():
        try:
            evt = json.loads(line)
        except json.JSONDecodeError:
            continue
        if turn_id and str(evt.get("turn_id") or "") != turn_id:
            continue
        role = evt.get("role") or evt.get("type") or nested_get(evt, "message", "role")
        if role != "assistant":
            continue
        text = (
            extract_text(evt.get("content"))
            or extract_text(nested_get(evt, "message", "content"))
            or extract_text(evt.get("message"))
        )
        if text:
            texts.append(text)
    return "\n".join(texts)


def has_rule22_marker(text: str) -> bool:
    return bool(re.search(r"\[Rule 22(?:\s*[·.-]\s*[^\]]+)?\]", text))


def hook_event(name: str, additional_context: str) -> dict[str, Any]:
    return {
        "hookSpecificOutput": {
            "hookEventName": name,
            "additionalContext": additional_context,
        }
    }


def config_path() -> Path:
    raw = os.environ.get("KT_CONFIG")
    if raw:
        return Path(raw).expanduser()
    shared = Path.home() / ".claude" / "aria-knowledge.local.md"
    if shared.exists():
        return shared
    return Path.home() / ".codex" / "aria-knowledge.local.md"


def read_config() -> dict[str, str]:
    path = config_path()
    if not path.exists():
        return {}
    text = path.read_text(errors="ignore")
    match = re.search(r"^---\n(.*?)\n---", text, re.S | re.M)
    if not match:
        return {}
    fields: dict[str, str] = {}
    for line in match.group(1).splitlines():
        if not line or line.startswith(" ") or ":" not in line:
            continue
        key, value = line.split(":", 1)
        fields[key.strip()] = value.strip()
    return fields


def config_value(config: dict[str, str], key: str, default: str = "") -> str:
    value = config.get(key, "").strip()
    return value if value else default


def config_bool(config: dict[str, str], key: str, default: bool) -> bool:
    raw = config_value(config, key, "true" if default else "false").lower()
    if raw == "true":
        return True
    if raw == "false":
        return False
    return default


def deny(message: str) -> dict[str, Any]:
    return {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": message,
        },
        "systemMessage": message,
    }


def cwd_from(data: dict[str, Any]) -> Path:
    raw = data.get("cwd") or os.getcwd()
    return Path(str(raw)).expanduser()


def session_key(data: dict[str, Any]) -> str:
    return str(data.get("session_id") or data.get("turn_id") or os.getpid())


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


def index_section(index_text: str) -> str:
    in_section = False
    lines: list[str] = []
    for line in index_text.splitlines():
        if line == "## Tag Index":
            in_section = True
            continue
        if in_section and line.startswith("## "):
            break
        if in_section:
            lines.append(line)
    return "\n".join(lines)


def tokenize(text: str) -> set[str]:
    return set(re.findall(r"[a-z0-9]+", text.lower()))


def active_context_matches(prompt: str, knowledge_folder: Path) -> tuple[list[str], list[str]]:
    index = knowledge_folder / "index.md"
    if not index.exists():
        return [], []

    section = index_section(index.read_text(errors="ignore"))
    words = tokenize(prompt)
    if not words:
        return [], []

    tags: list[str] = []
    current = ""
    entries_by_tag: dict[str, list[str]] = {}
    for line in section.splitlines():
        if line.startswith("### "):
            current = line[4:].strip().lower()
            entries_by_tag.setdefault(current, [])
            if current in words:
                tags.append(current)
            continue
        if current and line.startswith("- "):
            entries_by_tag.setdefault(current, []).append(line[2:].strip())

    tags = sorted(set(tags))
    if len(tags) < 2:
        return [], []

    files: list[str] = []
    seen_paths: set[str] = set()
    for tag in tags:
        for entry in entries_by_tag.get(tag, []):
            path = entry.split(" — ", 1)[0]
            if path in seen_paths:
                continue
            seen_paths.add(path)
            files.append(entry)
            if len(files) >= 5:
                return tags, files
    return tags, files


def codemap_artifact_message(start: Path, config: dict[str, str]) -> tuple[str, list[str]]:
    codemap = find_codemap(start)
    if codemap is None:
        return "", []
    if config_bool(config, "active_knowledge_surfacing", True):
        return (
            f"[aria] CODEMAP exists at {codemap}. Read its Directory section before broad exploration. ",
            [str(codemap)],
        )
    return (
        f"[aria] CODEMAP available at {codemap}. Consider reading its Directory section before broad exploration. ",
        [str(codemap)],
    )


def ledger_filter(items: list[str], ledger: Path) -> list[str]:
    if not ledger.exists() or not ledger.read_text(errors="ignore").strip():
        return items
    seen = set(ledger.read_text(errors="ignore").splitlines())
    return [item for item in items if item.split(" — ", 1)[0] not in seen and item not in seen]


def ledger_record(items: list[str], ledger: Path) -> None:
    if not items:
        return
    with ledger.open("a", encoding="utf-8") as fp:
        for item in items:
            fp.write(item.split(" — ", 1)[0] + "\n")


def user_prompt_submit(data: dict[str, Any]) -> None:
    config = read_config()
    knowledge_folder_raw = config_value(config, "knowledge_folder")
    if not knowledge_folder_raw or config_value(config, "auto_capture", "true") == "false":
        return

    knowledge_folder = Path(knowledge_folder_raw).expanduser()
    if not knowledge_folder.is_dir():
        return

    prompt = str(data.get("prompt") or "")
    if not prompt.strip():
        return

    key = session_key(data)
    cooldown = Path("/tmp") / f"aria-context-{key}"
    if cooldown.exists():
        try:
            elapsed = int(datetime.now(timezone.utc).timestamp()) - int(cooldown.read_text(errors="ignore").strip())
            if elapsed < 30:
                return
        except ValueError:
            pass

    active = config_bool(config, "active_knowledge_surfacing", True)
    ledger = Path("/tmp") / f"aria-active-{key}"
    tags, files = active_context_matches(prompt, knowledge_folder)
    artifacts_message, artifacts = codemap_artifact_message(cwd_from(data), config)

    if active:
        files = ledger_filter(files, ledger)
        artifacts = ledger_filter(artifacts, ledger)
        if not artifacts:
            artifacts_message = ""

    messages: list[str] = []
    if files:
        file_list = " ".join(f"  - {item};" for item in files).rstrip(";")
        if active:
            messages.append(
                f"ARIA ACTIVE - {len(files)} knowledge file(s) match this prompt (tags: {' '.join(tags)}). "
                f"Read each, then summarize what loaded in 1-2 sentences before proceeding. Files: {file_list}. "
                "(Recorded to session ledger - won't re-surface.)"
            )
        else:
            messages.append(
                f"ARIA: Found {len(files)} relevant knowledge file(s) matching tags: {' '.join(tags)}. "
                f"{file_list}. Run /context {' '.join(tags)} to load, or proceed without."
            )

    if artifacts_message:
        messages.append(artifacts_message.strip())

    if not messages:
        return

    try:
        cooldown.write_text(str(int(datetime.now(timezone.utc).timestamp())))
        if active:
            ledger_record(files, ledger)
            ledger_record(artifacts, ledger)
    except OSError:
        pass

    emit(hook_event("UserPromptSubmit", " ".join(messages)))


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


def command_from_inputs(inputs: dict[str, Any]) -> str:
    return str(inputs.get("cmd") or inputs.get("command") or "")


def parse_apply_patch_files(command: str) -> list[str]:
    paths: list[str] = []
    for line in command.splitlines():
        for prefix in ("*** Add File: ", "*** Update File: ", "*** Delete File: ", "*** Move to: "):
            if line.startswith(prefix):
                path = line[len(prefix) :].strip()
                if path and path not in paths:
                    paths.append(path)
    return paths


def is_apply_patch_tool(short_name: str) -> bool:
    return short_name in {"apply_patch", "Edit", "Write"} or short_name.endswith("apply_patch")


def is_shell_tool(short_name: str) -> bool:
    return short_name in {"Bash", "exec_command"} or short_name.endswith("exec_command")


def is_planning_path(path: str) -> bool:
    return bool(
        re.search(r"/docs/(specs|plans)/.+", f"/{path}")
        or re.search(r"/docs/superpowers/(specs|plans)/.+", f"/{path}")
    )


def is_auto_prospect_path(path: str) -> bool:
    return bool(
        re.search(r"/docs/plans/[^/]+\.md$", f"/{path}")
        or re.search(r"/docs/superpowers/plans/[^/]+\.md$", f"/{path}")
    )


def is_protected_path(path: str, config: dict[str, str]) -> bool:
    basename = Path(path).name
    if basename in {
        "AGENTS.md",
        "CLAUDE.md",
        "working-rules.md",
        "change-decision-framework.md",
        "enforcement-mechanisms.md",
        "settings.local.json",
        "plugin.json",
    }:
        return True

    knowledge_folder = config_value(config, "knowledge_folder")
    if knowledge_folder and str(Path(path).expanduser()).startswith(knowledge_folder):
        return True

    critical_paths = config_value(config, "critical_paths")
    if critical_paths:
        normalized = f"/{path}"
        for pattern in critical_paths.split(","):
            prefix = pattern.strip().rstrip("*").rstrip("/")
            if prefix and f"/{prefix}/" in normalized:
                return True
    return False


def scope_message(paths: list[str], config: dict[str, str]) -> str:
    if paths and all(is_planning_path(path) for path in paths) and not any(
        is_protected_path(path, config) for path in paths
    ):
        return "PLANNING PATH - abbreviated scope check. Output: [Rule 22 · Scope] OK - planning doc."
    return (
        "POST-EDIT SCOPE CHECK - Output one line now: [Rule 22 · Scope] PASS|PASS CONDITIONAL|FAIL - "
        "verify scope held, no unrelated rewrites landed, and secondary impact on parents/siblings/dependents is understood."
    )


def auto_prospect_message(paths: list[str], config: dict[str, str]) -> str:
    mode = config_value(config, "auto_prospect", "off")
    if mode not in {"nudge", "run"}:
        return ""
    plan_paths = [path for path in paths if is_auto_prospect_path(path)]
    if not plan_paths:
        return ""
    joined = ", ".join(plan_paths)
    if mode == "run":
        return f"AUTO-PROSPECT (run): plan file written at {joined}. Run /prospect file {plan_paths[0]} inline now, before any execution."
    return f"AUTO-PROSPECT (nudge): plan file written at {joined}. Offer to run /prospect file {plan_paths[0]} before execution and ask the user (do not auto-run)."


def absolute_touched_path(path: str, data: dict[str, Any]) -> Path:
    raw = Path(path).expanduser()
    if raw.is_absolute():
        return raw
    return (cwd_from(data) / raw).resolve()


def find_session_root(path: Path) -> Path | None:
    current = path if path.is_dir() else path.parent
    home = Path.home()
    while current != current.parent:
        if any((current / marker).exists() for marker in ("AGENTS.md", "CLAUDE.md", "PROGRESS.md")):
            if current.parent == home:
                return None
            return current
        if current == home:
            return None
        current = current.parent
    return None


def git_value(root: Path, *args: str) -> str:
    proc = subprocess.run(
        ["git", "-C", str(root), *args],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return proc.stdout.strip() if proc.returncode == 0 else ""


def split_frontmatter(text: str) -> tuple[dict[str, str], str] | None:
    if not text.startswith("---\n"):
        return None
    end = text.find("\n---\n", 4)
    if end == -1:
        return None
    fields: dict[str, str] = {}
    for line in text[4:end].splitlines():
        if ":" in line and not line.startswith(" "):
            key, value = line.split(":", 1)
            fields[key.strip()] = value.strip()
    return fields, text[end + 5 :]


def mark_session_inprogress(root: Path, session_id: str, author: str) -> None:
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    branch = git_value(root, "rev-parse", "--abbrev-ref", "HEAD")
    head = git_value(root, "rev-parse", "--short", "HEAD")
    session_file = root / "SESSION.md"
    body = ""
    fields: dict[str, str] = {}
    if session_file.exists():
        parsed = split_frontmatter(session_file.read_text(errors="ignore"))
        if parsed:
            fields, body = parsed
        else:
            body = "\n" + session_file.read_text(errors="ignore")

    fields["lastEvent"] = "in-progress"
    fields["at"] = now
    fields.setdefault("currentFocus", "")
    fields.setdefault("nextAction", "")
    if branch:
        fields["branch"] = branch
    if head:
        fields["headCommit"] = head
    if author:
        fields.setdefault("by", author)
    if session_id:
        fields["sessionId"] = session_id

    ordered = ["lastEvent", "at", "currentFocus", "nextAction", "branch", "headCommit", "by", "sessionId"]
    lines = ["---"]
    for key in ordered:
        if key in fields:
            lines.append(f"{key}: {fields[key]}")
    for key, value in fields.items():
        if key not in ordered:
            lines.append(f"{key}: {value}")
    lines.append("---")
    if body.strip():
        content = "\n".join(lines) + "\n" + body
    else:
        content = "\n".join(lines) + "\n\n## Where we left off\n\n(session in progress)\n"
    session_file.write_text(content)

    if git_value(root, "rev-parse", "--git-dir"):
        ignored = subprocess.run(
            ["git", "-C", str(root), "check-ignore", "-q", "SESSION.md"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        if ignored.returncode != 0:
            with (root / ".gitignore").open("a", encoding="utf-8") as fp:
                fp.write("SESSION.md\n")


def maybe_mark_session_state(paths: list[str], data: dict[str, Any], config: dict[str, str]) -> None:
    if config_value(config, "session_state", "false") != "true":
        return
    session_id = str(data.get("session_id") or data.get("turn_id") or "")
    author = config_value(config, "author_tag")
    key = session_id or hashlib.sha1(str(data.get("transcript_path") or os.getpid()).encode()).hexdigest()[:12]
    ledger = Path("/tmp") / f"aria-session-inprogress-codex-{key}"
    seen = set(ledger.read_text(errors="ignore").splitlines()) if ledger.exists() else set()
    for path in paths:
        if Path(path).name == "SESSION.md":
            continue
        root = find_session_root(absolute_touched_path(path, data))
        if root is None or str(root) in seen:
            continue
        try:
            mark_session_inprogress(root, session_id, author)
            seen.add(str(root))
        except OSError:
            continue
    try:
        ledger.write_text("\n".join(sorted(seen)) + ("\n" if seen else ""))
    except OSError:
        pass


def response_text(value: Any) -> str:
    if isinstance(value, str):
        return value
    if isinstance(value, dict):
        parts: list[str] = []
        for key in ("stderr", "stdout", "output", "text", "content"):
            text = extract_text(value.get(key))
            if text:
                parts.append(text)
        return "\n".join(parts) if parts else json.dumps(value)
    return extract_text(value)


def auto_retrospect_message(data: dict[str, Any], inputs: dict[str, Any], config: dict[str, str]) -> str:
    mode = config_value(config, "auto_retrospect", "off")
    if mode not in {"nudge", "run"}:
        return ""
    command = command_from_inputs(inputs)
    if "git push" not in command:
        return ""
    if re.search(r"(^|\s)(--force|-f|--force-with-lease)(\s|$)", command):
        return ""
    text = response_text(tool_response(data)).replace("\\n", "\n")
    match = re.search(r"([0-9a-f]{7,40}\.\.[0-9a-f]{7,40})", text)
    if not match:
        return ""
    range_value = match.group(1)
    branch_match = re.search(r"->\s+([A-Za-z0-9._/-]+)", text)
    branch = branch_match.group(1) if branch_match else ""
    branches = config_value(config, "retrospect_branches", "main,master,production").replace(" ", "")
    if branch and branches and branch not in branches.split(","):
        return ""
    min_commits_raw = config_value(config, "retrospect_min_commits", "3")
    min_commits = int(min_commits_raw) if min_commits_raw.isdigit() else 3
    count_proc = subprocess.run(
        ["git", "rev-list", "--count", range_value],
        cwd=str(cwd_from(data)),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if count_proc.returncode != 0 or not count_proc.stdout.strip().isdigit():
        return ""
    count = int(count_proc.stdout.strip())
    if count < min_commits:
        return ""
    if mode == "run":
        return f"AUTO-RETROSPECT (run): pushed {count} commits ({range_value}) to {branch}. Run /retrospect range {range_value} inline now."
    return f"AUTO-RETROSPECT (nudge): pushed {count} commits ({range_value}) to {branch}. Offer to run /retrospect range {range_value} and ask the user (do not auto-run)."


def pre_tool_use(data: dict[str, Any]) -> None:
    name = tool_name(data)
    short_name = name.split(".")[-1]
    inputs = tool_input(data)
    last_text = last_assistant_text(data)

    if is_apply_patch_tool(short_name):
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

    if is_shell_tool(short_name):
        cmd = command_from_inputs(inputs)
        shell_payload = dict(data)
        shell_payload["command"] = cmd
        returncode, stdout, stderr = run_legacy_capture(
            "bash-cd-check.sh",
            json.dumps(shell_payload),
            cwd_from(data),
        )
        if stdout:
            sys.stdout.write(stdout)
            return
        if returncode != 0 and stderr:
            sys.stderr.write(stderr)
            return
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
    inputs = tool_input(data)
    config = read_config()
    if is_apply_patch_tool(short_name):
        paths = parse_apply_patch_files(command_from_inputs(inputs))
        maybe_mark_session_state(paths, data, config)
        messages = [scope_message(paths, config)]
        prospect = auto_prospect_message(paths, config)
        if prospect:
            messages.append(prospect)
        emit(hook_event("PostToolUse", " ".join(messages)))
        return

    if is_shell_tool(short_name):
        retrospect = auto_retrospect_message(data, inputs, config)
        if retrospect:
            emit(hook_event("PostToolUse", retrospect))
        return


def main() -> int:
    event = sys.argv[1] if len(sys.argv) > 1 else ""
    raw, data = load_input()

    if event == "session-start":
        return run_legacy("session-start-check.sh", raw)
    if event == "pre-compact":
        return run_legacy("pre-compact-check.sh", raw)
    if event == "post-compact":
        return run_legacy("post-compact-check.sh", raw)
    if event == "user-prompt-submit":
        user_prompt_submit(data)
        return 0
    if event == "subagent-start":
        return run_legacy("subagent-start-selfreport.sh", raw)
    if event == "subagent-stop":
        return run_legacy("subagent-stop-capture.sh", raw)
    if event == "pre-tool-use":
        pre_tool_use(data)
        return 0
    if event == "post-tool-use":
        post_tool_use(data)
        return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
