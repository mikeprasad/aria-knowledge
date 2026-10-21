#!/bin/sh
# claude-ai-upload-limits.sh — the plugin must pass claude.ai's upload validation.
#
# claude.ai (organization upload, org sync, Cowork) validates a plugin server-side and
# refuses it on any finding. 2026-10-20 it rejected aria-knowledge with 27 errors:
#   - "Plugin description must be at most 500 characters."   (not in any public doc)
#   - "SKILL.md description cannot contain XML tags"          (13 skills, <path>-style
#      placeholders; Anthropic's published quick_validate.py rejects ANY < or >)
#   - "field 'description' in SKILL.md must be at most 1024 characters"
# plus, one release earlier, a top-level bin/. None of these show up anywhere else: the
# plugin installs and runs in Claude Code with every one of them. So they are checked here,
# for the two ports claude.ai installs — claude-code and cowork.
#
# Square brackets are banned too, as a precaution: a reported claude.ai bug silently DROPS
# a skill whose description contains [name] — no error at all, which is worse than a
# rejection. Bound: this checks the rules we have seen enforced or documented; claude.ai's
# validator is not public, so a rule it adds later will only show at upload.
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PASS=0; FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

# One checker, used for the real ports AND for the planted controls, so a control that
# fires proves the same code path the real check runs.
check_port() { # $1 = port dir; prints one finding per line, nothing when clean
  python3 -I - "$1" <<'PY'
import json, re, glob, os, sys
port = sys.argv[1]
pj = os.path.join(port, ".claude-plugin", "plugin.json")
d = json.load(open(pj, encoding="utf-8"))
n = len(d.get("description", ""))
if n > 500: print(f"plugin.json description {n} chars > 500")
if os.path.isdir(os.path.join(port, "bin")): print("top-level bin/ present")
skills = sorted(glob.glob(os.path.join(port, "skills", "*", "SKILL.md")))
print(f"#parsed {len(skills)}")
for p in skills:
    t = open(p, encoding="utf-8").read()
    m = re.match(r"^---\n(.*?)\n---\n", t, re.S)
    front = m.group(1) if m else ""
    sk = os.path.basename(os.path.dirname(p))
    dm = re.search(r'^description:\s*"(.*)"\s*$', front, re.M) or re.search(r"^description:\s*(.*)$", front, re.M)
    if not dm or not dm.group(1).strip():
        print(f"{sk}: description missing or not a single line"); continue
    desc = dm.group(1).replace('\\"', '"')
    if len(desc) > 1024: print(f"{sk}: description {len(desc)} chars > 1024")
    if len(desc.encode()) > 1024: print(f"{sk}: description {len(desc.encode())} bytes > 1024")
    bad_chars = sorted(set(c for c in desc if c in "<>[]"))
    if bad_chars: print(f"{sk}: description contains {' '.join(bad_chars)}")
    nm = re.search(r"^name:\s*(\S+)\s*$", front, re.M)
    if nm and nm.group(1).strip('"') != sk: print(f"{sk}: name {nm.group(1)} != directory")
PY
}

for port in plugin-claude-code plugin-claude-cowork; do
  out=$(check_port "$REPO_ROOT/$port")
  parsed=$(printf '%s\n' "$out" | sed -n 's/^#parsed //p')
  findings=$(printf '%s\n' "$out" | grep -v '^#parsed' || true)
  [ "${parsed:-0}" -ge 20 ] && ok "$port: positive control — $parsed skills parsed" \
                            || bad "$port parse" "only ${parsed:-0} skills parsed — the checker is not reading the port"
  [ -z "$findings" ] && ok "$port: passes the claude.ai upload limits" \
                     || bad "$port limits" "$(printf '%s' "$findings" | tr '\n' ';')"
done

# Planted controls: each predicate must FIRE on a value that breaks it. Without these, a
# checker with a broken regex reports every port clean.
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/p/.claude-plugin" "$TMP/p/skills/good" "$TMP/p/skills/tag" "$TMP/p/skills/long" "$TMP/p/skills/sq" "$TMP/p/skills/nm" "$TMP/p/bin"
python3 -I -c "import json;json.dump({'name':'p','description':'x'*501},open('$TMP/p/.claude-plugin/plugin.json','w'))"
printf -- '---\ndescription: "fine"\n---\n' > "$TMP/p/skills/good/SKILL.md"
printf -- '---\ndescription: "run /x file <path>"\n---\n' > "$TMP/p/skills/tag/SKILL.md"
python3 -I -c "open('$TMP/p/skills/long/SKILL.md','w').write('---\ndescription: \"' + 'a'*1025 + '\"\n---\n')"
printf -- '---\ndescription: "opts [auto|snap]"\n---\n' > "$TMP/p/skills/sq/SKILL.md"
printf -- '---\nname: other\ndescription: "fine"\n---\n' > "$TMP/p/skills/nm/SKILL.md"
ctl=$(check_port "$TMP/p")
for want in "plugin.json description 501" "top-level bin/" "tag: description contains <" "long: description 1025 chars" "sq: description contains [" "nm: name other"; do
  printf '%s\n' "$ctl" | grep -qF "$want" && ok "control fires: $want" || bad "control dead" "no finding for: $want"
done
printf '%s\n' "$ctl" | grep -q '^good:' && bad "control false positive" "a clean skill was flagged" || ok "control: a clean skill is not flagged"

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
