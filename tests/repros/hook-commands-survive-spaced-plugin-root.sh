#!/bin/sh
# hook-commands-survive-spaced-plugin-root.sh — v2.57.2: every hook command must run
# when the plugin root contains a space.
#
# Why (measured 2026-10-21/22): Claude desktop app 3.1623.1 installs plugins under
# ~/Library/Application Support/Claude/local-agent-mode-sessions/…/rpm/plugin_<id>/.
# The hook commands were `bash ${CLAUDE_PLUGIN_ROOT}/scripts/<x>.sh` with the
# variable unquoted, so the shell split the path at the space and bash exited 127
# ("…/Library/Application: No such file or directory"). Exit 127 is a NON-blocking
# hook error, so every hook was skipped and the Rule 22 edit gate failed OPEN:
# ~4,900 failures across 14 sessions in seven hours, 173 Edit/Write calls ungated.
#
# What this runs: every hook command string from the Claude Code manifest and the
# Codex hooks.json, through `sh -c`, against a stub plugin root whose path holds a
# space. Each referenced script is replaced by a stub that prints the path it was
# invoked as, so no real hook runs. Two substitution modes, because the host may
# either export the variable or substitute it into the string before the shell
# sees it — the fix has to hold for both.
#
# Controls:
#   C1  every hook command names a plugin-root variable (none silently skipped)
#   C2  every referenced script exists in the REAL plugin tree (a stub cannot hide
#       a wrong path)
#   C3  the same harness with a space-free root passes, so a red below is caused
#       by the space, not by the harness
#
# Declared before the fix: C1-C3 PASS; S-claude-code-env/text 19/19 FAIL;
# S-codex-env/text 8/8 FAIL. After quoting: all PASS.
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PASS=0; FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
LIST="$WORK/commands.tsv"

# port<TAB>variable<TAB>relative-script<TAB>command — one line per hook command.
python3 - "$REPO_ROOT" > "$LIST" <<'PY'
import json, re, sys
repo = sys.argv[1]
sources = [
    ("claude-code", repo + "/plugin-claude-code/.claude-plugin/plugin.json"),
    ("codex", repo + "/plugin-openai-codex/hooks.json"),
]
pat = re.compile(r'\$\{(CLAUDE_PLUGIN_ROOT|PLUGIN_ROOT)\}(/[^"\s]+)')
for port, path in sources:
    hooks = json.load(open(path))["hooks"]
    for groups in hooks.values():
        for group in groups:
            for h in group.get("hooks", []):
                cmd = h.get("command", "")
                m = pat.search(cmd)
                var, rel = (m.group(1), m.group(2)) if m else ("-", "-")
                print("\t".join([port, var, rel, cmd]))
PY

TAB=$(printf '\t')
count() { awk -F"$TAB" -v p="$1" '$1==p' "$LIST" | wc -l | tr -d ' '; }
CC=$(count claude-code); CX=$(count codex)

# C1 — every command names a root variable, and the parse found something.
unrooted=$(awk -F"$TAB" '$2=="-"' "$LIST" | wc -l | tr -d ' ')
# 18 since 2026-10-25: session-start-rules.sh merged into session-start-check.sh (one command fewer).
if [ "$CC" -ge 18 ] && [ "$CX" -ge 8 ] && [ "$unrooted" -eq 0 ]; then
  ok "C1-every-command-parsed-and-rooted (claude-code $CC, codex $CX)"
else
  bad "C1-every-command-parsed-and-rooted" "claude-code $CC, codex $CX, without a root variable $unrooted"
fi

# C2 — each referenced script exists in the real plugin tree.
missing=""
while IFS="$TAB" read -r port var rel cmd; do
  [ "$rel" = "-" ] && continue
  case "$port" in claude-code) base="plugin-claude-code" ;; codex) base="plugin-openai-codex" ;; esac
  [ -f "$REPO_ROOT/$base$rel" ] || missing="$missing $base$rel"
done < "$LIST"
[ -z "$missing" ] && ok "C2-referenced-scripts-exist" || bad "C2-referenced-scripts-exist" "missing:$missing"

# Build a stub root at $1: every referenced script prints the path it ran as.
make_root() {
  while IFS="$TAB" read -r port var rel cmd; do
    [ "$rel" = "-" ] && continue
    mkdir -p "$1$(dirname "$rel")"
    printf '#!/bin/sh\nprintf "ARIA_STUB_RAN %%s\\n" "$0"\n' > "$1$rel"
  done < "$LIST"
}

# run_all <root> <port> <mode> → prints failures, one per line; empty = all ran.
run_all() {
  root="$1"; want="$2"; mode="$3"
  while IFS="$TAB" read -r port var rel cmd; do
    [ "$port" = "$want" ] || continue
    [ "$rel" = "-" ] && continue
    if [ "$mode" = env ]; then
      out=$(env "$var=$root" sh -c "$cmd" </dev/null 2>&1) && rc=0 || rc=$?
    else
      expanded=$(python3 -c 'import sys; print(sys.argv[1].replace("${"+sys.argv[2]+"}", sys.argv[3]))' "$cmd" "$var" "$root")
      out=$(env -u "$var" sh -c "$expanded" </dev/null 2>&1) && rc=0 || rc=$?
    fi
    if [ "$rc" -ne 0 ] || [ "$out" != "ARIA_STUB_RAN $root$rel" ]; then
      printf '%s (exit %s: %s)\n' "$rel" "$rc" "$(printf '%s' "$out" | head -1)"
    fi
  done < "$LIST"
}

PLAIN="$WORK/plainroot"
SPACED="$WORK/Application Support/plugin root"
make_root "$PLAIN"
make_root "$SPACED"

# C3 — harness works when the root has no space.
c3=""
for p in claude-code codex; do for m in env text; do
  c3="$c3$(run_all "$PLAIN" "$p" "$m")"
done; done
[ -z "$c3" ] && ok "C3-harness-control-space-free-root" || bad "C3-harness-control-space-free-root" "$(printf '%s' "$c3" | head -1)"

# The guarded property.
for p in claude-code codex; do
  total=$(count "$p")
  for m in env text; do
    fails=$(run_all "$SPACED" "$p" "$m")
    n=$(printf '%s' "$fails" | grep -c . || true)
    if [ "$n" -eq 0 ]; then
      ok "S-$p-$m ($total/$total ran from a spaced root)"
    else
      bad "S-$p-$m" "$n/$total failed, e.g. $(printf '%s' "$fails" | head -1)"
    fi
  done
done

# ── Skill text ────────────────────────────────────────────────────────────────
# The host substitutes the root into SKILL.md bodies too (measured 2026-10-21: a
# loaded skill showed `/Users/…/Application Support/…/scripts/x.sh`, unquoted), so a
# skill line telling the agent to run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/x.sh` hands
# it a broken command. Flag a shell command word followed — across a line wrap — by
# an unquoted root. Prose path mentions read with the Read tool are left alone.
#   K0  the scanner flags a known-bad line and passes a known-good one (two-sided)
#   K-<port>  no unquoted command-position root in that port's skills
SCAN="$WORK/scan.py"
cat > "$SCAN" <<'PY'
import os, re, sys
PAT = re.compile(r'(?:^|[\s`(;\'])(bash|sh|source|python3?|\.)\s+\$\{(?:CLAUDE_PLUGIN_ROOT|PLUGIN_ROOT)')
def hits(text):
    return [text.count("\n", 0, m.start(1)) + 1 for m in PAT.finditer(text)]
if sys.argv[1] == "--self-test":
    bad = "run `bash\n   ${CLAUDE_PLUGIN_ROOT}/scripts/x.sh` and `sh -c '. ${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}/bin/y.sh'`"
    good = 'run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/x.sh"`; read `${CLAUDE_PLUGIN_ROOT}/template/a.md`'
    print("ok" if len(hits(bad)) == 2 and hits(good) == [] else "broken %s %s" % (hits(bad), hits(good)))
    sys.exit(0)
for root, _, files in os.walk(sys.argv[1]):
    for f in files:
        if f.endswith(".md"):
            p = os.path.join(root, f)
            for ln in hits(open(p, encoding="utf-8").read()):
                print("%s:%d" % (os.path.relpath(p, sys.argv[1]), ln))
PY
[ "$(python3 "$SCAN" --self-test)" = ok ] && ok "K0-scanner-two-sided" || bad "K0-scanner-two-sided" "$(python3 "$SCAN" --self-test)"
for d in plugin-claude-code plugin-openai-codex plugin-antigravity; do
  found=$(python3 "$SCAN" "$REPO_ROOT/$d/skills")
  n=$(printf '%s' "$found" | grep -c . || true)
  [ "$n" -eq 0 ] && ok "K-$d-skills-quote-the-root" || bad "K-$d-skills-quote-the-root" "$n unquoted, e.g. $(printf '%s' "$found" | head -1)"
done

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
