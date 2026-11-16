#!/usr/bin/env bats
# D8a census — every Antigravity suite that INVOKES any bin/antigravity/*-aria.sh wrapper must run it
# under a scratch HOME, or the wrapper (config.sh reads, and several wrappers write, under
# $HOME/.gemini/antigravity/) depends on or touches the real one. The census is every suite whose text
# names a wrapper — not just wrappers whose own source mentions $HOME, since a wrapper reaches HOME
# through the libraries it sources. For each invocation line (`bash ... $WRAPPER` or `bash ...
# <name>-aria.sh`), `export HOME=` must already have run: in setup(), or earlier in the same test or
# helper function.

@test "D8a: every suite invoking an Antigravity wrapper exports a scratch HOME before the call" {
  T="${BATS_TEST_DIRNAME}"
  A="$T/../bin/antigravity"
  missing=""
  checked=0
  for f in "$T"/*.bats; do
    [ "$(basename "$f")" = "test-antigravity-tests-isolate-home.bats" ] && continue
    names=""
    for w in "$A"/*-aria.sh; do
      wn=$(basename "$w")
      grep -q "$wn" "$f" && names="$names $wn"
    done
    [ -n "$names" ] || continue
    checked=$((checked+1))
    res=$(awk '
      /^setup\(\)/            { sect = "setup"; next }
      /^@test /               { sect = "test"; local = 0 }
      /^[A-Za-z_][A-Za-z0-9_]*\(\) *\{/ { sect = "func"; local = 0 }
      /^[[:space:]]*export HOME=/ { if (sect == "setup") sethome = 1; else local = 1 }
      /bash[^#]*(\$WRAPPER|-aria\.sh)/ {
        inv++
        if (!sethome && !local) bad++
      }
      END { printf "%d %d", inv + 0, bad + 0 }
    ' "$f")
    inv=${res% *}; bad=${res#* }
    # A suite naming a wrapper yet showing no recognisable invocation would pass vacuously.
    if [ "$inv" -lt 1 ] || [ "$bad" -gt 0 ]; then
      missing="$missing $(basename "$f")(invocations=$inv,unscoped=$bad)"
    fi
  done
  echo "suites checked: $checked; without a scratch HOME before the call:${missing:- none}" >&2
  [ "$checked" -ge 7 ]
  [ -z "$missing" ]
}
