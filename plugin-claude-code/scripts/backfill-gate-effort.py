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
              SKIPPED <path> changed-since-scan | ERROR <path> <reason>
              SUMMARY fill=N correct=N ambiguous=N unmatched=N errors=N
Dry-run unless --apply. CORRECT lines are always printed (they preview what
--correct-self-reported does) but are counted and applied only with that flag.
A log with no `effort:` line in its first frontmatter block is left alone.
Both `effort: unrecorded` and an EMPTY `effort:` value are filled (deliberate
extension). Transcript effort values must match [A-Za-z0-9_-]+, else the record
is ignored. At write time each log is re-read and re-verified (SKIPPED if it
changed since the scan) and written via temp file + os.replace. Per-file I/O
errors are reported as ERROR and never abort the run. Always exits 0.
"""
import argparse
import datetime
import glob
import json
import os
import re
import shutil
import tempfile

GATES = ("prospect", "retrospect", "preflight")
DONE = ("# from transcript", "# corrected from transcript")
FILL_VALUES = ("", "unrecorded")
VALID_EFFORT = re.compile(r"[A-Za-z0-9_-]+")


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
                if (not isinstance(effort, str) or not VALID_EFFORT.fullmatch(effort)
                        or not isinstance(content, list)):
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


def classify(data):
    """(start, end, eol, old, kind) for the effort line of `data`, or None if not actionable."""
    hit = find_effort_line(data)
    if not hit:
        return None
    start, end, eol, vtext = hit
    if any(m in vtext for m in DONE):
        return None
    old = vtext.split("#", 1)[0].strip()
    return start, end, eol, old, ("fill" if old in FILL_VALUES else "self")


def build_plan(knowledge, transcripts):
    """Scan phase: read-only. Returns a list of actions (one per distinct real file)."""
    cands, seen = [], set()
    for gate in GATES:
        for p in sorted(glob.glob(os.path.join(knowledge, "logs", gate, "*.md"))):
            rp = os.path.realpath(p)
            if rp in seen:
                continue
            try:
                with open(rp, "rb") as fh:
                    c = classify(fh.read())
            except OSError:
                continue
            if c:
                seen.add(rp)
                cands.append((p, rp, c[3], c[4]))
    found = collect(transcripts, {c[1] for c in cands}) if cands else {}
    plan = []
    for p, rp, old, kind in cands:
        vals = found.get(rp, set())
        if kind == "fill":
            if len(vals) > 1:
                plan.append({"op": "AMBIGUOUS", "path": p, "vals": sorted(vals)})
            elif not vals:
                plan.append({"op": "UNMATCHED", "path": p})
            else:
                plan.append({"op": "FILL", "path": p, "rp": rp, "old": old, "new": next(iter(vals))})
        elif len(vals) == 1 and next(iter(vals)) != old:
            plan.append({"op": "CORRECT", "path": p, "rp": rp, "old": old, "new": next(iter(vals))})
    return plan


def write_atomic(rp, data):
    d = os.path.dirname(rp)
    fd, tmp = tempfile.mkstemp(prefix=".bge-", dir=d)
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
        shutil.copymode(rp, tmp)
        os.replace(tmp, rp)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def execute(plan, apply=False, correct=False, today=None):
    today = today or datetime.date.today().strftime("%Y-%m-%d")
    n = {"fill": 0, "correct": 0, "ambiguous": 0, "unmatched": 0, "errors": 0}
    for e in plan:
        op, p = e["op"], e["path"]
        if op == "AMBIGUOUS":
            print("AMBIGUOUS %s %s" % (p, ",".join(e["vals"])))
            n["ambiguous"] += 1
            continue
        if op == "UNMATCHED":
            print("UNMATCHED %s" % p)
            n["unmatched"] += 1
            continue
        if op == "FILL":
            line = "effort: %s  # from transcript %s" % (e["new"], today)
            print("FILL %s %s" % (p, e["new"]))
        else:
            line = "effort: %s  # corrected from transcript %s; was %s" % (e["new"], today, e["old"])
            print("CORRECT %s %s -> %s" % (p, e["old"], e["new"]))
            if not correct:
                continue
        if apply:
            try:
                with open(e["rp"], "rb") as fh:
                    data = fh.read()
                c = classify(data)
                want = "fill" if op == "FILL" else "self"
                if not c or c[3] != e["old"] or c[4] != want:
                    print("SKIPPED %s changed-since-scan" % p)
                    continue
                start, end, eol = c[0], c[1], c[2]
                write_atomic(e["rp"], data[:start] + line.encode("utf-8") + eol + data[end:])
            except OSError as ex:
                print("ERROR %s %s" % (p, ex.strerror or ex))
                n["errors"] += 1
                continue
        n["fill" if op == "FILL" else "correct"] += 1
    print("SUMMARY fill=%d correct=%d ambiguous=%d unmatched=%d errors=%d" % (
        n["fill"], n["correct"], n["ambiguous"], n["unmatched"], n["errors"]))


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--knowledge", required=True)
    ap.add_argument("--transcripts", default=os.path.expanduser("~/.claude/projects"))
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--correct-self-reported", action="store_true")
    a = ap.parse_args()
    execute(build_plan(a.knowledge, a.transcripts), apply=a.apply, correct=a.correct_self_reported)


if __name__ == "__main__":
    main()
