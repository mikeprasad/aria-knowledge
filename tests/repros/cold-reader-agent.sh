#!/bin/sh
# cold-reader-agent.sh — the plugin ships a read-only reader agent for /prospect --cold (spec D6, AC8).
#
# /prospect --cold dispatches `aria-knowledge:cold-reader` so the cold read runs in the same
# environment the implementer will have (startup CLAUDE.md and rules load for a plugin agent).
# The agent must stay a neutral reader: it gets no write tools, no model pin, and its body carries
# only the read-only instruction. Anything about the plan under review belongs in the dispatch
# prompt, never in the agent file, or every cold read would be primed by it.
#
#   G1  the file exists
#   G2  the frontmatter keys are exactly name, description, tools (any order, nothing else)
#   G3  name is cold-reader; tools is exactly "Read, Grep, Glob, Bash"
#   G4  description is under 200 chars and holds no < > [ ] (the claude.ai skill precautions)
#   G5  the body, trimmed, equals exactly the one read-only sentence
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
AGENT="$REPO_ROOT/plugin-claude-code/agents/cold-reader.md"
PASS=0; FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

# One parser prints one line per arm: "<arm> ok" or "<arm> fail <reason>".
OUT=$(python3 -I - "$AGENT" <<'PY'
import os, re, sys
path = sys.argv[1]
WANT_BODY = "Follow the prompt you are given. Do not create, edit or delete any file."
if not os.path.isfile(path):
    for arm in ("G1", "G2", "G3", "G4", "G5"):
        print(f"{arm} fail file absent: {path}")
    sys.exit(0)
print("G1 ok")
t = open(path, encoding="utf-8").read()
m = re.match(r"^---\n(.*?)\n---\n?(.*)\Z", t, re.S)
if not m:
    for arm in ("G2", "G3", "G4", "G5"):
        print(f"{arm} fail no closed --- frontmatter block")
    sys.exit(0)
front, body = m.group(1), m.group(2)
fields = {}
for line in front.split("\n"):
    km = re.match(r"^([A-Za-z_][\w-]*):\s*(.*)$", line)
    if km:
        v = km.group(2).strip()
        if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
            v = v[1:-1]
        fields[km.group(1)] = v
keys = sorted(fields)
print("G2 ok" if keys == ["description", "name", "tools"] else f"G2 fail frontmatter keys are {keys}")
g3 = []
if fields.get("name") != "cold-reader": g3.append(f"name is {fields.get('name')!r}")
if fields.get("tools") != "Read, Grep, Glob, Bash": g3.append(f"tools is {fields.get('tools')!r}")
print("G3 ok" if not g3 else "G3 fail " + "; ".join(g3))
d = fields.get("description", "")
g4 = []
if not d: g4.append("description missing")
if len(d) >= 200: g4.append(f"description {len(d)} chars, not under 200")
bad_chars = sorted(set(c for c in d if c in "<>[]"))
if bad_chars: g4.append("description contains " + " ".join(bad_chars))
print("G4 ok" if not g4 else "G4 fail " + "; ".join(g4))
b = body.strip()
print("G5 ok" if b == WANT_BODY else f"G5 fail body is {b!r}")
PY
)
EX=$?
[ "$EX" -eq 0 ] || bad "parser" "python exited $EX: $OUT"

for arm in G1 G2 G3 G4 G5; do
  line=$(printf '%s\n' "$OUT" | grep "^$arm " || true)
  case "$line" in
    "$arm ok") ok "$arm" ;;
    "$arm fail "*) bad "$arm" "${line#"$arm fail "}" ;;
    *) bad "$arm" "no result line from the parser" ;;
  esac
done

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
