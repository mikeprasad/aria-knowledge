#!/usr/bin/env python3
"""Reference message-extraction filter for /audit style.
Turns a Claude Code .jsonl transcript into genuine user-authored prose lines.
The SKILL.md body documents this same multi-stage algorithm in prose; this file
is the machine-checkable canonical spec. Stdlib only, read-only, no network."""
import sys, json, re

# Redaction mirrors ditto's REDACTIONS (best-effort). Applied before any emit.
REDACTIONS = [
    (re.compile(r"sk-[A-Za-z0-9]{8,}"), "[REDACTED-KEY]"),
    (re.compile(r"sk_live_[A-Za-z0-9]{8,}"), "[REDACTED-KEY]"),
    (re.compile(r"eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+"), "[REDACTED-JWT]"),
    (re.compile(r"gh[pousr]_[A-Za-z0-9]{20,}"), "[REDACTED-GH]"),
    (re.compile(r"xox[baprs]-[A-Za-z0-9\-]{10,}"), "[REDACTED-SLACK]"),
    (re.compile(r"AKIA[0-9A-Z]{16}"), "[REDACTED-AWS]"),
    (re.compile(r"(?i)(password|secret|api[_-]?key)\s*[=:]\s*\S+"), r"\1=[REDACTED]"),
    (re.compile(r"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"), "[REDACTED-EMAIL]"),
    (re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b"), "[REDACTED-IP]"),
]
# Stage-2 wrapper markers (system/command noise wearing a role:user coat).
NOISE_MARKERS = ("<local-command", "<command-name>", "<command-args>",
                 "<local-command-stdout>", "<local-command-caveat>")
# Stage-3 system-injection preambles (not the user's voice).
INJECT_PREFIXES = ("Base directory for this skill:", "Caveat:",
                   "<system-reminder>")

def redact(text):
    for pat, repl in REDACTIONS:
        text = pat.sub(repl, text)
    return text

def user_text_blocks(obj):
    """Stage 1: role=user AND content is text (never tool_result)."""
    if obj.get("type") != "user":
        return ""
    msg = obj.get("message", {})
    if msg.get("role") != "user":
        return ""
    content = msg.get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return " ".join(
            b.get("text", "") for b in content
            if isinstance(b, dict) and b.get("type") == "text"
        )
    return ""

def is_noise(text):
    t = text.strip()
    if not t:
        return True
    if any(m in t for m in NOISE_MARKERS):          # stage 2
        return True
    if any(t.startswith(p) for p in INJECT_PREFIXES):  # stage 3
        return True
    # stage 3b: /handoff resume scaffold, possibly preceded by a short label line
    # (e.g. "cs\n  Resume Commonspace from ..."), so check the first 2 lines, not
    # only an absolute string start.
    if any(ln.strip().startswith("Resume ") for ln in t.splitlines()[:2]):
        return True
    if t.startswith("/"):                            # stage 4: bare slash-command
        return True
    return False

def main(path):
    session = date = None
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        session = obj.get("sessionId", session)
        ts = obj.get("timestamp", "")
        date = ts[:10] if ts else date
        text = user_text_blocks(obj)
        if not text or is_noise(text):
            continue
        print(json.dumps({"session": session, "date": date, "text": redact(text.strip())}))

if __name__ == "__main__":
    main(sys.argv[1])
