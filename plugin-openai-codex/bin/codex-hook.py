#!/usr/bin/env python3
"""Codex hook adapter for ARIA Knowledge."""

from __future__ import annotations

import errno
import hashlib
import json
import os
import re
import stat
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def write_stream(stream: Any, text: str) -> None:
    """Write text to stdout/stderr as UTF-8 bytes. A text write encodes with the locale, so under a C
    locale (ascii) any non-ASCII output from a legacy script raised UnicodeEncodeError and the hook
    exited 1. Codex reads hook output as UTF-8."""
    data = text.encode("utf-8", errors="replace")
    buffer = getattr(stream, "buffer", None)
    if buffer is None:
        stream.write(data.decode("utf-8"))
        return
    stream.flush()
    buffer.write(data)
    buffer.flush()


def emit(payload: dict[str, Any]) -> None:
    write_stream(sys.stdout, json.dumps(payload, separators=(",", ":")))


def run_legacy_capture(script_name: str, hook_input: str, cwd: Path | None = None) -> tuple[int, str, str]:
    plugin_root = Path(os.environ["ARIA_CODEX_PLUGIN_ROOT"])
    script = plugin_root / "bin" / script_name
    if not script.exists():
        return 0, "", ""
    try:
        proc = subprocess.run(
            ["sh", str(script)],
            input=hook_input,
            text=True,
            # A lone surrogate from a JSON \u escape, or a non-UTF-8 locale, made the encode raise
            # UnicodeEncodeError (a ValueError) and crashed the hook (as F4 found at the surfacing call).
            encoding="utf-8",
            errors="replace",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=os.environ.copy(),
            cwd=str(cwd) if cwd else None,
            check=False,
        )
    except (OSError, ValueError, subprocess.SubprocessError):
        return 0, "", ""  # the script could not run: no output, never a crash
    return proc.returncode, proc.stdout, proc.stderr


def run_legacy(script_name: str, hook_input: str) -> int:
    returncode, stdout, stderr = run_legacy_capture(script_name, hook_input)
    if stdout:
        write_stream(sys.stdout, stdout)
    elif stderr and returncode != 0:
        write_stream(sys.stderr, stderr)
    return returncode


def compact_json(data: dict[str, Any]) -> str:
    return json.dumps(data, separators=(",", ":"))


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
    for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
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
    # aria-knowledge v2.54.2: a "[Rule 22 · Scope]" line is the POST-edit check this
    # hook prompts for after every edit; it must not satisfy the next edit's gate.
    return bool(re.search(r"\[Rule 22(?:\s*[·.-](?!\s*(?i:scope)\b)\s*[^\]]+)?\]", text))


def hook_event(name: str, additional_context: str) -> dict[str, Any]:
    return {
        "hookSpecificOutput": {
            "hookEventName": name,
            "additionalContext": additional_context,
        }
    }


def parse_hook_stdout(stdout: str) -> dict[str, Any] | None:
    text = stdout.strip()
    if not text:
        return None
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        return None
    return parsed if isinstance(parsed, dict) else None


def hook_specific(parsed: dict[str, Any]) -> dict[str, Any]:
    value = parsed.get("hookSpecificOutput")
    return value if isinstance(value, dict) else {}


def is_deny_output(parsed: dict[str, Any]) -> bool:
    return hook_specific(parsed).get("permissionDecision") == "deny"


def output_additional_context(parsed: dict[str, Any]) -> str:
    value = hook_specific(parsed).get("additionalContext")
    return value if isinstance(value, str) else ""


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
    text = path.read_text(encoding="utf-8", errors="ignore")
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


# The session key: the rule lib-state-key.sh kt_session_key applies in every shell port, so the
# ledger session-start-check.sh STATES is the ledger this hook WRITES. The first of session_id,
# turn_id holding a non-empty string is used UNCHANGED when it is [A-Za-z0-9._-]+; any other value
# gives "" -- no key, so no state for that family (spec D3) -- and never falls back past it. Never
# stripped: stripping is not injective (`a+b` and `ab` would share one ledger). A non-string value
# counts as absent, as the shell extractor (strings only) reads it. The rule runs on the RAW stdin
# text, never the decoded JSON (spec D9). tests/repros/state-dir-model-facing.sh
# M8 pins shell == Python.
_SESSION_KEY_RE = re.compile(r"[A-Za-z0-9._-]+")


def session_key_check(value: Any) -> str:
    return value if isinstance(value, str) and _SESSION_KEY_RE.fullmatch(value) else ""


def session_key_field_raw(raw: str) -> str | None:
    """The first of session_id, turn_id holding a non-empty string, read from the RAW stdin text exactly
    as kt_session_key does: per field, the first textual match of the quoted field name, a colon (blanks
    allowed around it) and a quoted value running to the next quote, per LINE as grep reads it. None when
    neither field is present. The decoded JSON is never consulted -- an escaped value reads as the shell
    reads it (its backslash is not in the accept set)."""
    for field in ("session_id", "turn_id"):
        match = re.search(r'"' + field + r'"[ \t\v\f\r]*:[ \t\v\f\r]*"([^"\n]*)"', raw)
        if match and match.group(1) != "":
            return match.group(1)
    return None


def session_key_raw(raw: str) -> str:
    value = session_key_field_raw(raw)
    return session_key_check(value) if value is not None else ""


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


def active_context_matches(prompt: str, knowledge_folder: Path) -> tuple[list[str], list[str]]:
    """Ranked knowledge files for a prompt, from the port's shared CLI (bin/aria-surface.sh).

    The ranking lives in lib-index-match.sh alone (spec D1): this only runs the CLI and parses its
    output, in its order. KT_CONFIG is pinned to the file this hook read, so both halves read the
    same config (config.sh alone would never fall back to ~/.codex). A missing CLI, a non-zero exit,
    a timeout or any OS error yields no match: a broken install surfaces nothing, and never crashes
    or blocks the prompt.
    """
    if not (knowledge_folder / "index.md").exists():
        return [], []
    root = os.environ.get("ARIA_CODEX_PLUGIN_ROOT")
    if not root:
        return [], []
    cli = Path(root) / "bin" / "aria-surface.sh"
    if not cli.is_file():
        return [], []
    env = os.environ.copy()
    env["KT_CONFIG"] = str(config_path())
    try:
        proc = subprocess.run(
            ["sh", str(cli), "-"],
            input=prompt,
            text=True,
            # F4 (final fix wave): a lone surrogate from a JSON \u escape, or a non-UTF-8 locale,
            # made the encode raise UnicodeEncodeError (a ValueError) and crashed the hook.
            encoding="utf-8",
            errors="replace",
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            env=env,
            timeout=3,
            check=False,
        )
    except (OSError, subprocess.SubprocessError, ValueError):
        return [], []
    if proc.returncode != 0:
        return [], []
    lines = [line for line in proc.stdout.splitlines() if line.strip()]
    if len(lines) < 2 or not lines[0].startswith("tags: "):
        return [], []
    return lines[0][len("tags: "):].split(), lines[1:]


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


# --- The private per-user state directory (2.58.0) ---------------------------------------------
# Same contract as kt_state_* in lib-state-key.sh (tests/repros/state-dir-resolver.sh pins the two):
# <first set, non-empty of KT_STATE_BASE, XDG_RUNTIME_DIR, TMPDIR, (Darwin) DARWIN_USER_TEMP_DIR,
# /tmp; trailing "/" stripped>/aria-knowledge-<uid>, created 0700 and checked once. Any failure
# refuses and never tries the next base. Reasons are the shell's strings, verbatim.

_ARIA_STATE_ACL_XATTRS = ("system.posix_acl_access", "system.posix_acl_default", "system.nfs4_acl", "system.richacl")


def aria_state_base() -> str:
    for key in ("KT_STATE_BASE", "XDG_RUNTIME_DIR", "TMPDIR"):
        value = os.environ.get(key)
        if value:
            return value.rstrip("/")
    base = ""
    if sys.platform == "darwin":
        try:
            base = os.confstr(65537) or ""  # _CS_DARWIN_USER_TEMP_DIR; Python has no symbolic name
        except (ValueError, OSError):
            base = ""
    return (base or "/tmp").rstrip("/")


def _aria_state_acl_probe(path: str) -> tuple[str, str]:
    """(before, after): the ACL read split the way the shell resolver orders it. `before` is
    "permissions not verifiable" when the read itself failed -- the shell's one `ls` runs before its
    owner and mode checks, so that reason wins over both. `after` is applied only once owner and mode
    pass: "has an ACL", "permissions not verifiable" (a macOS "@" whose ACL could not be read), or ""."""
    listxattr = getattr(os, "listxattr", None)
    if listxattr is not None:
        try:
            names = listxattr(path, follow_symlinks=False)
        except OSError as exc:
            # No xattr support on this filesystem means no ACL can be stored there.
            if exc.errno in (getattr(errno, "ENOTSUP", -1), getattr(errno, "EOPNOTSUPP", -1)):
                return "", ""
            return "permissions not verifiable", ""
        return "", ("has an ACL" if any(name in _ARIA_STATE_ACL_XATTRS for name in names) else "")
    # No listxattr (macOS, BSD): the same single `ls` read the shell resolver makes. macOS hides "+"
    # behind "@" when an xattr is present; `-e` prints one extra line per ACL entry. Where -e is
    # unknown (a non-zero exit), fall back to -ldn and refuse an "@" whose ACL could not be read. An
    # empty read is refused, as the shell refuses it.
    def ls(flags: str) -> subprocess.CompletedProcess[str] | None:
        try:
            return subprocess.run(["ls", flags, path], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                  text=True, encoding="utf-8", errors="replace", check=False)
        except (OSError, ValueError, subprocess.SubprocessError):
            return None

    with_e = True
    out = ls("-lden")
    if out is None or out.returncode != 0:
        with_e = False
        out = ls("-ldn")
        if out is None or out.returncode != 0:
            return "permissions not verifiable", ""
    if not out.stdout:
        return "permissions not verifiable", ""
    lines = out.stdout.rstrip("\n").split("\n")
    mode = lines[0].split(" ", 1)[0]
    if mode.endswith("+") or len(lines) > 1:
        return "", "has an ACL"
    if mode.endswith("@") and not with_e:
        return "", "permissions not verifiable"
    return "", ""


def aria_state_resolve() -> tuple[Path | None, str]:
    uid = os.getuid()
    d = f"{aria_state_base()}/aria-knowledge-{uid}"
    try:
        os.lstat(d)
    except FileNotFoundError:
        try:
            os.mkdir(d, 0o700)
        except FileExistsError:
            pass
        except OSError:
            pass  # re-checked below
        else:
            try:
                os.chmod(d, 0o700)  # parity with `mkdir -m 700`, which ignores the umask
            except OSError:
                pass  # the mode check below refuses it
    except OSError:
        pass
    try:
        st = os.lstat(d)
    except OSError:
        return None, "not created"
    if stat.S_ISLNK(st.st_mode):
        return None, "is a link"
    if not stat.S_ISDIR(st.st_mode):
        return None, "not a directory"
    # The shell's order: its one `ls` read (which also carries the ACL) comes before owner and mode,
    # so an unreadable result outranks both; the ACL verdict itself comes after them.
    acl_before, acl_after = _aria_state_acl_probe(d)
    if acl_before:
        return None, acl_before
    if st.st_uid != uid:
        return None, "not owned by you"
    if stat.S_IMODE(st.st_mode) != 0o700:
        return None, "mode not 700"
    if acl_after:
        return None, acl_after
    return Path(d), ""


def aria_state_dir() -> Path | None:
    return aria_state_resolve()[0]


def aria_state_path(state_dir: Path | None, name: str) -> Path | None:
    if state_dir is None or name in ("", ".", "..") or "/" in name:
        return None
    try:
        os.fsencode(name)  # a lone surrogate from a JSON \u escape names no file this system can hold
    except ValueError:
        return None
    return state_dir / name


def state_read(path: Path | None) -> str | None:
    """The text of a state file, or None when there is no state at the name: no path (no state dir, or
    a name aria_state_path refused), nothing there, or anything but a regular file. The open never
    follows a link (O_NOFOLLOW) and never blocks on a FIFO (O_NONBLOCK); fstat decides."""
    if path is None:
        return None
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except (OSError, ValueError):  # ValueError: a name the filesystem cannot encode
        return None
    try:
        with os.fdopen(fd, "rb") as fp:
            if not stat.S_ISREG(os.fstat(fp.fileno()).st_mode):
                return None
            return fp.read().decode("utf-8", errors="replace")
    except (OSError, ValueError):
        return None


def state_write(path: Path | None, text: str, *, append: bool = False) -> bool:
    """Write (or append) a state file, created 0600. Writes nothing, and returns False, when there is
    no path or the name holds anything but a regular file (a FIFO with no reader fails the open; one
    with a reader is refused by fstat before any byte is written)."""
    if path is None:
        return False
    data = text.encode("utf-8", errors="replace")  # encode first: nothing is truncated if this fails
    flags = os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK | (os.O_APPEND if append else 0)
    try:
        fd = os.open(path, flags, 0o600)
    except (OSError, ValueError):  # ValueError: a name the filesystem cannot encode
        return False
    try:
        with os.fdopen(fd, "wb") as fp:
            if not stat.S_ISREG(os.fstat(fp.fileno()).st_mode):
                return False
            if not append:
                fp.truncate(0)
            fp.write(data)
        return True
    except (OSError, ValueError):
        return False


def ledger_is_ours(ledger: Path) -> bool:
    """F7 + (a) (final fix wave), kept as the second guard by spec D2: the ledger lives in the private
    state dir (<state dir>/aria-active-<key>), where no other user can create an entry, but a link, a
    non-regular file or a file another user owns at the name (our own mistake, or a path not routed
    through the resolver) is still never read or written through."""
    try:
        st = os.lstat(ledger)
    except FileNotFoundError:
        return True
    except (OSError, ValueError):  # ValueError: a name the filesystem cannot encode -- no state
        return False
    return stat.S_ISREG(st.st_mode) and st.st_uid == os.getuid()


def ledger_filter(items: list[str], ledger: Path | None) -> list[str]:
    if ledger is None or not ledger_is_ours(ledger):
        return items
    text = state_read(ledger)
    if not text or not text.strip():
        return items
    seen = set(text.splitlines())
    return [item for item in items if item.split(" — ", 1)[0] not in seen and item not in seen]


def ledger_record(items: list[str], ledger: Path | None) -> None:
    if not items or ledger is None or not ledger_is_ours(ledger):
        return
    state_write(ledger, "".join(item.split(" — ", 1)[0] + "\n" for item in items), append=True)


def user_prompt_submit(raw: str, data: dict[str, Any]) -> None:
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

    # The cooldown and the session ledger live in the private state dir. No usable state -- no state
    # dir (spec D3), or a name aria_state_path refuses (an id holding "/" or one the filesystem cannot
    # encode) -- means no cooldown and no dedupe, so every prompt would re-inject the same files:
    # surface nothing, as the shell ports do.
    state_dir = aria_state_dir()
    if state_dir is None:
        return
    key = session_key_raw(raw)
    if not key:   # no id, or one session_key rejects: no cooldown and no ledger (spec D3)
        return
    cooldown = aria_state_path(state_dir, f"aria-context-{key}")
    if cooldown is None:
        return
    stamp = state_read(cooldown)
    if stamp is not None:
        try:
            elapsed = int(datetime.now(timezone.utc).timestamp()) - int(stamp.strip())
            if elapsed < 30:
                return
        except ValueError:
            pass

    active = config_bool(config, "active_knowledge_surfacing", True)
    ledger = aria_state_path(state_dir, f"aria-active-{key}")
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
                f"ARIA ACTIVE — {len(files)} knowledge file(s) match this prompt (tags: {' '.join(tags)}). "
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

    state_write(cooldown, str(int(datetime.now(timezone.utc).timestamp())))
    if active:
        ledger_record(files, ledger)
        ledger_record(artifacts, ledger)

    emit(hook_event("UserPromptSubmit", " ".join(messages)))


def maybe_codemap_reminder(raw: str, data: dict[str, Any], cmd: str) -> dict[str, Any] | None:
    first_word = cmd.strip().split(maxsplit=1)[0] if cmd.strip() else ""
    if first_word not in {"rg", "grep", "find"}:
        return None

    codemap = find_codemap(cwd_from(data))
    if codemap is None:
        return None

    # The once-per-session cooldown lives in the private state dir. No state dir (spec D3), or a name
    # aria_state_path refuses: a reminder with no cooldown would repeat on every search, so emit nothing.
    state_dir = aria_state_dir()
    if state_dir is None:
        return None
    session = session_key_raw(raw)
    if not session:
        return None
    digest = hashlib.sha1(str(codemap.parent).encode()).hexdigest()[:12]
    ledger = aria_state_path(state_dir, f"aria-codex-codemap-{session}-{digest}")
    if ledger is None:
        return None
    if state_read(ledger) is not None:
        return None
    state_write(ledger, "seen\n")

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


def is_test_path(path: str) -> bool:
    return bool(re.search(r"(test|spec)", path, re.I))


def tautology_message(paths: list[str], data: dict[str, Any]) -> str:
    for path in paths:
        if not is_test_path(path):
            continue
        absolute = absolute_touched_path(path, data)
        if not absolute.exists() or not absolute.is_file():
            continue
        try:
            text = absolute.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue

        found = ""
        if re.search(
            r"assert\s+(True|true)([^A-Za-z0-9_]|$)|assertTrue\(\s*(True|true)\s*\)|expect\(\s*(true|True)\s*\)\.(toBe|toEqual)\(\s*(true|True)\s*\)",
            text,
        ):
            found = "a literal-true assertion"

        if not found:
            for match in re.finditer(
                r"assert\s+([A-Za-z_][A-Za-z0-9_.]*)\s*==\s*([A-Za-z_][A-Za-z0-9_.]*)",
                text,
            ):
                if match.group(1) == match.group(2):
                    found = f"an assertion whose two operands are both '{match.group(1)}'"
                    break

        if not found:
            for match in re.finditer(
                r"expect\(([A-Za-z_][A-Za-z0-9_.]*)\)\.(?:toBe|toEqual)\(([A-Za-z_][A-Za-z0-9_.]*)\)",
                text,
            ):
                if match.group(1) == match.group(2):
                    found = f"an assertion whose two operands are both '{match.group(1)}'"
                    break

        if not found:
            for match in re.finditer(
                r"\[\[?\s*(\$[A-Za-z_][A-Za-z0-9_]*)\s*(?:==?|=|-eq)\s*(\$[A-Za-z_][A-Za-z0-9_]*)\s*\]?\]",
                text,
            ):
                if match.group(1) == match.group(2):
                    found = f"a shell test comparing {match.group(1)} to itself"
                    break

        if found:
            return (
                f"ARIA: this test file contains {found} - it cannot fail, so it proves nothing while still reporting green "
                "(Rule 36). Rewrite it so it fails for the right reason, then watch it go RED before trusting it. "
                "NOTE: this check is syntactic only. It cannot detect semantic tautologies, so a clean result here is not evidence that the file is free of them."
            )
    return ""


def is_apply_patch_tool(short_name: str) -> bool:
    return short_name in {"apply_patch", "Edit", "Write"} or short_name.endswith("apply_patch")


def is_shell_tool(short_name: str) -> bool:
    return short_name in {"Bash", "exec_command"} or short_name.endswith("exec_command")


def is_external_fetch_tool(short_name: str) -> bool:
    return short_name in {"WebFetch", "WebSearch"} or short_name.endswith(("WebFetch", "WebSearch"))


def is_scheduler_create_tool(short_name: str) -> bool:
    return short_name in {"CronCreate", "create_scheduled_task"} or short_name.endswith(
        ("CronCreate", "create_scheduled_task")
    )


def is_planning_path(path: str) -> bool:
    return bool(
        re.search(r"/docs/(specs|plans)/.+", f"/{path}")
        or re.search(r"/docs/superpowers/(specs|plans)/.+", f"/{path}")
    )


def matches_config_path(path: str, raw_patterns: str) -> bool:
    if not raw_patterns.strip():
        return False
    normalized = f"/{path}"
    for pattern in raw_patterns.split(","):
        prefix = pattern.strip().rstrip("*").rstrip("/")
        if prefix and f"/{prefix}/" in normalized:
            return True
    return False


def is_planning_path_for_config(path: str, config: dict[str, str]) -> bool:
    return is_planning_path(path) or matches_config_path(path, config_value(config, "planning_paths"))


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
    if paths and all(is_planning_path_for_config(path, config) for path in paths) and not any(
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
    try:
        proc = subprocess.run(
            ["git", "-C", str(root), *args],
            text=True,
            encoding="utf-8",
            errors="replace",
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    except (OSError, ValueError, subprocess.SubprocessError):
        return ""  # no git, or a path it cannot encode: no value
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


def replace_file_bytes(path: Path, data: bytes) -> None:
    """Replace a file's content atomically: a temp file in the same directory, then os.replace, so a
    failure leaves the old file whole. A link at `path` is written through to its target (as a plain
    write did), and the target keeps its mode."""
    target = Path(os.path.realpath(path))
    try:
        mode = stat.S_IMODE(os.stat(target).st_mode)
    except FileNotFoundError:
        umask = os.umask(0)
        os.umask(umask)
        mode = 0o666 & ~umask
    fd, tmp = tempfile.mkstemp(dir=str(target.parent), prefix=f".{target.name}.", suffix=".tmp")
    try:
        with os.fdopen(fd, "wb") as fp:
            fp.write(data)
        os.chmod(tmp, mode)
        os.replace(tmp, target)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def mark_session_inprogress(root: Path, session_id: str, author: str) -> None:
    """Raises OSError or ValueError, with SESSION.md untouched, when the mark cannot be written."""
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    branch = git_value(root, "rev-parse", "--abbrev-ref", "HEAD")
    head = git_value(root, "rev-parse", "--short", "HEAD")
    session_file = root / "SESSION.md"
    body = ""
    fields: dict[str, str] = {}
    if session_file.exists():
        # UTF-8 with surrogateescape round-trips every byte: a locale read (or errors="ignore") would
        # drop what it cannot decode, and the rewrite below would then delete it from SESSION.md.
        existing = session_file.read_text(encoding="utf-8", errors="surrogateescape")
        parsed = split_frontmatter(existing)
        if parsed:
            fields, body = parsed
        else:
            body = "\n" + existing

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
    # Encode the whole file BEFORE touching it: a value surrogateescape cannot carry (a lone surrogate
    # outside U+DC80-DCFF, e.g. from a JSON \ud800 session id) raises here, and SESSION.md stays whole.
    replace_file_bytes(session_file, content.encode("utf-8", errors="surrogateescape"))

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


def maybe_mark_session_state(raw: str, paths: list[str], data: dict[str, Any], config: dict[str, str]) -> None:
    if config_value(config, "session_state", "false") != "true":
        return
    # session_key: the shared rule (lib-state-key.sh kt_session_key). A REJECTED id gives no key and no
    # cache, and the project is still marked (spec D3: "Mark anyway") with an empty session id, so the
    # raw id never reaches SESSION.md's front matter -- the shell post-edit hooks apply the same rule.
    # Only a payload with neither id falls back to the transcript hash, as before.
    session_id = session_key_raw(raw)
    author = config_value(config, "author_tag")
    if session_id:
        key = session_id
    elif session_key_field_raw(raw) is not None:   # an id is present but REJECTED: no key, mark anyway
        key = ""
    else:
        key = hashlib.sha1(str(data.get("transcript_path") or os.getpid()).encode()).hexdigest()[:12]
    # The per-session cache of roots already marked lives in the private state dir. No state dir, a
    # refused name, or no key (spec D3): mark every root anyway and keep no cache.
    ledger = aria_state_path(aria_state_dir(), f"aria-session-inprogress-codex-{key}") if key else None
    cached = state_read(ledger)
    seen = set(cached.splitlines()) if cached else set()
    for path in paths:
        if Path(path).name == "SESSION.md":
            continue
        root = find_session_root(absolute_touched_path(path, data))
        if root is None or str(root) in seen:
            continue
        try:
            mark_session_inprogress(root, session_id, author)
            seen.add(str(root))
        except (OSError, ValueError):  # not marked; SESSION.md is left as it was
            continue
    state_write(ledger, "\n".join(sorted(seen)) + ("\n" if seen else ""))


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
    try:
        count_proc = subprocess.run(
            ["git", "rev-list", "--count", range_value],
            cwd=str(cwd_from(data)),
            text=True,
            encoding="utf-8",
            errors="replace",
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    except (OSError, ValueError, subprocess.SubprocessError):
        return ""
    if count_proc.returncode != 0 or not count_proc.stdout.strip().isdigit():
        return ""
    count = int(count_proc.stdout.strip())
    if count < min_commits:
        return ""
    if mode == "run":
        return f"AUTO-RETROSPECT (run): pushed {count} commits ({range_value}) to {branch}. Run /retrospect range {range_value} inline now."
    return f"AUTO-RETROSPECT (nudge): pushed {count} commits ({range_value}) to {branch}. Offer to run /retrospect range {range_value} and ask the user (do not auto-run)."


def pre_tool_use(raw: str, data: dict[str, Any]) -> None:
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
        messages: list[str] = []
        # The STRING-matching pre-bash-write-check.sh was retired 2026-08-26 (silent on
        # backup-then-mutate, firing on a quoted `sed -i`). It was REPLACED, not removed:
        # canonical v2.48.1 decides from the RESOLVED mutation target via
        # pre-bash-write-resolve.py. Ported 2026-10-14 — it is run below with its own
        # payload, and it is the only writer of <state dir>/aria-r22-bypass-<session_id>,
        # the ledger /handoff and /wrapup read.
        for script in ("bash-cd-check.sh", "pre-commit-preflight-check.sh"):
            returncode, stdout, stderr = run_legacy_capture(script, compact_json(shell_payload), cwd_from(data))
            parsed = parse_hook_stdout(stdout)
            if parsed:
                if is_deny_output(parsed):
                    emit(parsed)
                    return
                context = output_additional_context(parsed)
                if context:
                    messages.append(context)
            elif stdout:
                write_stream(sys.stdout, stdout)
                return
            elif returncode != 0 and stderr:
                write_stream(sys.stderr, stderr)
                return

        # Record + warn on in-place writes to existing non-temp files. Warn-only by design.
        write_payload = {
            "session_id": session_key_raw(raw),
            "cwd": str(cwd_from(data)),
            "tool_input": {"command": cmd},
        }
        _rc, write_out, _err = run_legacy_capture(
            "pre-bash-write-check.sh", compact_json(write_payload), cwd_from(data)
        )
        write_parsed = parse_hook_stdout(write_out)
        write_context = output_additional_context(write_parsed) if write_parsed else ""
        if write_context:
            messages.append(write_context)

        reminder = maybe_codemap_reminder(raw, data, cmd)
        if reminder is not None:
            context = output_additional_context(reminder)
            if context:
                messages.append(context)
        if not write_context and writeish_exec_command(cmd) and not has_rule22_marker(last_text):
            messages.append(
                "ARIA: this shell command looks like it may write files. Prefer apply_patch for file edits, or output Rule 22 before any intentional write."
            )
        if messages:
            emit(hook_event("PreToolUse", " ".join(messages)))
        return

    if is_external_fetch_tool(short_name):
        returncode, stdout, stderr = run_legacy_capture("pre-external-fetch-check.sh", compact_json(data), cwd_from(data))
        parsed = parse_hook_stdout(stdout)
        if parsed:
            emit(parsed)
        elif stdout:
            write_stream(sys.stdout, stdout)
        elif returncode != 0 and stderr:
            write_stream(sys.stderr, stderr)
        return

    if is_scheduler_create_tool(short_name):
        returncode, stdout, stderr = run_legacy_capture("pre-cron-check.sh", compact_json(data), cwd_from(data))
        parsed = parse_hook_stdout(stdout)
        if parsed:
            emit(parsed)
        elif stdout:
            write_stream(sys.stdout, stdout)
        elif returncode != 0 and stderr:
            write_stream(sys.stderr, stderr)
        return


def post_tool_use(raw: str, data: dict[str, Any]) -> None:
    name = tool_name(data)
    short_name = name.split(".")[-1]
    inputs = tool_input(data)
    config = read_config()
    if is_apply_patch_tool(short_name):
        paths = parse_apply_patch_files(command_from_inputs(inputs))
        maybe_mark_session_state(raw, paths, data, config)
        messages = [scope_message(paths, config)]
        tautology = tautology_message(paths, data)
        if tautology:
            messages.append(tautology)
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
        user_prompt_submit(raw, data)
        return 0
    if event == "subagent-start":
        return run_legacy("subagent-start-selfreport.sh", raw)
    if event == "subagent-stop":
        return run_legacy("subagent-stop-capture.sh", raw)
    if event == "pre-tool-use":
        pre_tool_use(raw, data)
        return 0
    if event == "post-tool-use":
        post_tool_use(raw, data)
        return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
