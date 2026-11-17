#!/bin/sh
# shipped-patterns-2590.sh — the shipped pattern library carries the two forward patterns added in 2.59.0
# (spec "Patterns — two shipped"; plan Task 5), in every port's copy of retrospect-patterns.md.
#
# Copies: plugin-claude-code, plugin-openai-codex, plugin-claude-cowork and plugin-antigravity (generated
# by build.sh) template/rules/retrospect-patterns.md, plus plugin-cursor-template/knowledge/rules/.
# An entry is its "## <name>" line up to the next line starting "## ".
#
#   S1  contract-restated-anywhere-is-a-divergence-already-scheduled appears exactly once in every copy and
#       carries the seven fields of the library's entry format, in order, each non-empty: Tier · First
#       identified · One-line summary · Detection cues · Why it's a problem · Counter-discipline · References
#   S2  re-run-pre-execution-checks-empirically-at-execution-start, the same checks
#   S3  guard: the five copies are byte-identical (a hand-copy that drifted, or an Antigravity build that
#       was not re-run, fails here)
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PASS=0; FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

ARMS="S1 S2 S3"
OUT=$(python3 -I - "$REPO_ROOT" <<'PY'
import os, re, sys
root = sys.argv[1]
COPIES = [
    "plugin-claude-code/template/rules/retrospect-patterns.md",
    "plugin-openai-codex/template/rules/retrospect-patterns.md",
    "plugin-claude-cowork/template/rules/retrospect-patterns.md",
    "plugin-antigravity/template/rules/retrospect-patterns.md",
    "plugin-cursor-template/knowledge/rules/retrospect-patterns.md",
]
ENTRIES = {
    "S1": "contract-restated-anywhere-is-a-divergence-already-scheduled",
    "S2": "re-run-pre-execution-checks-empirically-at-execution-start",
}
# (label, kind): "inline" = "**Label:** value" on one line; "section" = "### Label" with a non-empty body
FIELDS = [
    ("Tier", "inline"),
    ("First identified", "inline"),
    ("One-line summary", "inline"),
    ("Detection cues", "section"),
    ("Why it's a problem", "section"),
    ("Counter-discipline", "section"),
    ("References", "section"),
]
fails = {"S1": [], "S2": [], "S3": []}
texts = {}

for rel in COPIES:
    p = os.path.join(root, rel)
    if not os.path.isfile(p):
        for a in fails:
            fails[a].append(f"{rel}: file missing")
        continue
    t = open(p, encoding="utf-8").read()
    texts[rel] = t
    lines = t.split("\n")
    for arm, name in ENTRIES.items():
        starts = [i for i, l in enumerate(lines) if l == f"## {name}"]
        if len(starts) != 1:
            fails[arm].append(f"{rel}: '## {name}' appears {len(starts)} times")
            continue
        s = starts[0]
        e = next((j for j in range(s + 1, len(lines)) if lines[j].startswith("## ")), len(lines))
        body = lines[s + 1:e]
        pos = -1
        for label, kind in FIELDS:
            if kind == "inline":
                hit = [i for i, l in enumerate(body) if l.startswith(f"**{label}:**")]
                if len(hit) != 1:
                    fails[arm].append(f"{rel}: '**{label}:**' appears {len(hit)} times")
                    continue
                i = hit[0]
                if not body[i][len(f"**{label}:**"):].strip():
                    fails[arm].append(f"{rel}: '**{label}:**' is empty")
            else:
                hit = [i for i, l in enumerate(body) if l == f"### {label}"]
                if len(hit) != 1:
                    fails[arm].append(f"{rel}: '### {label}' appears {len(hit)} times")
                    continue
                i = hit[0]
                k = next((j for j in range(i + 1, len(body)) if body[j].startswith("### ")), len(body))
                content = [l for l in body[i + 1:k] if l.strip() and l.strip() != "---"]
                if not content:
                    fails[arm].append(f"{rel}: '### {label}' has no body")
            if i < pos:
                fails[arm].append(f"{rel}: '{label}' is out of order")
            pos = i

if len(texts) == len(COPIES):
    base = texts[COPIES[0]]
    diff = [r for r in COPIES[1:] if texts[r] != base]
    if diff:
        fails["S3"].append("differs from " + COPIES[0] + ": " + ", ".join(diff))

for a, f in fails.items():
    print(f"{a} ok" if not f else f"{a} fail " + " | ".join(f))
PY
)
EX=$?
[ "$EX" -eq 0 ] || bad "parser" "python exited $EX: $OUT"

for arm in $ARMS; do
  line=$(printf '%s\n' "$OUT" | grep "^$arm " || true)
  case "$line" in
    "$arm ok") ok "$arm" ;;
    "$arm fail "*) bad "$arm" "${line#"$arm fail "}" ;;
    *) bad "$arm" "no result line from the parser" ;;
  esac
done

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
