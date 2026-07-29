#!/bin/sh
# lapse-guards.sh — guards for two recurring lapses that prose did not hold.
#
# C1: a structural edit performed through the shell routes AROUND the Edit/Write
#     PreToolUse gate, so Rule 22 never fires and the change lands with no scope
#     assessment recorded.
#
# Both guards are WARN-ONLY by design. A false positive would interfere with
# legitimate shell work in every session, which is worse than the lapse. The
# assertions below FAIL if either ever emits a permissionDecision.
#
# The C1 rule is narrowed to IN-PLACE MUTATION, not file creation. That
# distinction came from measuring 25,508 real Bash calls: `cat > newfile` is a
# throwaway probe (legitimate, frequent), while `sed -i` / `.write_text()` on a
# tracked file is the actual lapse. The narrowed rule fires on 0.674% of calls,
# about 1 in 148.
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BW="$REPO_ROOT/plugin-claude-code/bin/pre-bash-write-check.sh"
MANIFEST="$REPO_ROOT/plugin-claude-code/.claude-plugin/plugin.json"
PASS=0; FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

run_bw() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" | sh "$BW" 2>/dev/null || true; }

[ -x "$BW" ] && ok "A bash-write hook exists" || bad "A exists" "missing or not +x"

# B — RED: the dominant real lapse. A python heredoc mutating a tracked doc.
OUT=$(run_bw "python3 - <<PY\nimport pathlib; p=pathlib.Path('cs/PROGRESS.md'); p.write_text(s)\nPY")
echo "$OUT" | grep -q 'additionalContext' \
  && ok "B warns on .write_text() mutation" || bad "B write_text" "no warning (got: $OUT)"
echo "$OUT" | grep -q 'permissionDecision' \
  && bad "B warn-only" "emitted a permissionDecision; C1 must be warn-only" \
  || ok "B is warn-only (never denies)"
echo "$OUT" | grep -qi 'Edit' \
  && ok "B names the right tool to use instead" || bad "B guidance" "warning does not point at Edit/Write"

# C — RED: an in-place rename via sed.
OUT2=$(run_bw "sed -i '' s/_model_has_field/model_has_field/g commonspace/checks.py")
echo "$OUT2" | grep -q 'additionalContext' \
  && ok "C warns on sed -i" || bad "C sed -i" "no warning (got: $OUT2)"

# D — GREEN: CREATION of a throwaway probe is NOT the lapse. Measured as the
# dominant false-positive class; the rule must not fire on it.
for cmd in "cat > ./diag.spec.ts <<EOF" "cat > commonspace/test_probe_setup.py <<PYEOF"; do
  O=$(run_bw "$cmd")
  [ -z "$O" ] && ok "D silent on file creation: ${cmd%% *} ..." \
              || bad "D creation" "warned on a throwaway creation: $cmd"
done

# E — GREEN: ordinary read-only work must stay silent.
for cmd in "git status" "grep -rn foo src/" "ls -la" "npm test"; do
  O=$(run_bw "$cmd")
  [ -z "$O" ] && ok "E silent on: $cmd" || bad "E silent $cmd" "warned on a benign command"
done

# F — GREEN: temp and scratchpad writes are exempt (11.4% of all calls; all legitimate).
for cmd in "sed -i '' s/a/b/ /tmp/x.py" "python3 -c \\\"open('/private/tmp/claude-501/scratchpad/z.py','w')\\\""; do
  O=$(run_bw "$cmd")
  [ -z "$O" ] && ok "F exempt: temp/scratchpad path" || bad "F exempt" "warned on a temp path: $cmd"
done

# G — GREEN: appending to a markdown backlog is legitimate (1.27% of calls, all benign).
O=$(run_bw "cat >> \\\"\$KF/intake/insights-backlog.md\\\" <<EOF")
[ -z "$O" ] && ok "G silent on a markdown append" || bad "G markdown" "warned on an .md append"

# H — registered in the manifest.
grep -q 'pre-bash-write-check.sh' "$MANIFEST" \
  && ok "H registered in plugin.json" || bad "H registered" "hook not wired"

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
