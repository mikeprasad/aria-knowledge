#!/bin/sh
# tests/repros/picker-menu.sh — kt_project_menu rendering (picker feature, spec 2026-06-06)
set -e
DIR="$(cd "$(dirname "$0")/../.." && pwd)"   # repo root
. "$DIR/plugin-claude-code/bin/config.sh"

fail=0
KT_PROJECTS_LIST='alpha:alpha,beta:beta,gamma:gamma'

# Case A: no labels -> bare tags, comma-space joined
KT_PROJECTS_LABELS=''
got=$(kt_project_menu)
[ "$got" = "alpha, beta, gamma" ] || { echo "A FAIL: got [$got]"; fail=1; }

# Case B: partial labels -> "tag (Label)" only where present
KT_PROJECTS_LABELS='alpha:Alpha App,gamma:Gamma Service'
got=$(kt_project_menu)
[ "$got" = "alpha (Alpha App), beta, gamma (Gamma Service)" ] || { echo "B FAIL: got [$got]"; fail=1; }

# Case C: empty list -> empty string
KT_PROJECTS_LIST=''
got=$(kt_project_menu)
[ -z "$got" ] || { echo "C FAIL: got [$got]"; fail=1; }

if [ "$fail" = 0 ]; then echo "picker-menu: PASS"; else echo "picker-menu: FAIL"; exit 1; fi
