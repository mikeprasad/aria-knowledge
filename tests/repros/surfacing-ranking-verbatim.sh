#!/bin/sh
# surfacing-ranking-verbatim.sh — the knowledge-surfacing ranking is stated in prose in places
# where no code can run. Spec D1: every such copy is the ONE canonical paragraph, copied verbatim
# between a marker pair, and this suite fails on divergence.
#
#   canonical text : plugin-claude-code/scripts/surfacing-ranking.txt (trailing newline ignored)
#   marked copy    : <start marker>TEXT<end marker>, markers spelled as surfacing_marker_start /
#                    surfacing_marker_end build them below; whitespace just inside the markers is
#                    ignored, every other byte must match.
#
# Arms:
#   verbatim_guard               every marked copy in the repo equals the canonical text.
#   census                       the guard examined at least one copy (a zero-file run is a FAIL,
#                                not a pass) and names every file it examined.
#   positive controls            a planted correct copy passes; a planted copy with ONE changed
#                                word fails; a start marker with no end marker fails.
#   digest_ranking_is_canonical  the Claude Code ARIA ACTIVE CONTEXT block carries the marked
#                                paragraph and no other ordering rule.
#
# The markers are built by concatenation so this file is not itself a marked copy.
#
# Census scope: every file under the repo except .git/, docs/, .superpowers/ and CHANGELOG*.
# Those are design records and dated release notes that QUOTE the marker tokens in prose; they are
# not instructions any runtime loads, and back-dating a record is worse than a stale-looking line.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CANON_FILE="$ROOT/plugin-claude-code/scripts/surfacing-ranking.txt"
DIGEST="$ROOT/plugin-claude-code/rules/aria-rules.md"

PASS=0
FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

MS='<!-- surfacing-''ranking:start -->'
ME='<!-- surfacing-''ranking:end -->'

SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/aria-ranking-verbatim.XXXXXX") || exit 1
trap 'rm -rf "$SCRATCH"' EXIT

# --- canonical text --------------------------------------------------------------------------
CANON=""
if [ -s "$CANON_FILE" ]; then
  CANON=$(cat "$CANON_FILE")   # $(...) drops trailing newlines only
fi
if [ -n "$CANON" ]; then
  ok "canonical paragraph file exists and is non-empty"
else
  bad "canonical paragraph file exists and is non-empty" "missing or empty: ${CANON_FILE#$ROOT/}"
fi

# verbatim_guard FILE... — prints one line per file; returns non-zero if ANY file has a marked
# segment that differs from the canonical text, a start marker with no end marker, an end marker
# with no start marker, or no segment at all.
verbatim_guard() {
  _vg_rc=0
  for _vg_f in "$@"; do
    _vg_out=$(MS="$MS" ME="$ME" CANON="$CANON" awk '
      { s = s $0 "\n" }
      END {
        ms = ENVIRON["MS"]; me = ENVIRON["ME"]; canon = ENVIRON["CANON"]
        if (canon == "") { print "bad no canonical text to compare against"; exit 1 }
        n = 0; rest = s
        while ((i = index(rest, ms)) > 0) {
          rest = substr(rest, i + length(ms))
          j = index(rest, me)
          if (j == 0) { print "bad start marker with no end marker"; exit 1 }
          seg = substr(rest, 1, j - 1)
          if (index(seg, ms) > 0) { print "bad start marker with no end marker"; exit 1 }
          rest = substr(rest, j + length(me))
          sub(/^[ \t\r\n]+/, "", seg); sub(/[ \t\r\n]+$/, "", seg)
          n++
          if (seg != canon) { print "bad copy " n " differs from the canonical text"; exit 1 }
        }
        if (index(rest, me) > 0) { print "bad end marker with no start marker"; exit 1 }
        if (n == 0) { print "bad no marked copy in file"; exit 1 }
        print "ok " n " marked cop" (n == 1 ? "y" : "ies") " verbatim"
      }' "$_vg_f" 2>&1)
    _vg_st=$?
    printf '        %s: %s\n' "$_vg_f" "$_vg_out"
    case "$_vg_out" in ok*) [ "$_vg_st" -eq 0 ] || _vg_rc=1 ;; *) _vg_rc=1 ;; esac
  done
  return "$_vg_rc"
}

# --- census + verbatim_guard over the repo ---------------------------------------------------
CENSUS="$SCRATCH/census"
{
  grep -rlIF --exclude-dir=.git --exclude-dir=docs --exclude-dir=.superpowers \
    --exclude='CHANGELOG*' -e "$MS" "$ROOT" 2>/dev/null
  grep -rlIF --exclude-dir=.git --exclude-dir=docs --exclude-dir=.superpowers \
    --exclude='CHANGELOG*' -e "$ME" "$ROOT" 2>/dev/null
} | sort -u > "$CENSUS"
N_COPIES=$(wc -l < "$CENSUS" | tr -d ' ')
printf '        census (%s file(s) carry a marker):\n' "$N_COPIES"
sed "s|^$ROOT/|          |" "$CENSUS"
if [ "$N_COPIES" -ge 1 ]; then
  ok "census: at least one marked copy exists"
else
  bad "census: at least one marked copy exists" "zero files carry the marker pair — the guard would examine nothing"
fi

if [ "$N_COPIES" -ge 1 ]; then
  # shellcheck disable=SC2046
  if verbatim_guard $(cat "$CENSUS"); then
    ok "verbatim_guard: every marked copy equals the canonical text"
  else
    bad "verbatim_guard: every marked copy equals the canonical text" "see the per-file lines above"
  fi
else
  bad "verbatim_guard: every marked copy equals the canonical text" "nothing to examine"
fi

# --- positive controls: the guard must be able to fail, and to pass --------------------------
if [ -n "$CANON" ]; then
  printf 'before %s%s%s after\n' "$MS" "$CANON" "$ME" > "$SCRATCH/good.md"
  if verbatim_guard "$SCRATCH/good.md" >/dev/null; then
    ok "control: a planted correct copy passes the guard"
  else
    bad "control: a planted correct copy passes the guard" "guard rejects a verbatim copy"
  fi

  # One changed word. The substitution must actually change the text, or the control is void.
  CHANGED=$(printf '%s' "$CANON" | sed 's/rarest/commonest/')
  if [ "$CHANGED" = "$CANON" ]; then
    bad "control: a one-word change fails the guard" "substitution changed nothing — control void"
  else
    printf 'before %s%s%s after\n' "$MS" "$CHANGED" "$ME" > "$SCRATCH/drift.md"
    if verbatim_guard "$SCRATCH/drift.md" >/dev/null; then
      bad "control: a one-word change fails the guard" "guard accepted a copy with 'rarest' -> 'commonest'"
    else
      ok "control: a one-word change fails the guard"
    fi
  fi

  printf 'before %s%s after\n' "$MS" "$CANON" > "$SCRATCH/unclosed.md"
  if verbatim_guard "$SCRATCH/unclosed.md" >/dev/null; then
    bad "control: a start marker with no end marker fails the guard" "guard accepted it"
  else
    ok "control: a start marker with no end marker fails the guard"
  fi
else
  bad "controls" "no canonical text — controls cannot run"
fi

# --- digest_ranking_is_canonical -------------------------------------------------------------
BLOCK=$(grep '^ARIA ACTIVE CONTEXT — ' "$DIGEST" 2>/dev/null)
N_BLOCK=$(grep -c '^ARIA ACTIVE CONTEXT — ' "$DIGEST" 2>/dev/null)
if [ "$N_BLOCK" = "1" ]; then
  ok "digest: exactly one ARIA ACTIVE CONTEXT block"
else
  bad "digest: exactly one ARIA ACTIVE CONTEXT block" "found ${N_BLOCK:-0}"
fi

if [ -n "$CANON" ] && printf '%s' "$BLOCK" | grep -qF -e "$MS$CANON$ME"; then
  ok "digest: ARIA ACTIVE CONTEXT carries the marked canonical paragraph"
else
  bad "digest: ARIA ACTIVE CONTEXT carries the marked canonical paragraph" "marked paragraph absent"
fi

# Everything in the block OUTSIDE the marked paragraph. If the paragraph is not there the whole
# block is "outside", which is what the old algorithm text should be judged against.
OUTSIDE=$(printf '%s' "$BLOCK" | MS="$MS" ME="$ME" awk '
  { s = s $0 }
  END {
    ms = ENVIRON["MS"]; me = ENVIRON["ME"]
    i = index(s, ms); j = index(s, me)
    if (i > 0 && j > i) s = substr(s, 1, i - 1) substr(s, j + length(me))
    print s
  }')
for _needle in 'cap at top-5' 'first-appearance' 'top-5' 'dedupe by path'; do
  if printf '%s' "$OUTSIDE" | grep -qiF -e "$_needle"; then
    bad "digest: no ordering rule outside the paragraph ('$_needle')" "found outside the markers"
  else
    ok "digest: no ordering rule outside the paragraph ('$_needle')"
  fi
done
# A numbered procedure outside the paragraph is a second algorithm. The paragraph's own (1)..(6)
# were removed with it above, so any digit-in-parentheses left is someone else's list.
if printf '%s' "$OUTSIDE" | grep -qE '\([0-9]\)'; then
  bad "digest: no numbered procedure outside the paragraph" "found $(printf '%s' "$OUTSIDE" | grep -oE '\([0-9]\)' | tr '\n' ' ')"
else
  ok "digest: no numbered procedure outside the paragraph"
fi

# --- skills (Task 6) ---------------------------------------------------------------------------
# Expected marked copies: 2 rules digests (claude-code, antigravity) + 2 Cowork skills = 4.
# Task 7 raises this when the codex/antigravity/cursor skill copies join.
EXPECTED_COPIES=4
if [ "$N_COPIES" -eq "$EXPECTED_COPIES" ]; then
  ok "census: exactly $EXPECTED_COPIES files carry the marker pair"
else
  bad "census: exactly $EXPECTED_COPIES files carry the marker pair" "found $N_COPIES — a copy vanished or an unexpected one appeared"
fi

# no_first_appearance_order — the retired ordering rule must not survive in any skill.
# (Task 7 extends the scope to every port.)
_fao=$(grep -rlF 'first-appearance order' "$ROOT/plugin-claude-code" "$ROOT/plugin-claude-cowork" --include=SKILL.md 2>/dev/null)
if [ -z "$_fao" ]; then
  ok "no_first_appearance_order: no claude-code/cowork SKILL.md states the retired ordering"
else
  bad "no_first_appearance_order: no claude-code/cowork SKILL.md states the retired ordering" "still in: $(printf '%s' "$_fao" | sed "s|$ROOT/||" | tr '\n' ' ')"
fi

# code_skills_call_cli — Claude Code skills delegate the ranking to the CLI.
for _s in prospect retrospect; do
  if grep -qF '"${CLAUDE_PLUGIN_ROOT}/scripts/aria-surface.sh"' "$ROOT/plugin-claude-code/skills/$_s/SKILL.md"; then
    ok "code_skills_call_cli: claude-code /$_s calls aria-surface.sh"
  else
    bad "code_skills_call_cli: claude-code /$_s calls aria-surface.sh" "CLI invocation absent"
  fi
done

# cowork_carries_paragraph — Cowork cannot run code, so its skills carry the paragraph itself
# (the verbatim_guard above then compares them byte for byte).
for _s in prospect retrospect; do
  if [ -n "$CANON" ] && grep -qF -e "$MS" "$ROOT/plugin-claude-cowork/skills/$_s/SKILL.md" \
     && verbatim_guard "$ROOT/plugin-claude-cowork/skills/$_s/SKILL.md" >/dev/null; then
    ok "cowork_carries_paragraph: cowork /$_s carries the marked canonical paragraph"
  else
    bad "cowork_carries_paragraph: cowork /$_s carries the marked canonical paragraph" "marked paragraph absent or divergent"
  fi
done

# --- fix round 1 -------------------------------------------------------------------------------
SK_CC="$ROOT/plugin-claude-code/skills"; SK_CW="$ROOT/plugin-claude-cowork/skills"

# F5: /retrospect keeps loop closure as a bounded ADDITION (never a re-ranking).
for _f in "$SK_CC/retrospect/SKILL.md" "$SK_CW/retrospect/SKILL.md"; do
  _n=${_f#$ROOT/}
  if grep -qF 'added for loop closure' "$_f"; then ok "loop_closure: $_n carries the loop-closure addition"
  else bad "loop_closure: $_n carries the loop-closure addition" "phrase 'added for loop closure' absent"; fi
  if grep -qiE 'prioriti[sz]e the retro within the top-5|jump the queue' "$_f"; then
    bad "loop_closure: $_n has no re-ranking of the top 5" "old re-ranking / queue-jump wording present"
  else ok "loop_closure: $_n has no re-ranking of the top 5"; fi
  if grep -qF 'at most ONE' "$_f"; then ok "loop_closure: $_n bounds the addition to one retro"
  else bad "loop_closure: $_n bounds the addition to one retro" "'at most ONE' absent"; fi
done

# F1: relative paths vs the ledger, absolute paths for Read — all four skills say so.
for _f in "$SK_CC/prospect/SKILL.md" "$SK_CC/retrospect/SKILL.md" "$SK_CW/prospect/SKILL.md" "$SK_CW/retrospect/SKILL.md"; do
  _n=${_f#$ROOT/}
  if grep -qF 'ledger records paths RELATIVE' "$_f" && grep -qF 'to an absolute path before `Read`' "$_f"; then
    ok "paths: $_n compares relative paths with the ledger and resolves to absolute before Read"
  else bad "paths: $_n compares relative paths with the ledger and resolves to absolute before Read" "relative/absolute statement absent"; fi
done

# F2: no stale 'N substeps' count in the Cowork Step 0.5 (items 2-6 merged).
for _f in "$SK_CW/prospect/SKILL.md" "$SK_CW/retrospect/SKILL.md"; do
  _n=${_f#$ROOT/}
  if grep -qE '10[- ]substeps?' "$_f"; then bad "substeps: $_n has no stale substep count" "still says 10 substeps"
  else ok "substeps: $_n has no stale substep count"; fi
done

# F3 + F4: the Cowork by-hand matcher carries aliases, the project-directory rule and the projects_enabled gate.
for _f in "$SK_CW/prospect/SKILL.md" "$SK_CW/retrospect/SKILL.md"; do
  _n=${_f#$ROOT/}
  _blk=$(awk '/^## Step 0.5/{on=1;next} /^## Step 1/{on=0} on' "$_f")
  for _needle in '[aliases:' 'projects/<tag>/' 'projects_enabled: true'; do
    if printf '%s' "$_blk" | grep -qF -e "$_needle"; then ok "cowork_matcher: $_n Step 0.5 names '$_needle'"
    else bad "cowork_matcher: $_n Step 0.5 names '$_needle'" "absent from Step 0.5"; fi
  done
done

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
