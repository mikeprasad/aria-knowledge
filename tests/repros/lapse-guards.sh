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

# ---------------------------------------------------------------------------
# C1 — RETIRED 2026-08-26. What remains here PINS the retirement.
#
# pre-bash-write-check.sh warned when a shell command mutated a file in place,
# bypassing the Rule 22 gate. The intent was sound; the method decided from the
# COMMAND STRING instead of resolving the mutation TARGET, and that made it wrong
# in both directions — silent on backup-then-mutate (the command merely MENTIONS a
# temp path, and that is the careful pattern this project mandates), and firing on
# any command that just QUOTES an idiom like `sed -i`, including a commit whose
# MESSAGE did. Ruled out rather than tuned: "if it is wrong then don't use it."
#
# ➜ SUPERSEDED 2026-08-27 (v2.48.1). The two assertions that pinned "not shipped"
# and "not registered" have been REPLACED, not deleted — and they were doing their
# job: they exist so a silent re-wire fails loudly, and they caught the restoration.
#
# What changed is that the restoration is NOT a re-wire of the ruled-out method.
# The measured SCOPE is unchanged (in-place mutation only, 0.674% of 25,508 calls);
# only the METHOD is replaced — targets are RESOLVED via bin/pre-bash-write-resolve.py
# (heredoc bodies stripped, shlex operator-aware tokenizing, per-statement extraction,
# temp exemption applied to the RESOLVED PATH), which closes BOTH directions above
# with one mechanism. It is also WARN-ONLY and can never deny.
#
# ⛔ THE INVARIANT THAT SURVIVES THE RETIREMENT, and it is the load-bearing one:
# the ARCHIVED copy must never become the registered one. That is the actual
# "silent re-wire" this block was written to prevent, and it is now asserted
# directly rather than as a side effect of asserting absence.
#
# Behaviour is proven in tests/repros/bash-write-target-resolution.sh, whose AC1 and
# AC2 ARE the two historical defects stated as executable controls.
[ -f "$BW" ] && ok "C1 restored: the corrected hook ships in bin/" \
             || bad "C1 restored" "pre-bash-write-check.sh is missing from bin/"
[ -f "$REPO_ROOT/plugin-claude-code/bin/.archived/pre-bash-write-check.sh" ] \
  && ok "C1 archived per Rule 6 with its mechanism recorded" \
  || bad "C1 archive" "the retired hook is not in bin/.archived/"
grep -q 'SUPERSEDED 2026-08-27' "$REPO_ROOT/plugin-claude-code/bin/.archived/pre-bash-write-check.sh" \
  && ok "C1 the archive forward-points at its successor" \
  || bad "C1 archive pointer" "the archive asserts retirement with no pointer to the live hook"
grep -q 'pre-bash-write-check\.sh' "$MANIFEST" \
  && ok "C1 the corrected hook is registered" \
  || bad "C1 registered" "the corrected hook is not registered in plugin.json"
grep -q '\.archived/pre-bash-write-check\.sh' "$MANIFEST" \
  && bad "C1 archived-not-registered" "the ARCHIVED hook is registered — the ruled-out method is live" \
  || ok "C1 the archived copy is not the registered one"
grep -q 'pre-bash-write-resolve\.py' "$BW" \
  && ok "C1 the hook delegates to the target resolver, not to string matching" \
  || bad "C1 method" "the hook does not reference the resolver — the ruled-out method may be back"

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

# --- S: the bypass LEDGER is GONE with its only writer.
# The retired hook was the sole producer of ${TMPDIR}/aria-r22-bypass-<session_id>
# — measured: grep for that name across bin/ returns only bin/.archived/. So the
# ledger can no longer be populated, and the two closing skills that REPORTED it
# had their instruction removed rather than left describing an empty file. This
# assertion is what keeps those two facts in step.
#
# ⚠ Asserted POSITIVELY, on the retraction, not negatively on the path. The first
# version grepped the skills for `aria-r22-bypass` and expected zero — and it failed,
# because the retraction text NAMES the retired path in order to explain itself. A
# guard that reads the very text its own fix adds is the recurring
# `own-comment-enters-the-text-its-guard-reads` shape; a mention is not a read.
for sk in handoff wrapup; do
  grep -qi 'no ledger to read' "$REPO_ROOT/plugin-claude-code/skills/$sk/SKILL.md" \
    && ok "S /$sk no longer reads the writerless ledger" \
    || bad "S $sk orphan" "still instructs reading a ledger whose only writer is archived"
done

# T: both closing skills must check pending handoffs.
# ⚠ The bypass-ledger half of this was REMOVED 2026-08-26 and its removal is not a
# relaxation — it directly contradicted S above. It required both skills to report a
# ledger whose only writer is now archived, so satisfying T would have meant keeping
# an instruction to read a file that can never have entries. S asserts the absence; T
# asserted the presence; only one can be right, and the writer decides which.
for sk in handoff wrapup; do
  F="$REPO_ROOT/plugin-claude-code/skills/$sk/SKILL.md"
  grep -qi 'Pending handoffs' "$F" \
    && ok "T /$sk checks pending handoffs" || bad "T $sk pending" "does not check pending handoffs"
done

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
