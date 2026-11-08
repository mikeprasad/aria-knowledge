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

# --- skills (Task 6) + ports (Task 7) ----------------------------------------------------------
# Expected marked copies (7):
#   plugin-claude-code/rules/aria-rules.md                    (the canonical directive)
#   plugin-antigravity/rules/aria-rules.md                    (regenerated from it by build.sh)
#   plugin-claude-cowork/skills/{prospect,retrospect}/SKILL.md (Cowork has no shell: it carries the paragraph)
#   plugin-openai-codex/bin/session-start-check.sh            (hand-maintained directive copy)
#   plugin-cursor-template/scripts/aria/session-start-check.sh (hand-maintained directive copy)
#   plugin-antigravity/bin/antigravity/pre-invocation-aria.sh (hand-maintained directive copy)
# Code-port skills (claude-code, codex, antigravity, cursor .mdc) call aria-surface.sh instead.
EXPECTED_COPIES=7
if [ "$N_COPIES" -eq "$EXPECTED_COPIES" ]; then
  ok "census: exactly $EXPECTED_COPIES files carry the marker pair"
else
  bad "census: exactly $EXPECTED_COPIES files carry the marker pair" "found $N_COPIES — a copy vanished or an unexpected one appeared"
fi

# no_first_appearance_order — the retired ordering rule must not survive in any port's skill text.
# Scope: every SKILL.md in the four skill-carrying plugin dirs, plus the compiled Cursor .mdc rules.
# The scope is counted and must be non-empty per source, or the absence would be vacuous.
_fao_scope="$SCRATCH/fao-scope"
: > "$_fao_scope"
for _d in plugin-claude-code plugin-claude-cowork plugin-openai-codex plugin-antigravity; do
  _n=$(find "$ROOT/$_d/skills" -name SKILL.md 2>/dev/null | tee -a "$_fao_scope" | wc -l | tr -d ' ')
  if [ "${_n:-0}" -ge 1 ]; then ok "no_first_appearance_order scope: $_d has $_n SKILL.md file(s)"
  else bad "no_first_appearance_order scope: $_d has SKILL.md files" "found none — the check below would be vacuous for $_d"; fi
done
_n=$(find "$ROOT/plugin-cursor-template/.cursor/rules" -name '*.mdc' 2>/dev/null | tee -a "$_fao_scope" | wc -l | tr -d ' ')
if [ "${_n:-0}" -ge 1 ]; then ok "no_first_appearance_order scope: cursor has $_n .mdc file(s)"
else bad "no_first_appearance_order scope: cursor has .mdc files" "found none — the check below would be vacuous for cursor"; fi
_fao=$(while IFS= read -r _f; do grep -lF 'first-appearance order' "$_f" 2>/dev/null; done < "$_fao_scope")
if [ -z "$_fao" ]; then
  ok "no_first_appearance_order: no port's skill text states the retired ordering ($(wc -l < "$_fao_scope" | tr -d ' ') files)"
else
  bad "no_first_appearance_order: no port's skill text states the retired ordering" "still in: $(printf '%s' "$_fao" | sed "s|$ROOT/||" | tr '\n' ' ')"
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

# --- ports (Task 7) ------------------------------------------------------------------------------
# Every shell port carries the SAME matcher and the SAME CLI, and each hand-maintained session-start
# emitter sends the canonical ARIA ACTIVE CONTEXT directive plus an ARIA SURFACE line naming its own
# CLI. Each emitter is RUN against a fixture: a directive that is present in the source but mangled
# on the way out (a backtick inside a double-quoted shell string is command substitution and deletes
# text silently) only shows in the emitted payload.
LIB_CANON="$ROOT/plugin-claude-code/scripts/lib-index-match.sh"
CLI_CANON="$ROOT/plugin-claude-code/scripts/aria-surface.sh"
PORT_LIBS="$LIB_CANON $ROOT/plugin-antigravity/bin/lib-index-match.sh $ROOT/plugin-openai-codex/bin/lib-index-match.sh $ROOT/plugin-cursor-template/scripts/aria/lib-index-match.sh"
PORT_CLIS="$CLI_CANON $ROOT/plugin-antigravity/bin/aria-surface.sh $ROOT/plugin-openai-codex/bin/aria-surface.sh $ROOT/plugin-cursor-template/scripts/aria/aria-surface.sh"

# four_libs_identical — cksum of the four lib copies.
_ref=$(cksum < "$LIB_CANON" 2>/dev/null)
_diffs=""
for _f in $PORT_LIBS; do
  _c=$(cksum < "$_f" 2>/dev/null)
  printf '        %s  %s\n' "${_c:-MISSING}" "${_f#$ROOT/}"
  [ -n "$_c" ] && [ "$_c" = "$_ref" ] || _diffs="$_diffs ${_f#$ROOT/}"
done
if [ -n "$_ref" ] && [ -z "$_diffs" ]; then ok "four_libs_identical: the 4 lib-index-match.sh copies are byte-identical"
else bad "four_libs_identical: the 4 lib-index-match.sh copies are byte-identical" "differ or missing:$_diffs"; fi

# Fixture: the surfacing-rank index, a config that turns surfacing on, and a query that fires.
T7="$SCRATCH/t7"; mkdir -p "$T7/kf/logs" "$T7/home" "$T7/home/.gemini/antigravity"
cp "$ROOT/tests/repros/fixtures/surfacing/index.md" "$T7/kf/index.md"
# Today-dated audit logs: without them a first-run emitter sends only the welcome banner and exits.
printf -- '- **Date:** %s\n' "$(date +%Y-%m-%d)" > "$T7/kf/logs/knowledge-audit-log.md"
printf -- '- **Date:** %s\n' "$(date +%Y-%m-%d)" > "$T7/kf/logs/config-audit-log.md"
mk_t7_cfg() { # $1 = path, $2 = active_knowledge_surfacing value
  printf -- '---\nknowledge_folder: %s\nactive_knowledge_surfacing: %s\nprojects_enabled: true\nprojects_list: proj-a:proj-a,proj-b:proj-b,proj-c:proj-c\n---\n' "$T7/kf" "$2" > "$1"
}
mk_t7_cfg "$T7/on.md" true
mk_t7_cfg "$T7/off.md" false
T7_QUERY="fix the proj-b payments webhook"
cli_run() { ( cd "$T7" && TMPDIR="$T7" HOME="$T7/home" KT_ROOT="$T7" KT_CONFIG="$T7/on.md" sh "$1" "$T7_QUERY" </dev/null 2>/dev/null ) ; }

CLI_REF=$(cli_run "$CLI_CANON")
case "$CLI_REF" in
  "tags: "*) ok "port CLI control: the canonical CLI ranks the fixture ($(printf '%s\n' "$CLI_REF" | sed 1d | wc -l | tr -d ' ') paths)" ;;
  *) bad "port CLI control: the canonical CLI ranks the fixture" "got: $(printf '%s' "$CLI_REF" | head -c 120)" ;;
esac
for _f in $PORT_CLIS; do
  _n=${_f#$ROOT/}
  [ "$_f" = "$CLI_CANON" ] && continue
  if [ -f "$_f" ] && cmp -s "$_f" "$CLI_CANON"; then ok "port_cli: $_n is byte-identical to the canonical CLI"
  else bad "port_cli: $_n is byte-identical to the canonical CLI" "missing or differs"; fi
  _out=$(cli_run "$_f")
  if [ -n "$CLI_REF" ] && [ "$_out" = "$CLI_REF" ]; then ok "port_cli: $_n run in its own layout prints the canonical ranking"
  else bad "port_cli: $_n run in its own layout prints the canonical ranking" "got: $(printf '%s' "$_out" | head -c 120)"; fi
done

# Canonical directive line with the knowledge folder substituted — the exact text every emitter must send.
CANON_LINE=$(grep '^ARIA ACTIVE CONTEXT — ' "$DIGEST" 2>/dev/null | head -1)
EXPECT_LINE=$(printf '%s' "$CANON_LINE" | KF="$T7/kf" awk '{ i = index($0, "{knowledge_folder}"); if (i) $0 = substr($0, 1, i - 1) ENVIRON["KF"] substr($0, i + 18); print }')
if [ -n "$CANON_LINE" ] && [ "$EXPECT_LINE" != "$CANON_LINE" ]; then ok "emitter control: the canonical directive names {knowledge_folder} once and substitutes"
else bad "emitter control: the canonical directive names {knowledge_folder} once and substitutes" "substitution changed nothing"; fi

emit_port() { # $1 = port, $2 = cfg → decoded model text on stdout
  case "$1" in
    codex)
      printf '{"session_id":"t7"}' | ( cd "$T7" && HOME="$T7/home" KT_CONFIG="$2" sh "$ROOT/plugin-openai-codex/bin/session-start-check.sh" 2>/dev/null ) \
        | jq -r '.systemMessage // ""' 2>/dev/null ;;
    cursor)
      printf '{"sessionId":"t7"}' | ( cd "$T7" && HOME="$T7/home" KT_ROOT="$T7" KT_CONFIG="$2" sh "$ROOT/plugin-cursor-template/scripts/aria/session-start-check.sh" 2>/dev/null ) \
        | jq -r '.agentMessage // ""' 2>/dev/null ;;
    antigravity)
      printf '{"conversationId":"t7","workspacePaths":["%s"],"transcriptPath":"","artifactDirectoryPath":"","invocationNum":0,"initialNumSteps":0}' "$T7" \
        | ( cd "$T7" && HOME="$T7/home" KT_CONFIG="$2" bash "$ROOT/plugin-antigravity/bin/antigravity/pre-invocation-aria.sh" 2>/dev/null ) \
        | jq -r '[.injectSteps[]?.ephemeralMessage] | join("\n")' 2>/dev/null ;;
  esac
}
port_cli_path() {
  case "$1" in
    codex) printf '%s' "$ROOT/plugin-openai-codex/bin/aria-surface.sh" ;;
    cursor) printf '%s' "$ROOT/plugin-cursor-template/scripts/aria/aria-surface.sh" ;;
    antigravity) printf '%s' "$ROOT/plugin-antigravity/bin/aria-surface.sh" ;;
  esac
}
for _p in codex cursor antigravity; do
  _m=$(emit_port "$_p" "$T7/on.md")
  if [ -z "$_m" ]; then bad "emitter $_p: produced a model message" "empty — every absence below would pass vacuously"; continue; fi
  ok "emitter $_p: produced a model message (${#_m} chars)"
  _nb=$(printf '%s' "$_m" | grep -oF 'ARIA ACTIVE CONTEXT — ' | wc -l | tr -d ' ')
  if [ "$_nb" = "1" ]; then ok "emitter $_p: exactly one ARIA ACTIVE CONTEXT directive"
  else bad "emitter $_p: exactly one ARIA ACTIVE CONTEXT directive" "found $_nb"; fi
  if [ -n "$CANON_LINE" ] && printf '%s' "$_m" | grep -qF -e "$EXPECT_LINE"; then
    ok "emitter $_p: emits the canonical directive byte for byte (knowledge folder substituted)"
  else
    bad "emitter $_p: emits the canonical directive byte for byte (knowledge folder substituted)" "directive differs from plugin-claude-code/rules/aria-rules.md"
  fi
  printf '%s\n' "$_m" > "$T7/emitted-$_p.txt"
  if verbatim_guard "$T7/emitted-$_p.txt"; then ok "emitter $_p: the marked paragraph extracted from the payload equals the canonical text"
  else bad "emitter $_p: the marked paragraph extracted from the payload equals the canonical text" "see the line above"; fi
  for _needle in 'cap at top-5' 'first-appearance' 'dedupe by path'; do
    if printf '%s' "$_m" | grep -qiF -e "$_needle"; then bad "emitter $_p: no retired ordering text ('$_needle')" "still emitted"
    else ok "emitter $_p: no retired ordering text ('$_needle')"; fi
  done
  _sp=$(printf '%s' "$_m" | grep -o 'ARIA SURFACE — "[^"]*"' | head -1 | sed 's/^ARIA SURFACE — "//; s/"$//')
  if [ "$_sp" = "$(port_cli_path "$_p")" ]; then ok "emitter $_p: ARIA SURFACE names this port's own CLI, absolute and quoted"
  else bad "emitter $_p: ARIA SURFACE names this port's own CLI, absolute and quoted" "got '${_sp}'"; fi
  if [ -n "$_sp" ] && [ "$(cli_run "$_sp")" = "$CLI_REF" ] && [ -n "$CLI_REF" ]; then ok "emitter $_p: the ARIA SURFACE path runs and ranks the fixture"
  else bad "emitter $_p: the ARIA SURFACE path runs and ranks the fixture" "path did not produce the canonical ranking"; fi

  _m0=$(emit_port "$_p" "$T7/off.md")
  if printf '%s' "$_m0" | grep -qF 'ARIA CONTEXT — '; then
    ok "emitter $_p control: surfacing off still emits the passive ARIA CONTEXT line"
    if printf '%s' "$_m0" | grep -qF 'ARIA SURFACE'; then bad "emitter $_p: surfacing off → no ARIA SURFACE line" "still emitted"
    else ok "emitter $_p: surfacing off → no ARIA SURFACE line"; fi
  else
    bad "emitter $_p control: surfacing off still emits the passive ARIA CONTEXT line" "absent — the off-arm absence is unproven"
  fi
  mv "$T7/kf/index.md" "$T7/kf/index.md.away"
  _mn=$(emit_port "$_p" "$T7/on.md")
  mv "$T7/kf/index.md.away" "$T7/kf/index.md"
  if [ -n "$_mn" ]; then
    if printf '%s' "$_mn" | grep -qF 'ARIA SURFACE'; then bad "emitter $_p: no index.md → no ARIA SURFACE line" "still emitted"
    else ok "emitter $_p: no index.md → no ARIA SURFACE line"; fi
  else
    bad "emitter $_p: no index.md → no ARIA SURFACE line" "emitter sent nothing — absence unproven"
  fi
done

# codex_skills_call_cli — Codex skills delegate the ranking to their own CLI. ARIA_PLUGIN_ROOT is not
# set in a Codex skill's environment (only /setup's own snippet assigns it), so the command must
# assign it in the same line, from the port's established ${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}.
for _s in prospect retrospect; do
  _f="$ROOT/plugin-openai-codex/skills/$_s/SKILL.md"
  if grep -qF 'ARIA_PLUGIN_ROOT="${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}"; sh "${ARIA_PLUGIN_ROOT}/bin/aria-surface.sh"' "$_f"; then
    ok "codex_skills_call_cli: codex /$_s assigns ARIA_PLUGIN_ROOT and calls bin/aria-surface.sh"
  else
    bad "codex_skills_call_cli: codex /$_s assigns ARIA_PLUGIN_ROOT and calls bin/aria-surface.sh" "CLI invocation absent"
  fi
done
for _f in "$ROOT/plugin-openai-codex/skills/retrospect/SKILL.md"; do
  if grep -qF 'added for loop closure' "$_f" && grep -qF 'at most ONE' "$_f"; then ok "loop_closure: codex /retrospect carries the bounded loop-closure addition"
  else bad "loop_closure: codex /retrospect carries the bounded loop-closure addition" "absent"; fi
done
for _s in prospect retrospect; do
  _f="$ROOT/plugin-openai-codex/skills/$_s/SKILL.md"
  if grep -qF 'ledger records paths RELATIVE' "$_f" && grep -qF 'to an absolute path before `Read`' "$_f"; then
    ok "paths: codex /$_s compares relative paths with the ledger and resolves to absolute before Read"
  else bad "paths: codex /$_s compares relative paths with the ledger and resolves to absolute before Read" "absent"; fi
done

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
