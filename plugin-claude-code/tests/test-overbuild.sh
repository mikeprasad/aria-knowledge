# shellcheck shell=sh
# test-overbuild.sh — anti-over-build upgrade: marker grammar + lens-documented lint
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"

# --- marker grammar: a well-formed aria:simplification marker matches; malformed ones don't ---
MARKER_RE='aria:simplification — .+ \| limitation: .+ \| upgrade: .+'

good='// aria:simplification — used native Date instead of date-fns | limitation: no TZ math | upgrade: add date-fns if TZ bugs appear'
bad_no_upgrade='// aria:simplification — used native Date | limitation: no TZ math'
bad_generic='// TODO: simplify this later'

assert_eq "marker: well-formed matches" "1" \
  "$(printf '%s\n' "$good" | grep -Eq "$MARKER_RE" && echo 1 || echo 0)"
assert_eq "marker: missing upgrade rejected" "0" \
  "$(printf '%s\n' "$bad_no_upgrade" | grep -Eq "$MARKER_RE" && echo 1 || echo 0)"
assert_eq "marker: generic TODO not a marker" "0" \
  "$(printf '%s\n' "$bad_generic" | grep -Eq "$MARKER_RE" && echo 1 || echo 0)"

# --- /retrospect documents the lens, reads the library, carries marker-respect ---
RS="$ROOT/skills/retrospect/SKILL.md"
assert_eq "retrospect: lens flag documented" "1" \
  "$(grep -cq -- '--lens=overbuild' "$RS" && echo 1 || echo 0)"
assert_eq "retrospect: reads overbuild-patterns" "1" \
  "$(grep -cq 'overbuild-patterns.md' "$RS" && echo 1 || echo 0)"
assert_eq "retrospect: marker-respect present" "1" \
  "$(grep -cq 'resolved (marked)' "$RS" && echo 1 || echo 0)"

# --- /prospect documents the forward lens + reads the library ---
PS="$ROOT/skills/prospect/SKILL.md"
assert_eq "prospect: lens flag documented" "1" \
  "$(grep -cq -- '--lens=overbuild' "$PS" && echo 1 || echo 0)"
assert_eq "prospect: reads overbuild-patterns" "1" \
  "$(grep -cq 'overbuild-patterns.md' "$PS" && echo 1 || echo 0)"

# --- /readiness-audit carries an over-build probe + keeps it read-only ---
RA="$ROOT/skills/readiness-audit/SKILL.md"
assert_eq "readiness-audit: overbuild probe present" "1" \
  "$(grep -cq 'overbuild-patterns.md' "$RA" && echo 1 || echo 0)"
assert_eq "readiness-audit: probe is read-only" "1" \
  "$(grep -cq 'never mutates a build artifact' "$RA" && echo 1 || echo 0)"
