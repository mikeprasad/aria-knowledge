#!/bin/sh
# tracker-agnostic.sh — no shipped skill may treat one ticket vendor as THE tracker.
#
# This plugin is public. A user on Jira, Asana, Monday, ClickUp, Notion or GitHub
# Issues must not read instructions written as though one vendor were the only
# option, and must not be told a capability "needs <Vendor> MCP" when what it
# actually needs is whichever tracker they have connected.
#
# The rule distinguishes LOCK from MENTION:
#   lock    — "Linear MCP", "a Linear ID", "Linear comment", "<vendor> ticket IDs"
#             i.e. the vendor standing in for the category. NOT ALLOWED.
#   mention — the vendor named inside a list of sibling trackers, which is what
#             /digest does and what helps the runtime probe. ALLOWED.
#
# Backward compatibility is preserved separately: the historical `linear` scope
# and `--linear-post` flag remain accepted aliases. Asserted below, because
# silently dropping a documented CLI contract would be its own defect.
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SKILLS="$REPO_ROOT/plugin-claude-code/skills"
PASS=0; FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

# A — no vendor-as-the-category phrasing in any shipped skill.
for s in auto prospect retrospect; do
  F="$SKILLS/$s/SKILL.md"
  HITS=$(grep -oiE 'linear (mcp|id|comment|ticket)|a linear|linear-style' "$F" 2>/dev/null | sort -u | tr '\n' ' ')
  if [ -n "$HITS" ]; then
    bad "A vendor-as-category in /$s" "found: $HITS"
  else
    ok "A no vendor-as-category: /$s"
  fi
done

# B — where a vendor IS named, siblings must be named beside it.
for s in auto prospect retrospect; do
  F="$SKILLS/$s/SKILL.md"
  if grep -qi 'linear' "$F"; then
    grep -qiE 'linear.*(asana|jira|atlassian|monday|clickup|notion|github)|( asana|jira|atlassian|monday|clickup|notion|github).*linear' "$F" \
      && ok "B vendor named among siblings: /$s" \
      || bad "B lone vendor in /$s" "named without sibling trackers beside it"
  else
    ok "B no vendor named at all: /$s"
  fi
done

# C — the generic vocabulary is actually present (not just the vendor removed).
for s in prospect retrospect; do
  F="$SKILLS/$s/SKILL.md"
  grep -qiE 'tracker' "$F" && ok "C generic 'tracker' vocabulary: /$s" \
                           || bad "C no generic term in /$s" "vendor removed but nothing replaced it"
done

# D — BACKWARD COMPATIBILITY. The historical invocations are documented CLI
# contract and must keep working. Dropping them silently would be a defect, not
# a cleanup.
grep -q 'linear-post' "$SKILLS/prospect/SKILL.md" \
  && ok "D --linear-post still honoured in /prospect" || bad "D compat" "--linear-post alias dropped"
grep -q 'linear-post' "$SKILLS/retrospect/SKILL.md" \
  && ok "D --linear-post still honoured in /retrospect" || bad "D compat" "--linear-post alias dropped"
grep -qiE '`linear`|/prospect linear' "$SKILLS/prospect/SKILL.md" \
  && ok "D legacy 'linear' scope still accepted" || bad "D compat" "legacy linear scope dropped"

# E — Gate B: neither description may grow past its current size. Caps are the
# MEASURED sizes at the time of this change, not estimates -- a cap set well
# above the real value is a guard that cannot fail.
for pair in "prospect:680" "retrospect:678"; do
  s=${pair%%:*}; cap=${pair##*:}
  n=$(awk '/^description:/{f=1;print;next} f&&/^[a-z_-]+:/{f=0} f' "$SKILLS/$s/SKILL.md" | wc -c | tr -d ' ')
  [ "$n" -le "$cap" ] && ok "E /$s description within budget ($n <= $cap)" \
                      || bad "E /$s budget" "grew to $n (cap $cap)"
done

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
