#!/bin/sh
# prospect-adoptions.sh — /prospect gains --cold (Step 3.6), --summary, command receipts and a fourth
# frame question in every port that carries the skill (2.59.0 spec R1, R2, R5, R6, R9, --summary; AC2,
# AC3, AC7).
#
# Ports: plugin-claude-code, plugin-openai-codex, plugin-antigravity and plugin-claude-cowork
# skills/prospect/SKILL.md, plus the /prospect section of the Cursor aria-commands.mdc. That .mdc also
# carries /retrospect, which has its own "Three questions" and Step 3.5, so every Cursor arm first cuts
# the /prospect section (its "## /prospect" line up to the next line starting "## /") and asserts only
# inside it. Every Step 3.6 arm first cuts Step 3.6 (its "## Step 3.6" line up to the next "## Step")
# and asserts case-insensitively inside it.
#
#   P1  --cold and --summary in Step 0's modifier list (every port) and in argument-hint (claude-code,
#       codex, cowork; build.sh strips argument-hint from Antigravity; Cursor has no per-skill frontmatter)
#   P2  a "## Step 3.6" heading naming the cold read, between Step 3.5 and Step 4
#   P3  the template between the cold-read-template markers is byte-identical in every port and holds
#       five numbered items (guard half proven by a one-character mutation)
#   P4  Step 3.6 names aria-knowledge:cold-reader, its general-purpose fallback, the docs/host stamp,
#       "fresh reader", the read-in-place rule, the five known gaps, and the Cold read block fields
#   P5  section 4.6 says "Four questions" and its fourth is the in-flight-work question
#   P6  Step 6 carries the --summary rule
#   P7  claude-code frontmatter allowed-tools contains Agent
#   P8  Step 3.6 holds the not-run line for a runtime that cannot start a subagent
#   P9  guard: Step 3.6 never says "instruction-free", "context-free" or "Plan agent"
#   P10 guard: each port's prospect description is byte-unchanged from the pre-change tree (11041cd);
#       the pinned values are SHA-256 of the whole "description:" line
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PASS=0; FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

ARMS="P1 P2 P3 P4 P5 P6 P7 P8 P9 P10"
OUT=$(python3 -I - "$REPO_ROOT" <<'PY'
import hashlib, os, re, sys
root = sys.argv[1]
SKILL_PORTS = ["plugin-claude-code", "plugin-openai-codex", "plugin-antigravity", "plugin-claude-cowork"]
CURSOR = "plugin-cursor-template/.cursor/rules/aria-commands.mdc"
HINT_PORTS = {"plugin-claude-code", "plugin-openai-codex", "plugin-claude-cowork"}
PINNED_DESC = {
    "plugin-claude-code": "f971f4995883f57747bbdfb2898fa3f8ed70dc121ecf8dd31c7e052b61803a76",
    "plugin-openai-codex": "9c45f8b2091de7958d7a75b2113c61e0bcc2bed08236c65cb8c22435d1401b74",
    "plugin-claude-cowork": "6fc7ebc7177bf796f922cf67c6f0ebf0d747dbd03c741dcfc8d8fc23fe77f323",
    "plugin-antigravity": "f971f4995883f57747bbdfb2898fa3f8ed70dc121ecf8dd31c7e052b61803a76",
}
NOT_RUN = "cold read: not run — this runtime cannot start a subagent"
fails = {a: [] for a in ["P1", "P2", "P3", "P4", "P5", "P6", "P7", "P8", "P9", "P10"]}

def read(rel):
    p = os.path.join(root, rel)
    if not os.path.isfile(p):
        return None
    return open(p, encoding="utf-8").read()

def frontmatter(t):
    m = re.match(r"^---\n(.*?)\n---\n", t, re.S)
    return m.group(1) if m else None

def cut(t, start_re, end_re):
    """Text from the first line matching start_re up to (not including) the next line matching end_re."""
    lines = t.split("\n")
    out, on = [], False
    for ln in lines:
        if not on:
            if re.match(start_re, ln):
                on = True
                out.append(ln)
            continue
        if re.match(end_re, ln):
            break
        out.append(ln)
    return "\n".join(out) if on else None

docs = {}
for p in SKILL_PORTS:
    docs[p] = read(f"{p}/skills/prospect/SKILL.md")
mdc = read(CURSOR)
docs["cursor"] = cut(mdc, r"^## /prospect\s*$", r"^## /") if mdc is not None else None

templates = {}
for name, t in docs.items():
    if t is None:
        for a in fails:
            fails[a].append(f"{name}: prospect text not found")
        continue
    low = t.lower()
    step0 = cut(t, r"^## Step 0:", r"^## Step 0\.5")
    s36 = cut(t, r"^## Step 3\.6", r"^## Step ")
    s36l = s36.lower() if s36 is not None else None
    s46 = cut(t, r"^### 4\.6\.", r"^### 4\.7\.")
    step6 = cut(t, r"^## Step 6:", r"^## Step 7:")
    fm = frontmatter(t) if name in SKILL_PORTS else None

    # P1
    if step0 is None or "--cold" not in step0 or "--summary" not in step0:
        fails["P1"].append(f"{name}: Step 0 lacks --cold/--summary")
    if name in HINT_PORTS:
        hint = [l for l in (fm or "").split("\n") if l.startswith("argument-hint:")]
        if not hint or "[--cold]" not in hint[0] or "[--summary]" not in hint[0]:
            fails["P1"].append(f"{name}: argument-hint lacks [--cold] [--summary]")

    # P2
    heads = [l for l in t.split("\n") if l.startswith("## Step ")]
    h36 = [l for l in heads if l.startswith("## Step 3.6")]
    if not h36 or "cold read" not in h36[0].lower():
        fails["P2"].append(f"{name}: no '## Step 3.6' heading naming the cold read")
    else:
        order = [l.split(":")[0] for l in heads]
        try:
            i35, i36, i4 = order.index("## Step 3.5"), order.index(h36[0].split(":")[0]), order.index("## Step 4")
            if not (i35 < i36 < i4):
                fails["P2"].append(f"{name}: Step 3.6 is not between Step 3.5 and Step 4")
        except ValueError as e:
            fails["P2"].append(f"{name}: heading order unreadable ({e})")

    # P3
    m = re.search(r"<!-- cold-read-template:begin -->\n(.*?)<!-- cold-read-template:end -->", t, re.S)
    if not m:
        fails["P3"].append(f"{name}: no cold-read-template block")
    else:
        templates[name] = m.group(1)
        nums = [int(x) for x in re.findall(r"^(\d+)\. ", m.group(1), re.M)]
        if nums != [1, 2, 3, 4, 5]:
            fails["P3"].append(f"{name}: template numbered items are {nums}, not 1-5")

    # P4, P8, P9 — inside Step 3.6 only
    if s36l is None:
        fails["P4"].append(f"{name}: no Step 3.6")
        fails["P8"].append(f"{name}: no Step 3.6")
    else:
        need = {
            "agent type": "aria-knowledge:cold-reader",
            "fallback": "general-purpose",
            "stamp": "claude code docs read 2026-11-15; measured on 2.1.325",
            "fresh reader": "fresh reader",
            "read in place (D7)": "in place",
            "gap a": "auto memory",
            "gap b": "system prompt",
            "gap c": "subagentstart",
            "gap d": "working directory",
            "gap e": "sessionstart",
            "five gaps named": "five known gaps",
            "block: subagent type": "subagent type",
            "block: where read": "where the plan was read",
            "block: git status": "git status",
            "block: item-5 comparison": "item-5",
        }
        miss = [k for k, v in need.items() if v not in s36l]
        if miss:
            fails["P4"].append(f"{name}: Step 3.6 lacks {', '.join(miss)}")
        if NOT_RUN not in s36l:
            fails["P8"].append(f"{name}: Step 3.6 lacks the not-run line")
        hits = [w for w in ("instruction-free", "context-free", "plan agent") if w in s36l]
        if hits:
            fails["P9"].append(f"{name}: Step 3.6 says {', '.join(hits)}")

    # P5
    if s46 is None or "four questions" not in s46.lower() or "in-flight work" not in s46.lower():
        fails["P5"].append(f"{name}: 4.6 lacks 'Four questions' / the in-flight-work question")
    elif "three questions" in s46.lower():
        fails["P5"].append(f"{name}: 4.6 still says 'Three questions'")

    # P6
    if step6 is None or "--summary" not in step6:
        fails["P6"].append(f"{name}: Step 6 lacks the --summary rule")

    # P7
    if name == "plugin-claude-code":
        at = [l for l in (fm or "").split("\n") if l.startswith("allowed-tools:")]
        tools = [x.strip() for x in at[0].split(":", 1)[1].split(",")] if at else []
        if "Agent" not in tools:
            fails["P7"].append(f"{name}: allowed-tools is {tools}")

    # P10
    if name in PINNED_DESC:
        d = [l for l in (fm or "").split("\n") if l.startswith("description:")]
        h = hashlib.sha256(d[0].encode("utf-8")).hexdigest() if len(d) == 1 else None
        if h != PINNED_DESC[name]:
            fails["P10"].append(f"{name}: description changed (sha256 {h})")

if len(templates) == len(docs) and len(set(templates.values())) != 1:
    base = templates["plugin-claude-code"]
    diff = [n for n, v in templates.items() if v != base]
    fails["P3"].append("template differs from plugin-claude-code in: " + ", ".join(diff))

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
