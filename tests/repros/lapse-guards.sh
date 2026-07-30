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

# ---------------------------------------------------------------------------
# C2 — assertions that cannot fail. A tautological assertion is a false green:
# it reports success without ever having been able to report failure (Rule 36).
# Syntactic detection only, warn-only, scoped to test-shaped paths.
# ---------------------------------------------------------------------------
TA="$REPO_ROOT/plugin-claude-code/bin/post-edit-tautology-check.sh"
run_ta() { printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"%s"}}' "$1" "$2" | sh "$TA" 2>/dev/null || true; }

[ -x "$TA" ] && ok "I tautology hook exists" || bad "I exists" "missing or not +x"

# RED: identical operands.
OUT=$(run_ta "/x/tests/test_a.py" "def test_x():\n    assert value == value\n")
echo "$OUT" | grep -q 'additionalContext' \
  && ok "J warns on identical-operand assert" || bad "J identical" "no warning (got: $OUT)"
echo "$OUT" | grep -q 'permissionDecision' \
  && bad "J warn-only" "emitted permissionDecision; C2 must be warn-only" || ok "J is warn-only"
echo "$OUT" | grep -qi 'semantic' \
  && ok "K states what it cannot detect" || bad "K limit" "does not disclose its own blind spot"

# RED: literal-true assertion.
OUT2=$(run_ta "/x/tests/test_b.py" "def test_y():\n    assert True\n")
echo "$OUT2" | grep -q 'additionalContext' \
  && ok "L warns on assert True" || bad "L assert True" "no warning"

# RED: the JS/TS shape.
OUT3=$(run_ta "/x/src/__tests__/thing.spec.ts" "it('works', () => { expect(got).toBe(got) })")
echo "$OUT3" | grep -q 'additionalContext' \
  && ok "M warns on expect(x).toBe(x)" || bad "M expect" "no warning"

# GREEN: a real assertion must stay silent.
OUT4=$(run_ta "/x/tests/test_c.py" "def test_z():\n    assert parse(raw) == expected\n")
[ -z "$OUT4" ] && ok "N silent on a real assertion" || bad "N real" "warned on a valid test: $OUT4"

# GREEN: scoped to test paths — a non-test file is not this hook's business.
OUT5=$(run_ta "/x/src/app.py" "assert x == x\n")
[ -z "$OUT5" ] && ok "O scoped to test-shaped paths" || bad "O scope" "warned on a non-test file"

# GREEN: multi-line content must not break extraction (the echo-escape lesson).
OUT6=$(run_ta "/x/tests/test_d.py" "import os\nimport sys\n\ndef test_w():\n    assert compute(1) == 2\n")
[ -z "$OUT6" ] && ok "P silent across a multi-line real test" || bad "P multiline" "false positive on multi-line content"

grep -q 'post-edit-tautology-check.sh' "$MANIFEST" \
  && ok "Q registered in plugin.json" || bad "Q registered" "hook not wired"

# R — shell self-comparison. This repo's own guards ARE shell, so a `[ "$a" = "$a" ]` in a
# repro suite is exactly the false green this hook exists to catch. (Dropped during the
# portability rewrite that removed regex backreferences; re-added here with awk.)
# Fixtures are deliberately quote-free. The hook extracts its field with the sibling
# `grep -o '"key":"[^"]*"'` idiom, which truncates at the first escaped quote, so a file
# containing a double quote is only partially examined. That fails toward a MISSED warning,
# never a spurious one, and is stated in the hook header. A quoted fixture would be testing
# the extractor's limit rather than the detector.
OUT7=$(run_ta "/x/tests/repros/thing.sh" "[ \$got = \$got ] && ok A || bad A x\n")
echo "$OUT7" | grep -q 'additionalContext' \
  && ok "R warns on a shell self-comparison" || bad "R shell" "no warning (got: $OUT7)"

OUT8=$(run_ta "/x/tests/repros/thing.sh" "[ \$got = \$want ] && ok A || bad A x\n")
[ -z "$OUT8" ] && ok "R silent on a real shell comparison" || bad "R shell real" "warned on a valid test: $OUT8"

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
