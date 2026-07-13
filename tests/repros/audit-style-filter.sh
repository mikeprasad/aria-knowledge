#!/bin/sh
# audit-style-filter.sh — the extraction filter is the one executable piece of /audit style.
# Asserts extract-user-prose.py keeps GENUINE user prose and rejects command wrappers,
# stdout echoes, tool_results, and skill-injection preambles. Also asserts redaction of
# secret-bearing prose. Fixture locks the observed .jsonl shape so format drift fails loud.
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PY="$REPO_ROOT/plugin-claude-code/skills/audit-style/extract-user-prose.py"
FIX="$SCRIPT_DIR/fixtures/audit-style"
PASS=0; FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

A="$(python3 "$PY" "$FIX/session-a.jsonl")"
# A1: keeps the genuine "runs live" prose (fixture text is "run live"; substring "live" is
# the part shared with session-b's "running live" and absent from every noise line)
echo "$A" | grep -qi "live" && ok "A keeps genuine prose" || bad "A genuine" "runs-live prose dropped"
# A2: drops the local-command-caveat wrapper
echo "$A" | grep -qi "DO NOT respond" && bad "A caveat" "command caveat leaked as prose" || ok "A drops command caveat"
# A3: drops the skill-injection preamble
echo "$A" | grep -qi "Base directory for this skill" && bad "A preamble" "skill preamble leaked" || ok "A drops skill preamble"

N="$(python3 "$PY" "$FIX/session-noise.jsonl")"
# B1: slash-command yields no prose
echo "$N" | grep -qi "/model" && bad "B slash" "slash-command leaked" || ok "B drops slash-command"
# B2: stdout echo dropped
echo "$N" | grep -qi "Set model to Opus" && bad "B stdout" "stdout echo leaked" || ok "B drops stdout echo"
# B3: tool_result dropped
echo "$N" | grep -qi "file contents here" && bad "B toolresult" "tool_result leaked" || ok "B drops tool_result"
# B4 (REDACTION): the secret value never appears in output, even though the sentence is prose
echo "$N" | grep -q "sk-ABC123SECRETVALUE" && bad "B redact" "secret survived to output" || ok "B redacts secret"

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
