#!/usr/bin/env python3
"""Resolve the files a Bash command mutates IN PLACE. Prints one path per line; prints nothing
when there are none. Exits 0 always.

WHY THIS EXISTS
  v2.48.0 REMOVED `pre-bash-write-check.sh` and affirmed its intent in the same breath:

      "It warned when a shell command mutated a file in place, bypassing the Rule 22 gate.
       The intent was sound; the method decided from the COMMAND STRING instead of resolving
       the mutation TARGET."

  The retired guard was wrong in BOTH directions, and both are the same root cause:

    FALSE NEGATIVE  it exempted any command whose text merely MENTIONED a temp path, so
                    `cp f /tmp/bak && sed -i ... f` was silent — backup-then-mutate, the careful
                    pattern this project mandates. Doing the safe thing disarmed the check.
    FALSE POSITIVE  its idiom match was unanchored, so a `git commit` whose MESSAGE quoted
                    `sed -i` was flagged as an in-place mutation.

  Resolving the target closes both at once. That is the whole change.

⛔ SCOPE IS DELIBERATELY UNCHANGED from the retired guard, and it was MEASURED, not assumed:
  across 25,508 real Bash calls, `cat > newfile` is overwhelmingly a throwaway probe or diagnostic
  harness, while `sed -i` on a tracked file is the actual lapse. The narrowed rule fired on 0.674%
  of calls. Do NOT widen this to `>` creation, `cp`, `mv` or `tee` — the resolver this is ported
  from detects all of those because it answers a DIFFERENT question. Widening turns a guard that
  fires 1-in-148 into noise, and an ignored guard catches nothing.

⛔ `Path.write_text()` was in the retired guard's scope and is NOT here. Its target lives inside
  Python source text, which a shell lexer cannot reach, so keeping it would mean matching the raw
  command string — precisely the method this file exists to replace. Dropped deliberately; it
  returns only when a resolver can parse Python source. This loses a measured real lapse.
"""

import json
import os
import re
import shlex
import sys

#: A heredoc BODY is data, not shell. A `sed -i` inside one is prose — this is exactly the
#: false positive that retired the previous guard (a commit message quoting an idiom).
HEREDOC_BODY = re.compile(r"<<-?\s*([\'\"]?)(\w+)\1[\s\S]*?^\2\s*$", re.M)

#: Shell operators that END a statement. A verb's arguments never cross one of these.
#: Without this, `rest = toks[i+1:]` reads to end-of-command and sweeps in unrelated paths.
STATEMENT_SEPS = frozenset({"&&", "||", ";", ";;", "|", "|&", "&", "(", ")", "\n"})

#: Appending to a SOURCE file is a structural edit. Appending to a backlog or a log is normal and
#: was measured always benign (1.27% of calls), which is why .md and .json are deliberately absent.
SOURCE_EXT = (".py", ".ts", ".tsx", ".js", ".jsx", ".sh", ".swift", ".kt", ".java", ".rb", ".go", ".rs")

#: Transient by construction. ⛔ Matched against the RESOLVED TARGET, never the command string —
#: that inversion is the entire false-negative fix.
TEMP_PREFIXES = ("/tmp/", "/private/tmp/", "/var/tmp/", "/var/folders/")


def _statements(body):
    """Per-statement token lists. Raises ValueError when unparseable (=> caller fails open).

    `punctuation_chars=True` is the stdlib's operator-aware mode. Chosen over a hand-rolled
    splitter because the hard part is QUOTING and shlex already gets it right: `echo "a;b"`
    yields ONE token and does not split, while `a && b` and `a; b` do.
    """
    lx = shlex.shlex(body, posix=True, punctuation_chars=True)
    lx.whitespace_split = True
    lx.commenters = ""
    stmts, cur = [], []
    for t in list(lx):
        if t in STATEMENT_SEPS:
            if cur:
                stmts.append(cur)
                cur = []
        else:
            cur.append(t)
    if cur:
        stmts.append(cur)
    return stmts


def _in_place_targets(toks):
    """Files a single statement mutates in place."""
    out, n = [], len(toks)
    for i, t in enumerate(toks):
        base = os.path.basename(t)
        rest = toks[i + 1:]
        if base in ("sed", "perl"):
            # A real -i flag, not a mention. `sed -n` reads and must record nothing.
            if any(u == "-i" or u.startswith("-i") for u in rest):
                out.extend(u for u in rest if u and not u.startswith("-"))
        elif base == "awk":
            if "inplace" in rest:
                out.extend(u for u in rest if u and not u.startswith("-") and u != "inplace")
        elif t == ">>":
            tgt = toks[i + 1] if i + 1 < n else ""
            # Extension-sensitive: a source file is a structural edit, a backlog is not.
            if tgt and tgt.lower().endswith(SOURCE_EXT):
                out.append(tgt)
    return out


def _reportable(path):
    """⛔ EXISTENCE IS THE FILTER, and it is a definition rather than a heuristic.

    In-place mutation presupposes the file exists. Requiring existence therefore (a) matches what
    'mutates in place' means, (b) drops a sed SCRIPT like `s/a/b/` which is a token but not a
    file — naming it in a human-readable warning would be a wrong message, and unlike the
    root-repo tool this hook cannot absorb over-detection for free, and (c) makes `>>` onto a
    not-yet-existing file fall out as CREATION, which is out of scope, with no extra rule.
    """
    if not path or path.startswith("-"):
        return False
    try:
        if not os.path.exists(path):
            return False
        real = os.path.realpath(os.path.abspath(path))
    except Exception:
        return False                                  # unstattable => fail open
    if "/scratchpad/" in real or real.startswith(TEMP_PREFIXES):
        return False
    return True


def main():
    try:
        payload = json.load(sys.stdin)
        cmd = (payload.get("tool_input") or {}).get("command") or ""
    except Exception:
        return 0                                      # malformed => fail open
    if not cmd:
        return 0
    try:
        stmts = _statements(HEREDOC_BODY.sub(" ", cmd))
    except ValueError:
        return 0                                      # unbalanced quotes => fail open
    seen = []
    for toks in stmts:
        for t in _in_place_targets(toks):
            if t not in seen and _reportable(t):
                seen.append(t)
    for t in seen:
        print(t)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)                                   # observability must never cost a Bash call
