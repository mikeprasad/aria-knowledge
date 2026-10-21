#!/usr/bin/env python3
"""Repair the `effort:` frontmatter line of gate logs from the transcript that wrote them.

Usage: backfill-gate-effort.py --knowledge DIR [--transcripts ROOT] [--apply]
                               [--correct-self-reported]

Claude Code records the session effort as a top-level `effort` field on each
assistant transcript record. The record that holds the `Write` tool call which
created a gate log (logs/{prospect,retrospect,preflight}/*.md) is therefore the
ground truth for that log's effort.

Output lines: FILL <path> <value> | CORRECT <path> <old> -> <new>
              AMBIGUOUS <path> <v1,v2> | UNMATCHED <path>
              SUMMARY fill=N correct=N ambiguous=N unmatched=N
Dry-run unless --apply. CORRECT lines are always printed (they preview what
--correct-self-reported does) but are counted and applied only with that flag.
A log with no `effort:` line in its first frontmatter block is left alone.
Always exits 0.
"""
import argparse
import datetime
import glob
import json
import os
import re

GATES = ("prospect", "retrospect", "preflight")
DONE = ("# from transcript", "# corrected from transcript")
FILL_VALUES = ("", "unrecorded")


def find_effort_line(data):
    """Return (start, end, eol, value_text) of the first frontmatter effort line, or None."""
    lines = data.splitlines(keepends=True)
    if not lines or lines[0].rstrip(b"\r\n") != b"---":
        return None
    pos = len(lines[0])
    for raw in lines[1:]:
        text = raw.rstrip(b"\r\n")
        if text == b"---":
            return None
        m = re.match(rb"effort:[ \t]*(.*)$", text)
        if m:
            return pos, pos + len(raw), raw[len(text):], m.group(1).decode("utf-8", "replace")
        pos += len(raw)
    return None


def transcript_files(root):
    seen = set()
    for pat in ("*/*.jsonl", "*/*/subagents/*.jsonl"):
        for p in glob.glob(os.path.join(root, pat)):
            if p not in seen:
                seen.add(p)
                yield p


def collect(root, wanted):
    """realpath(log) -> set of effort values, for Write calls naming a wanted log."""
    found = {}
    for tp in transcript_files(root):
        try:
            fh = open(tp, "r", encoding="utf-8", errors="replace")
        except OSError:
            continue
        with fh:
            for line in fh:
                if '"Write"' not in line:
                    continue
                try:
                    rec = json.loads(line)
                except ValueError:
                    continue
                if not isinstance(rec, dict):
                    continue
                effort = rec.get("effort")
                msg = rec.get("message")
                content = msg.get("content") if isinstance(msg, dict) else None
                if not isinstance(effort, str) or not effort or not isinstance(content, list):
                    continue
                for blk in content:
                    if not (isinstance(blk, dict) and blk.get("type") == "tool_use"
                            and blk.get("name") == "Write"):
                        continue
                    inp = blk.get("input")
                    fp = inp.get("file_path") if isinstance(inp, dict) else None
                    if not isinstance(fp, str):
                        continue
                    rp = os.path.realpath(fp)
                    if rp in wanted:
                        found.setdefault(rp, set()).add(effort)
    return found


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--knowledge", required=True)
    ap.add_argument("--transcripts", default=os.path.expanduser("~/.claude/projects"))
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--correct-self-reported", action="store_true")
    a = ap.parse_args()

    today = datetime.date.today().strftime("%Y-%m-%d")
    cands = []  # (path, realpath, kind, old, span, eol)
    for gate in GATES:
        for p in sorted(glob.glob(os.path.join(a.knowledge, "logs", gate, "*.md"))):
            try:
                with open(p, "rb") as fh:
                    data = fh.read()
            except OSError:
                continue
            hit = find_effort_line(data)
            if not hit:
                continue
            start, end, eol, vtext = hit
            if any(m in vtext for m in DONE):
                continue
            old = vtext.split("#", 1)[0].strip()
            kind = "fill" if old in FILL_VALUES else "self"
            cands.append((p, os.path.realpath(p), kind, old, (start, end), eol))

    found = collect(a.transcripts, {c[1] for c in cands}) if cands else {}
    counts = {"fill": 0, "correct": 0, "ambiguous": 0, "unmatched": 0}

    for p, rp, kind, old, (start, end), eol in cands:
        vals = found.get(rp, set())
        if kind == "fill":
            if len(vals) > 1:
                print("AMBIGUOUS %s %s" % (p, ",".join(sorted(vals))))
                counts["ambiguous"] += 1
                continue
            if not vals:
                print("UNMATCHED %s" % p)
                counts["unmatched"] += 1
                continue
            new = next(iter(vals))
            line = "effort: %s  # from transcript %s" % (new, today)
            print("FILL %s %s" % (p, new))
            counts["fill"] += 1
        else:
            if len(vals) != 1:
                continue  # self-reported: nothing safe to correct to
            new = next(iter(vals))
            if new == old:
                continue
            line = "effort: %s  # corrected from transcript %s; was %s" % (new, today, old)
            print("CORRECT %s %s -> %s" % (p, old, new))
            if not a.correct_self_reported:
                continue
            counts["correct"] += 1
        if a.apply:
            with open(p, "rb") as fh:
                data = fh.read()
            data = data[:start] + line.encode("utf-8") + eol + data[end:]
            with open(p, "wb") as fh:
                fh.write(data)

    print("SUMMARY fill=%d correct=%d ambiguous=%d unmatched=%d" % (
        counts["fill"], counts["correct"], counts["ambiguous"], counts["unmatched"]))


if __name__ == "__main__":
    main()
