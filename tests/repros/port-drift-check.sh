#!/bin/sh
# Repro: bin/check-port-drift.sh detects surface drift, re-baselines on --update,
# tolerates SLA=undeclared drift, and catches the antigravity version-pair trap.
# Hermetic — drives the checker against a tmp fixture via the PORT_LEDGER /
# PORT_LEDGER_ROOT env seam, never the real repo.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/../../plugin-claude-code/bin/check-port-drift.sh"
fail() { echo "FAIL: $1"; exit 1; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# Part A — surface drift on a declared (continuous) port
# ---------------------------------------------------------------------------
ROOT="$TMP/a"; mkdir -p "$ROOT"
printf 'alpha\n' > "$ROOT/a.txt"
printf 'bravo\n' > "$ROOT/b.txt"
LEDGER="$TMP/ledger-a.json"
# Skeleton lists the two surfaces with placeholder hashes; --update will baseline.
cat > "$LEDGER" <<'JSON'
{"testport":{"version":"0","parity_target":"0","last_parity_pass":"2026-01-01","sla":"continuous","surfaces":{"a.txt":"PLACEHOLDER","b.txt":"PLACEHOLDER"}}}
JSON

PORT_LEDGER="$LEDGER" PORT_LEDGER_ROOT="$ROOT" sh "$SCRIPT" --update testport >/dev/null \
  || fail "baseline --update returned non-zero"
PORT_LEDGER="$LEDGER" PORT_LEDGER_ROOT="$ROOT" sh "$SCRIPT" --quiet \
  || fail "fresh baseline should be clean (--quiet exit 0)"

# Mutate one surface -> drifted + --quiet exit 1
printf 'alpha-CHANGED\n' > "$ROOT/a.txt"
out=$(PORT_LEDGER="$LEDGER" PORT_LEDGER_ROOT="$ROOT" sh "$SCRIPT")
printf '%s' "$out" | grep -q "a.txt" || fail "a.txt missing from table"
printf '%s' "$out" | awk '/a.txt/{print}' | grep -q "drifted" || fail "mutated a.txt not reported drifted"
printf '%s' "$out" | awk '/b.txt/{print}' | grep -q "ok" || fail "unchanged b.txt should be ok"
if PORT_LEDGER="$LEDGER" PORT_LEDGER_ROOT="$ROOT" sh "$SCRIPT" --quiet; then
  fail "--quiet should exit 1 on continuous-SLA drift"
fi

# --update re-baselines -> ok again
PORT_LEDGER="$LEDGER" PORT_LEDGER_ROOT="$ROOT" sh "$SCRIPT" --update testport >/dev/null
PORT_LEDGER="$LEDGER" PORT_LEDGER_ROOT="$ROOT" sh "$SCRIPT" --quiet \
  || fail "--update should re-baseline mutated surface back to ok"

# ---------------------------------------------------------------------------
# Part B — SLA=undeclared tolerates drift (does not fail --quiet)
# ---------------------------------------------------------------------------
ROOT_U="$TMP/u"; mkdir -p "$ROOT_U"
printf 'x\n' > "$ROOT_U/s.txt"
LEDGER_U="$TMP/ledger-u.json"
cat > "$LEDGER_U" <<'JSON'
{"someport":{"version":"0","parity_target":"0","last_parity_pass":"2026-01-01","sla":"undeclared","surfaces":{"s.txt":"PLACEHOLDER"}}}
JSON
PORT_LEDGER="$LEDGER_U" PORT_LEDGER_ROOT="$ROOT_U" sh "$SCRIPT" --update someport >/dev/null
printf 'x-CHANGED\n' > "$ROOT_U/s.txt"
outu=$(PORT_LEDGER="$LEDGER_U" PORT_LEDGER_ROOT="$ROOT_U" sh "$SCRIPT")
printf '%s' "$outu" | awk '/s.txt/{print}' | grep -q "drifted" || fail "undeclared drift should still SHOW as drifted"
PORT_LEDGER="$LEDGER_U" PORT_LEDGER_ROOT="$ROOT_U" sh "$SCRIPT" --quiet \
  || fail "undeclared-SLA drift must be TOLERATED (--quiet exit 0)"

# ---------------------------------------------------------------------------
# Part C — antigravity version-pair drift
# ---------------------------------------------------------------------------
ROOT_AG="$TMP/ag"; mkdir -p "$ROOT_AG/plugin-antigravity"
printf '1.0.0\n' > "$ROOT_AG/plugin-antigravity/version.txt"
printf '{\n  "version": "2.0.0"\n}\n' > "$ROOT_AG/plugin-antigravity/plugin.json"
LEDGER_AG="$TMP/ledger-ag.json"
cat > "$LEDGER_AG" <<'JSON'
{"antigravity":{"version":"1.0.0","parity_target":"2.0.0","last_parity_pass":"2026-01-01","sla":"undeclared","surfaces":{}}}
JSON
outag=$(PORT_LEDGER="$LEDGER_AG" PORT_LEDGER_ROOT="$ROOT_AG" sh "$SCRIPT")
printf '%s' "$outag" | grep -q "version-pair-drift" || fail "antigravity version-pair mismatch not detected"
if PORT_LEDGER="$LEDGER_AG" PORT_LEDGER_ROOT="$ROOT_AG" sh "$SCRIPT" --quiet; then
  fail "--quiet should exit 1 on version-pair-drift"
fi
# Matching pair -> ok
printf '2.0.0\n' > "$ROOT_AG/plugin-antigravity/version.txt"
PORT_LEDGER="$LEDGER_AG" PORT_LEDGER_ROOT="$ROOT_AG" sh "$SCRIPT" --quiet \
  || fail "matching version pair should be clean"

# ---------------------------------------------------------------------------
# Part D — version lag is measured against LIVE canonical, not a frozen ledger pair
#
# Before 2026-08-17 the lag line compared a port's own `version` to its own
# `parity_target`. Both are written together by --update, so they were equal by
# construction at baseline time and never diverged as canonical moved on — the line
# was silent for the only lag that exists (the kind accruing AFTER a baseline).
# Measured then: antigravity read 2.36.0/2.36.0 and reported nothing while canonical
# was 2.46.1.
#
# The two assertions this block replaced ("codex/cursor prerelease suffix produced no
# false lag") asserted an ABSENCE that is now true by construction — the port's own
# version, suffix and all, is no longer an operand. They would have passed whether or
# not the feature existed. Replaced rather than adjusted, deliberately.
# ---------------------------------------------------------------------------

# Writes a canonical manifest under a fixture root so canonical_version() resolves.
# No prior fixture created one — every root here is a bare tmp dir — which is exactly
# why the empty-canonical guard (Part D5) is load-bearing.
mk_canon() {
  mkdir -p "$1/plugin-claude-code/.claude-plugin"
  printf '{\n  "version": "%s"\n}\n' "$2" > "$1/plugin-claude-code/.claude-plugin/plugin.json"
}

ROOT_V="$TMP/v"; mkdir -p "$ROOT_V"
mk_canon "$ROOT_V" "3.0.0"
LEDGER_V="$TMP/ledger-v.json"
cat > "$LEDGER_V" <<'JSON'
{
  "claude-code":{"version":"3.0.0","parity_target":"2.0.0","last_parity_pass":"2026-06-11","sla":"undeclared","surfaces":{}},
  "openai-codex":{"version":"2.0.0-codex.0","parity_target":"2.0.0","last_parity_pass":"2026-06-11","sla":"undeclared","surfaces":{}},
  "cursor-template":{"version":"3.0.0-cursor.0","parity_target":"3.0.0","last_parity_pass":"2026-06-11","sla":"undeclared","surfaces":{}},
  "claude-cowork":{"version":"1.4.0","parity_target":"3.0.0","last_parity_pass":"2026-06-11","sla":"undeclared","surfaces":{}}
}
JSON
outv=$(PORT_LEDGER="$LEDGER_V" PORT_LEDGER_ROOT="$ROOT_V" sh "$SCRIPT")

# D1 — synced to an older canonical than the live one -> lag, naming both versions
printf '%s' "$outv" | grep -q "openai-codex.*lag" \
  || fail "D1 port synced to an older canonical should report lag"
printf '%s' "$outv" | grep -q "openai-codex.*synced to 2.0.0 → canonical 3.0.0" \
  || fail "D1 lag line should name the synced target and live canonical"

# D2 — synced to the live canonical -> no lag
printf '%s' "$outv" | grep -q "cursor-template.*lag" \
  && fail "D2 port synced to live canonical should NOT report lag"

# D3 — REGRESSION GUARD for the permanent false positive. A port on an independent
# version scheme (cowork's 1.x) whose parity_target IS current must be silent. Under the
# old comparison its own 1.4.0 could never equal a 3.0.0 target, so it flagged forever.
printf '%s' "$outv" | grep -q "claude-cowork.*lag" \
  && fail "D3 independent version scheme must not produce lag when parity_target is current"

# D4 — claude-code is the baseline and never reports lag, even with a stale parity_target
printf '%s' "$outv" | grep -q "claude-code.*lag" \
  && fail "D4 claude-code is the baseline and must never report lag"

# D5 — A1 GUARD: canonical unresolvable -> no lag for ANY port, and no crash.
# canonical_version() is tolerant (empty when the manifest is absent) because its other
# caller is --update stamping. Empty as a comparison operand would make every port differ.
rm -f "$ROOT_V/plugin-claude-code/.claude-plugin/plugin.json"
outnc=$(PORT_LEDGER="$LEDGER_V" PORT_LEDGER_ROOT="$ROOT_V" sh "$SCRIPT")
ncrc=$?
[ "$ncrc" -eq 0 ] || fail "D5 absent canonical manifest should not crash the report"
printf '%s' "$outnc" | grep -q "lag" \
  && fail "D5 absent canonical manifest must produce NO lag line for any port"
# positive control: the report still ran and produced its table
printf '%s' "$outnc" | grep -q "PORT" \
  || fail "D5 control — report did not run at all, so the no-lag result proves nothing"

# D6 — lag is informational: it must never change the exit code
mk_canon "$ROOT_V" "3.0.0"
PORT_LEDGER="$LEDGER_V" PORT_LEDGER_ROOT="$ROOT_V" sh "$SCRIPT" --quiet \
  || fail "D6 lag must not fail --quiet (it is informational, not a surface status)"

echo "PASS port-drift-check"
