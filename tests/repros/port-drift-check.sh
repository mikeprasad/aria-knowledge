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
# Part D — port prerelease suffixes do not create false version lag
# ---------------------------------------------------------------------------
ROOT_V="$TMP/v"; mkdir -p "$ROOT_V"
LEDGER_V="$TMP/ledger-v.json"
cat > "$LEDGER_V" <<'JSON'
{
  "openai-codex":{"version":"2.30.0-codex.0","parity_target":"2.30.0","last_parity_pass":"2026-06-11","sla":"undeclared","surfaces":{}},
  "cursor-template":{"version":"2.30.0-cursor.0","parity_target":"2.30.0","last_parity_pass":"2026-06-11","sla":"undeclared","surfaces":{}},
  "someport":{"version":"1.0.0","parity_target":"2.0.0","last_parity_pass":"2026-06-11","sla":"undeclared","surfaces":{}}
}
JSON
outv=$(PORT_LEDGER="$LEDGER_V" PORT_LEDGER_ROOT="$ROOT_V" sh "$SCRIPT")
printf '%s' "$outv" | grep -q "openai-codex.*lag" && fail "codex prerelease suffix produced false lag"
printf '%s' "$outv" | grep -q "cursor-template.*lag" && fail "cursor prerelease suffix produced false lag"
printf '%s' "$outv" | grep -q "someport.*lag" || fail "real version lag should still be reported"

echo "PASS port-drift-check"
