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
# Needle: both spellings, any case ("first-appearance", "first appearance", "First Appearance").
# fao_hits prints each file that states it; the two planted controls prove the needle fires on
# each spelling, so a clean result is evidence and not a dead pattern.
fao_hits() { while IFS= read -r _f; do grep -liE 'first[- ]appearance' "$_f" 2>/dev/null; done; }
printf 'Cap at top-5 by First-Appearance order.\n' > "$SCRATCH/fao-hyphen.md"
printf 'Cap at top-5 by first appearance order.\n' > "$SCRATCH/fao-space.md"
for _c in fao-hyphen fao-space; do
  if [ -n "$(printf '%s\n' "$SCRATCH/$_c.md" | fao_hits)" ]; then ok "no_first_appearance_order control: the needle fires on $_c"
  else bad "no_first_appearance_order control: the needle fires on $_c" "a planted copy was not caught"; fi
done
_fao=$(fao_hits < "$_fao_scope")
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

# Per-port directive (2.58.0 fix wave, I2; no-text-transport D5). Each port keeps the canonical
# ranking paragraph byte for byte between its markers; the clauses AROUND it are the port's own.
# Every hooked runtime now ranks in code (Codex prompt hook, Cursor beforeSubmitPrompt+postToolUse,
# Antigravity PreInvocation), so its injection is the only source and each emitter names its hook.
# No port names CLAUDE_CODE_SESSION_ID, which none of them sets.
PD_HEAD="ARIA ACTIVE CONTEXT — Unasked, read each task's knowledge files before answering; say in one line which you used and why. Source: "
PD_TAIL=" Skip files already read this session."
port_directive() { # $1 = port → the exact directive that emitter must send
  case "$1" in
    codex) _pd_src='an `ARIA ACTIVE —` injection from the Codex prompt hook, the only source (none = read nothing); the plugin ranks its files this way: ' ;;
    cursor) _pd_src='an `ARIA ACTIVE —` injection from the Cursor prompt hooks (it arrives after the first tool call of a turn), the only source (none = read nothing); the plugin ranks its files this way: ' ;;
    antigravity) _pd_src='an `ARIA ACTIVE —` injection from the Antigravity PreInvocation hook, the only source (none = read nothing); the plugin ranks its files this way: ' ;;
  esac
  printf '%s%s%s%s%s%s' "$PD_HEAD" "$_pd_src" "$MS" "$CANON" "$ME" "$PD_TAIL"
}
# model_run PATH → what the CLI prints when a model does what the skills now say: write the text to
# a scratch file with its file-write tool, then run `sh '<ARIA SURFACE path>' --file '<scratch>'`.
# The text carries a backtick span, a $() span and a bare ARIA_TASK line followed by a command line,
# each of which creates a marker file if anything runs it.
T7_HOSTILE="$T7_QUERY "'`touch '"$T7/mk1"'` $(touch '"$T7/mk2"')'
printf '%s\nARIA_TASK\ntouch %s\n' "$T7_HOSTILE" "$T7/mk3" > "$T7/task.md"
model_run() {
  rm -f "$T7/mk1" "$T7/mk2" "$T7/mk3"
  printf "sh '%s' --file '%s'\n" "$1" "$T7/task.md" > "$T7/model.sh"
  ( cd "$T7" && TMPDIR="$T7" HOME="$T7/home" KT_ROOT="$T7" KT_CONFIG="$T7/on.md" sh "$T7/model.sh" </dev/null 2>/dev/null )
}
# Reference: the canonical CLI given the same file as an argv element (no shell parses it).
CLI_REF_H=$( cd "$T7" && TMPDIR="$T7" HOME="$T7/home" KT_ROOT="$T7" KT_CONFIG="$T7/on.md" sh "$CLI_CANON" --file "$T7/task.md" </dev/null 2>/dev/null )

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
  if [ -n "$CANON" ] && printf '%s' "$_m" | grep -qF -e "$(port_directive "$_p")"; then
    ok "emitter $_p: emits this port's directive byte for byte (canonical paragraph + port template)"
  else
    bad "emitter $_p: emits this port's directive byte for byte (canonical paragraph + port template)" "directive differs from the $_p template"
  fi
  for _needle in 'CLAUDE_CODE_SESSION_ID' 'in Claude Code the only source'; do
    if printf '%s' "$_m" | grep -qF -e "$_needle"; then bad "emitter $_p: no Claude-Code-only clause ('$_needle')" "still emitted"
    else ok "emitter $_p: no Claude-Code-only clause ('$_needle')"; fi
  done
  printf '%s\n' "$_m" > "$T7/emitted-$_p.txt"
  if verbatim_guard "$T7/emitted-$_p.txt"; then ok "emitter $_p: the marked paragraph extracted from the payload equals the canonical text"
  else bad "emitter $_p: the marked paragraph extracted from the payload equals the canonical text" "see the line above"; fi
  for _needle in 'cap at top-5' 'first-appearance' 'dedupe by path'; do
    if printf '%s' "$_m" | grep -qiF -e "$_needle"; then bad "emitter $_p: no retired ordering text ('$_needle')" "still emitted"
    else ok "emitter $_p: no retired ordering text ('$_needle')"; fi
  done
  # surface_line_path_only (D5): the value line is `ARIA SURFACE — "<abs path>"` and nothing else —
  # no `run:` template, no heredoc, no instruction to put text anywhere.
  _sp=$(printf '%s\n' "$_m" | sed -n 's/^.*ARIA SURFACE — "\([^"]*\)".*$/\1/p' | head -1)
  if [ "$_sp" = "$(port_cli_path "$_p")" ]; then ok "emitter $_p: ARIA SURFACE names this port's own CLI, absolute and quoted"
  else bad "emitter $_p: ARIA SURFACE names this port's own CLI, absolute and quoted" "got '${_sp}'"; fi
  # These emitters join their messages with a space on one line, so after the closing quote comes
  # either the end of the line or the next message, which starts with an UPPERCASE name and ` — `
  # (e.g. `INSIGHT CAPTURE — `). Anything else — ` - <<…`, ` run: …`, prose — is a command template.
  _after=$(printf '%s\n' "$_m" | awk '{ i = index($0, "ARIA SURFACE — \""); if (!i) next
      r = substr($0, i + length("ARIA SURFACE — \"")); j = index(r, "\""); if (!j) { print "UNTERMINATED"; exit }
      print "[" substr(r, j + 1, 60) "]"; exit }')
  if [ -n "$_sp" ] && printf '%s' "$_after" | grep -qE '^\[[[:space:]]*(\]|[A-Z][A-Z0-9 ]* — )'; then
    ok "emitter $_p: surface_line_path_only — the line is the quoted path and nothing else"
  else bad "emitter $_p: surface_line_path_only — the line is the quoted path and nothing else" "after the path: '$(printf '%s' "$_after" | head -c 160)'"; fi
  if printf '%s' "$_m" | grep -qE 'ARIA SURFACE — run:|<<'"'"'?ARIA_TASK'; then
    bad "emitter $_p: no run: template and no heredoc anywhere in the payload" "retired transport still emitted"
  else ok "emitter $_p: no run: template and no heredoc anywhere in the payload"; fi
  if [ -n "$_sp" ] && [ "$(cli_run "$_sp")" = "$CLI_REF" ] && [ -n "$CLI_REF" ]; then ok "emitter $_p: the ARIA SURFACE path runs and ranks the fixture"
  else bad "emitter $_p: the ARIA SURFACE path runs and ranks the fixture" "path did not produce the canonical ranking"; fi
  _mr=$(model_run "$_sp")
  if [ -n "$_sp" ] && [ -n "$CLI_REF_H" ] && [ "$_mr" = "$CLI_REF_H" ]; then ok "emitter $_p: sh '<ARIA SURFACE path>' --file '<scratch>' ranks the file's literal words"
  else bad "emitter $_p: sh '<ARIA SURFACE path>' --file '<scratch>' ranks the file's literal words" "got '$(printf '%s' "$_mr" | head -1)'"; fi
  if [ -e "$T7/mk1" ] || [ -e "$T7/mk2" ] || [ -e "$T7/mk3" ]; then bad "emitter $_p: … and runs nothing in the file's content" "a marker file was created"
  else ok "emitter $_p: … and runs nothing in the file's content"; fi

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

# --- fix round 1 (Task 7) ------------------------------------------------------------------------
# F1: every Step 0.5 copy that RUNS the CLI (a) prefers the absolute path the session-start emitter
# sent on its ARIA SURFACE line — a plugin-root variable is not guaranteed in the model's shell, and
# unset it turns the command into `sh /bin/aria-surface.sh` (exit 127, empty stdout); and (b) says a
# not-found or non-zero run is "unavailable", never "0 matches", which would claim the index was
# searched. Cowork does not run the CLI and is not in this set.
# 2.58.0 fix wave: (A) the CLI path comes from ARIA SURFACE, (D) an `unavailable:` line is handled, and
# (E) no free text goes on the command line at all — the CLI takes references (no-text-transport D1/D2).
F1_A='if an `ARIA SURFACE — "<path>"` line reached you at session start, use that path'
F1_B='`Active surfacing: unavailable (<the reason or error>)`'
F1_C='never `Active surfacing: 0 matches`'
F1_D='If it prints `unavailable: <reason>`'
F1_E='Never put task text'
F1_DEAD='It always exits 0.'
f1_count() { grep -oF -e "$1" "$2" 2>/dev/null | wc -l | tr -d ' '; }
for _spec in \
  "plugin-claude-code/skills/prospect/SKILL.md:1" "plugin-claude-code/skills/retrospect/SKILL.md:1" \
  "plugin-antigravity/skills/prospect/SKILL.md:1" "plugin-antigravity/skills/retrospect/SKILL.md:1" \
  "plugin-openai-codex/skills/prospect/SKILL.md:1" "plugin-openai-codex/skills/retrospect/SKILL.md:1" \
  "plugin-cursor-template/.cursor/rules/aria-commands.mdc:2"; do
  _n=${_spec%:*}; _want=${_spec##*:}; _f="$ROOT/$_n"
  for _p in A B C D E; do
    eval "_needle=\$F1_$_p"
    _got=$(f1_count "$_needle" "$_f")
    if [ "$_got" = "$_want" ]; then ok "F1 $_p: $_n carries it ($_got)"
    else bad "F1 $_p: $_n carries it" "want $_want, got $_got"; fi
  done
  if grep -qF -e "$F1_DEAD" "$_f"; then bad "F1: $_n no longer promises the CLI always exits 0" "'$F1_DEAD' still present"
  else ok "F1: $_n no longer promises the CLI always exits 0"; fi
done
# The codex fallback keeps the in-line ARIA_PLUGIN_ROOT assignment (asserted above); the Claude Code
# and antigravity fallbacks keep their plugin-root form.
for _spec in "plugin-claude-code/skills/prospect/SKILL.md:\${CLAUDE_PLUGIN_ROOT}/scripts/aria-surface.sh" \
             "plugin-antigravity/skills/prospect/SKILL.md:\${CLAUDE_PLUGIN_ROOT}/bin/aria-surface.sh" \
             "plugin-cursor-template/.cursor/rules/aria-commands.mdc:scripts/aria/aria-surface.sh"; do
  _n=${_spec%%:*}; _needle=${_spec#*:}
  if grep -qF -e "otherwise use \`sh \"$_needle\"\` with the same arguments" "$ROOT/$_n"; then ok "F1 fallback: $_n falls back to $_needle"
  else bad "F1 fallback: $_n falls back to $_needle" "fallback form absent"; fi
done

# skills_use_references (D2) — every Step 0.5 copy that runs the CLI passes references: a file
# (`--file '<path>'`) and a commit range (`--git-range '<a>..<b>'`), single-quoted, and tells the model
# to write text-only scopes to a scratch file with its file-write tool, never a shell redirect.
for _spec in \
  "plugin-claude-code/skills/prospect/SKILL.md:1" "plugin-claude-code/skills/retrospect/SKILL.md:1" \
  "plugin-antigravity/skills/prospect/SKILL.md:1" "plugin-antigravity/skills/retrospect/SKILL.md:1" \
  "plugin-openai-codex/skills/prospect/SKILL.md:1" "plugin-openai-codex/skills/retrospect/SKILL.md:1" \
  "plugin-cursor-template/.cursor/rules/aria-commands.mdc:2"; do
  _n=${_spec%:*}; _want=${_spec##*:}; _f="$ROOT/$_n"
  # fix round 1: m1 an unsafe reference (a `'`, backtick or `$` in a path or ref — a cloned remote's
  # refs are third-party text) is never passed; m3 the scratch file is a new one in the scratchpad.
  for _needle in "--file '" "--git-range '" 'file-write tool' 'unsafe reference' 'scratchpad directory'; do
    _got=$(grep -oF -e "$_needle" "$_f" 2>/dev/null | wc -l | tr -d ' ')
    if [ "${_got:-0}" -ge "$_want" ]; then ok "skills_use_references: $_n carries \"$_needle\" ($_got)"
    else bad "skills_use_references: $_n carries \"$_needle\"" "want >= $_want, got ${_got:-0}"; fi
  done
  # m2: the canonical text must not name Claude Code's tool, or the generated ports name the wrong one.
  if grep -qF 'in Claude Code, `Write`' "$_f"; then bad "skills_use_references: $_n names no runtime-specific write tool" "'(in Claude Code, \`Write\`)' present"
  else ok "skills_use_references: $_n names no runtime-specific write tool"; fi
done

# --- preflight_authz_census_reaches_working_tree (fix round 2) -----------------------------------
# /preflight runs BEFORE a commit, when the newest consumer is often untracked. The authz census was
# a working-tree `grep -rn`; round 1 made it a `git grep`, which searches TRACKED files only and so
# missed exactly that consumer. Each preflight copy's git-grep command is RUN in a fixture repo
# (placeholders filled in): an untracked consumer must appear, and a `Tests/` path (capital T — the
# old filter was case-insensitive) and a migration path must not.
PF="$SCRATCH/pf-repo"; mkdir -p "$PF/src" "$PF/Tests" "$PF/lib"
(
  cd "$PF" && git init -q . \
  && printf 'Widget allow\n' > src/a.py && printf 'Widget allow\n' > Tests/t.py \
  && printf 'Widget allow\n' > lib/migration_x.py \
  && git add src/a.py Tests/t.py lib/migration_x.py \
  && git -c user.email=t@example.invalid -c user.name=t commit -qm init \
  && printf 'Widget permission\n' > src/untracked.py
) >/dev/null 2>&1
for _n in plugin-claude-code/skills/preflight/SKILL.md plugin-antigravity/skills/preflight/SKILL.md \
          plugin-openai-codex/skills/preflight/SKILL.md plugin-cursor-template/.cursor/rules/aria-commands.mdc; do
  _cmd=$(awk '/^git grep / { c = $0; if (c ~ /\\$/) { sub(/\\$/, "", c); getline n; c = c n } print c; exit }' "$ROOT/$_n" \
    | sed 's/<SYMBOL>/Widget/g; s/<ext>/py/g')
  if [ -z "$_cmd" ]; then bad "preflight_authz_census: $_n carries a git-grep census command" "none found"; continue; fi
  _out=$( cd "$PF" && sh -c "$_cmd" 2>&1 )
  case "$_out" in *src/a.py*) ok "preflight_authz_census: $_n — control: the tracked consumer appears" ;;
    *) bad "preflight_authz_census: $_n — control: the tracked consumer appears" "got: $(printf '%s' "$_out" | head -c 160)" ;; esac
  case "$_out" in *src/untracked.py*) ok "preflight_authz_census: $_n — an UNTRACKED consumer appears" ;;
    *) bad "preflight_authz_census: $_n — an UNTRACKED consumer appears" "missing (tracked files only?)" ;; esac
  case "$_out" in *Tests/*) bad "preflight_authz_census: $_n — a Tests/ path is excluded (case-insensitive)" "Tests/t.py listed" ;;
    *) ok "preflight_authz_census: $_n — a Tests/ path is excluded (case-insensitive)" ;; esac
  case "$_out" in *migration*) bad "preflight_authz_census: $_n — a migration path is excluded" "listed" ;;
    *) ok "preflight_authz_census: $_n — a migration path is excluded" ;; esac
done

# --- no_text_transport_anywhere (AC1, D6) --------------------------------------------------------
# No instruction a model loads may tell it to compose a shell command carrying free text. The guard
# is a CLASS guard over every tracked instruction surface in every port: all Markdown/.mdc under the
# plugin dirs (skills, rules, workflows, commands, AGENTS/GEMINI/CLAUDE files, templates), the repo's
# own AGENTS.md/CLAUDE.md, and every hook that emits model-facing text. Programmatic callers that exec
# the CLI with an argv list (codex-hook.py, tests) are not instructions: codex-hook.py is scanned for
# its model-facing strings and passes, because a Python argv list matches none of these shapes.
# fix round 1 (I1): the first version was a DENYLIST anchored on the literal `aria-surface.sh`, and
# the skills invoke `sh '<path>' …`, so a reviewer's seven plants all passed it. This is an ALLOWLIST:
#   D  any CLI invocation — `sh`/`bash` followed by a quoted `<…>` placeholder or by a token naming
#      aria-surface.sh — may carry ONLY `--file '…'` and `--git-range '…'` arguments (single-quoted),
#      up to the end of the code span / line or a `;` `&` `|` `)` boundary;
# plus deny rules for free text reaching a shell some other way:
#   A  a heredoc on the retired ARIA_TASK delimiter;
#   B  a quoted `<…>` placeholder on the same command as `>`, `>>`, `<(` or `|`;
#   C  a heredoc together with a redirect (a shell write of text: `cat > f <<'X'`);
#   E  `printf` carrying a quoted `<…>` placeholder (P1: /preflight's marker took free-text scope);
#   F  (Task 5b) any shell command carrying a quoted `<…>` placeholder whose NAME is free text —
#      it contains prompt / focus / next / goal / query / task / scope / rationale / text / body /
#      message / summary / description (case-insensitive) — unless its LAST word is an identifier
#      (sid, sessionid, at, token, path, root, ref, hash, file: `<entry file path>` is a path).
#      This is the shape D cannot see: a helper called by NAME (`kt_ss_ledger_add "<root>" … "<prior
#      next-session-prompt>"`, the session ledger's old demote line) or a script behind a path prefix
#      (`sh <path>/x.sh "<goal>"`). A "shell command" is: in code (a fence line or a backtick span)
#      any command word at the start or after `;` `&` `|` `(` — a span starting `--flag` (a skill
#      argument) or `key:` (a YAML field) is not one; on a bare prose line, only a line that STARTS
#      with sh/bash/zsh/dash/source/./python/echo/printf/cat, a snake_case helper or a *.sh/*.py path.
#      Measured on a82127c: the census finds exactly the four old kt_ss_ledger_add lines; a rule
#      without the command-start condition also flagged `--decision "<text>"` (a /foundational-review
#      argument, 4 ports) and a `dismissal-reason: "<text>"` frontmatter row — neither is a shell command.
# Markdown is checked where a model would copy a command from: whole lines inside a fence, backtick
# spans elsewhere, and whole prose lines that carry no backtick (a leading `>` quote marker and table
# rows are skipped there). Scripts are checked whole-line.
TT_AWK="$SCRATCH/tt-guard.awk"
cat > "$TT_AWK" <<'AWK'
function bad(r) { printf "        %s:%d: [%s] %s\n", F, FNR, r, substr($0, 1, 150); hit = 1 }
# F: does s carry a quoted placeholder whose name is free text? An identifier as the LAST word wins.
function freeph(s,    t, nm, w, n, i, last) {
  t = s
  while (match(t, RE_QPH)) {
    nm = tolower(substr(t, RSTART + 2, RLENGTH - 4))
    t = substr(t, RSTART + RLENGTH)
    n = split(nm, w, /[^a-z0-9]+/); last = ""
    for (i = n; i >= 1; i--) if (w[i] != "") { last = w[i]; break }
    if (last in IDW) continue
    if (nm ~ RE_FREE) return 1
  }
  return 0
}
function check(s, code,    t, t2, hasq, rest, a, ok, cmd) {
  if (s ~ RE_A) bad("A retired ARIA_TASK heredoc")
  cmd = 0                               # no ternary: BSD awk rejects some ternary forms
  if (code) { if (s ~ RE_CODECMD) cmd = 1 } else if (s ~ RE_BARECMD) cmd = 1
  if (cmd && freeph(s)) bad("F free-text placeholder in a shell command")
  # B, C and E judge the SHAPE of a command a model is told to write, so they run on instruction
  # text only. In a hook script the same shapes are the hook's own plumbing (`<<PCC_INPUT …
  # 2>/dev/null`, a Python list of redirect tokens); its model-facing strings are covered by A and D.
  if (MD) {
    t = s
    gsub(RE_QPH, "QPH", t)
    hasq = (t != s)
    gsub(RE_QLIT, "QS", t)              # a | or > INSIDE quotes is data, not a pipe or redirect
    gsub(/<[A-Za-z][^<>]*>/, "PH", t)
    if (hasq && (t ~ />/ || t ~ /<\(/ || t ~ /\|/)) bad("B quoted placeholder with > >> <( or |")
    t2 = t; gsub(/<<<?/, "", t2); gsub(/[0-9&]>+/, "", t2)
    if (t ~ /<</ && t2 ~ />/) bad("C heredoc with a redirect")
    if (hasq && s ~ /(^|[^A-Za-z0-9_])printf[ \t]/) bad("E printf with a quoted placeholder")
  }
  scan_inv(s, RE_INV_SH)    # sh / bash / zsh / dash, with or without a path prefix (/bin/sh)
  scan_inv(s, RE_INV_SRC)   # `. script` / `source script` run the CLI in the current shell
}
# D: after each invocation, the script token must be the CLI (a placeholder, a whole-variable token,
# or a token naming aria-surface.sh) for the allowlist to apply; then only --file '…' / --git-range '…'
# may follow, up to the end of the span or line or a `;` `&` `|` `)` boundary.
function scan_inv(rest, re,    a, ok, nx) {
  while (match(rest, re)) {
    rest = substr(rest, RSTART + RLENGTH)
    if (!match(rest, RE_SCRIPT)) continue
    nx = substr(rest, RLENGTH + 1, 1)
    if (nx != "" && nx !~ /[ \t;&|)`]/) continue   # `<plugin>/scripts/x.sh`: a path PREFIX, not the CLI
    a = substr(rest, RLENGTH + 1); ok = 1
    while (1) {
      sub(/^[ \t]+/, "", a)
      if (a == "" || a ~ /^[`;)|&]/) break
      if (match(a, RE_ARG)) { a = substr(a, RLENGTH + 1); continue }
      ok = 0; break
    }
    if (!ok) bad("D CLI argument other than --file '…' / --git-range '…'")
  }
}
BEGIN {
  q = sprintf("%c", 39)
  RE_A = "<<-?[ \t]*[\"" q "]?ARIA_TASK"
  RE_QPH = "(\"<[^<>\"]*>\"|" q "<[^<>" q "]*>" q ")"
  RE_QLIT = "(\"[^\"]*\"|" q "[^" q "]*" q ")"
  RE_INV_SH = "(^|[^A-Za-z0-9_.-])([^ \t`\"" q "]*/)?(sh|bash|zsh|dash)[ \t]+"
  RE_INV_SRC = "(^|[;&|(` \t])(\\.|source)[ \t]+"
  RE_SCRIPT = "^(\"<[^<>\"]*>\"|" q "<[^<>" q "]*>" q "|<[^<>]+>|\"\\$[A-Za-z_][A-Za-z0-9_]*\"|\"\\$[{][^}\"]*[}]\"|\"[^\"]*aria-surface\\.sh\"|" q "[^" q "]*aria-surface\\.sh" q "|[^ \t`\"" q "]*aria-surface\\.sh)"
  RE_ARG = "^--(file|git-range)[ \t]+" q "[^" q "]*" q
  RE_FREE = "(prompt|focus|next|goal|query|task|scope|rationale|text|body|message|summary|description)"
  RE_CODECMD = "(^|[;&|(])[ \t]*(\\$[ \t]+)?[A-Za-z_./$~{][A-Za-z0-9_./${}~-]*[ \t]"
  RE_BARECMD = "^[ \t]*(\\$[ \t]+)?(sh|bash|zsh|dash|source|\\.|python3?|echo|printf|cat|[A-Za-z][A-Za-z0-9]*_[A-Za-z0-9_]+|[^ \t]*\\.(sh|py))[ \t]"
  split("sid sessionid at token path root ref hash file", _idw, " "); for (_i in _idw) IDW[_idw[_i]] = 1
}
FNR == 1 { fence = 0 }
{
  if (!MD) { check($0, 1); next }
  if ($0 ~ /^[ \t]*(```|~~~)/) { fence = !fence; next }
  if (fence) { if ($0 !~ /^[ \t]*\|/) check($0, 1); next }   # a table row in a fence is a listing
  if (index($0, "`") == 0) {
    line = $0; sub(/^[ \t]*>+[ \t]?/, "", line)
    if (line !~ /^[ \t]*\|/) check(line, 0)
    next
  }
  s = $0
  # Save the span bounds BEFORE check(): its own match() calls overwrite RSTART/RLENGTH.
  while (match(s, /`[^`]+`/)) { st = RSTART; ln = RLENGTH; check(substr(s, st + 1, ln - 2), 1); s = substr(s, st + ln) }
}
END { exit hit }
AWK
TT_EMITTERS="plugin-claude-code/scripts/session-start-check.sh plugin-claude-code/scripts/prompt-context-check.sh
plugin-claude-code/scripts/lib-prompt-surface.sh plugin-openai-codex/bin/session-start-check.sh plugin-openai-codex/bin/codex-hook.py
plugin-cursor-template/scripts/aria/session-start-check.sh plugin-cursor-template/scripts/aria/prompt-capture-check.sh
plugin-cursor-template/scripts/aria/prompt-context-inject.sh plugin-cursor-template/scripts/aria/lib-prompt-surface.sh
plugin-antigravity/bin/antigravity/pre-invocation-aria.sh plugin-antigravity/bin/lib-prompt-surface.sh"
# tt_guard FILE... — prints every matching line as file:line:text; returns 1 if anything matched.
tt_guard() {
  _tt_rc=0
  for _tt_f in "$@"; do
    case "$_tt_f" in *.md|*.mdc) _tt_md=1 ;; *) _tt_md=0 ;; esac
    awk -v F="${_tt_f#$ROOT/}" -v MD="$_tt_md" -f "$TT_AWK" "$_tt_f" || _tt_rc=1
  done
  return "$_tt_rc"
}
TT_SCOPE="$SCRATCH/tt-scope"
{
  git -C "$ROOT" ls-files -- 'plugin-*' 'AGENTS.md' 'CLAUDE.md' 2>/dev/null \
    | grep -E '\.(md|mdc)$' | grep -vE '(^|/)tests?/'
  for _e in $TT_EMITTERS; do printf '%s\n' "$_e"; done
} | sort -u | sed "s|^|$ROOT/|" > "$TT_SCOPE"
_tt_missing=""
while IFS= read -r _f; do [ -f "$_f" ] || _tt_missing="$_tt_missing ${_f#$ROOT/}"; done < "$TT_SCOPE"
N_TT=$(wc -l < "$TT_SCOPE" | tr -d ' ')
printf '        no_text_transport census (%s instruction file(s) scanned):\n' "$N_TT"
sed "s|^$ROOT/|          |" "$TT_SCOPE"
if [ -z "$_tt_missing" ]; then ok "no_text_transport census: every named emitter exists"
else bad "no_text_transport census: every named emitter exists" "missing:$_tt_missing"; fi
for _d in plugin-claude-code plugin-claude-cowork plugin-openai-codex plugin-antigravity plugin-cursor-template; do
  _c=$(grep -c "^$ROOT/$_d/" "$TT_SCOPE")
  if [ "${_c:-0}" -ge 5 ]; then ok "no_text_transport census: $_d contributes $_c file(s)"
  else bad "no_text_transport census: $_d contributes files" "only ${_c:-0} — the guard would be near-vacuous there"; fi
done
# Planted controls. MUST-FAIL: the review's seven plants plus the retired heredoc and the old
# /preflight marker, each planted three ways — inside a ```sh fence, inside a backtick span on a
# prose line, and as a bare prose line — so no wrapping hides one. MUST-PASS: the reference forms
# the skills now use and the skills' own "Never put task text" prose line (it names heredocs and
# pipes in prose and must not trip the guard).
cat > "$SCRATCH/tt-must-fail.txt" <<'PLANTS'
sh '<path>' '<the goal sentence>'
sh '<path>' - <<'EOF2'
printf '%s' '<goal>' | sh '<path>'
sh "<ARIA SURFACE path>" "<your query>"
sh '<path>' --file <(printf '%s' '<goal>')
cat > /tmp/q.md <<'Q'
echo '<goal sentence>' > /tmp/q.md && sh '<path>' --file /tmp/q.md
cat <<'ARIA_TASK'
printf '%s\t%s\t%s\n' "$(date +%H:%M)" "<VERDICT>" "<scope>"
/bin/sh '<path>' '<the goal>'
sh "$ARIA_SURFACE" '<the goal>'
sh <path> "<the goal>"
. '<path>' '<goal>'
kt_ss_ledger_add "{project_root}" "<prior sessionId>" "<prior at>" "<prior currentFocus>" "<prior nextAction>" "<prior next-session-prompt>"
sh <path>/x.sh "<goal>"
PLANTS
cat > "$SCRATCH/tt-must-pass.txt" <<'CLEAN'
sh '<path>' --file '<file path>'
sh '<path>' --git-range '<a>..<b>'
sh '<path>' --file '<file path>' --git-range '<a>..<b>'
sh "${CLAUDE_PLUGIN_ROOT}/scripts/aria-surface.sh" --git-range 'main..HEAD'
ARIA_PLUGIN_ROOT="${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT}}"; sh "${ARIA_PLUGIN_ROOT}/bin/aria-surface.sh" --file '/tmp/a.md'
printf '%s\tREADY\n' "$(date +%H:%M)" >> "${TMPDIR:-/tmp}/aria-preflight-${CLAUDE_SESSION_ID}"
ARIA SURFACE — "/p/aria-surface.sh"
"<task-notification"
kt_ss_ledger_demote_active "{project_root}"
kt_ss_ledger_demote_active "{project_root}" "<your sid>"
kt_ss_ledger_add_file "{project_root}" "<your sid>" "<your at>" '<entry file path>'
--decision "<text>"
dismissal-reason: "<text>"
kt_ss_ledger_add_file "{project_root}" "<your sid>" "<your at>" '<prompt file path>'
CLEAN
tt_wrap() { # $1 = mode (fence|span|bare), $2 = line → a markdown file on stdout
  case "$1" in
    fence) printf 'before\n```sh\n%s\n```\nafter\n' "$2" ;;
    span)  printf 'Run `%s` now.\n' "$2" ;;
    bare)  printf '%s\n' "$2" ;;
  esac
}
_i=0
while IFS= read -r _spec; do
  _i=$((_i + 1))
  for _w in fence span bare; do
    tt_wrap "$_w" "$_spec" > "$SCRATCH/tt-plant-$_i-$_w.md"
    if tt_guard "$SCRATCH/tt-plant-$_i-$_w.md" >/dev/null; then bad "no_text_transport must-FAIL control $_i ($_w): $_spec" "guard passed it"
    else ok "no_text_transport must-FAIL control $_i ($_w)"; fi
  done
done < "$SCRATCH/tt-must-fail.txt"
_i=0
while IFS= read -r _spec; do
  _i=$((_i + 1))
  for _w in fence span bare; do
    tt_wrap "$_w" "$_spec" > "$SCRATCH/tt-clean-$_i-$_w.md"
    if tt_guard "$SCRATCH/tt-clean-$_i-$_w.md" >/dev/null; then ok "no_text_transport must-PASS control $_i ($_w)"
    else bad "no_text_transport must-PASS control $_i ($_w): $_spec" "guard over-matches a legitimate form"; fi
  done
done < "$SCRATCH/tt-must-pass.txt"
# The skills' own prose line, taken from the canonical file so the control tracks its real wording.
_never=$(grep -F 'Never put task text' "$ROOT/plugin-claude-code/skills/prospect/SKILL.md" | head -1)
if [ -n "$_never" ]; then
  printf '%s\n' "$_never" > "$SCRATCH/tt-never.md"
  if tt_guard "$SCRATCH/tt-never.md" >/dev/null; then ok "no_text_transport must-PASS control: the \"Never put task text\" prose line"
  else bad "no_text_transport must-PASS control: the \"Never put task text\" prose line" "guard flags the prohibition itself"; fi
else bad "no_text_transport must-PASS control: the \"Never put task text\" prose line" "line not found in canonical prospect"; fi
# shellcheck disable=SC2046
if tt_guard $(cat "$TT_SCOPE"); then ok "no_text_transport_anywhere: no instruction file composes free text into a shell command ($N_TT files)"
else bad "no_text_transport_anywhere: no instruction file composes free text into a shell command" "see the file:line hits above"; fi

# --- digest_within_bound (AC5) -------------------------------------------------------------------
_db=$(wc -c < "$DIGEST" | tr -d ' ')
if [ "${_db:-99999}" -le 26198 ]; then ok "digest_within_bound: aria-rules.md is $_db bytes (bound 26,198)"
else bad "digest_within_bound: aria-rules.md is within 26,198 bytes" "$_db bytes"; fi
# Branch (b) — "run the ARIA SURFACE command on the task text" — is gone from the canonical digest,
# and the directive names hooks as the source everywhere they run (D5).
if printf '%s' "$BLOCK" | grep -qF 'run the `ARIA SURFACE` command'; then
  bad "digest: branch (b) (run ARIA SURFACE on the task text) is gone" "still present"
else ok "digest: branch (b) (run ARIA SURFACE on the task text) is gone"; fi
if printf '%s' "$BLOCK" | grep -qF 'injection wherever a hook runs'; then ok "digest: the injection is the source wherever a hook runs"
else bad "digest: the injection is the source wherever a hook runs" "phrase absent"; fi

# F2: spec AC1 — every port's lib-index-match.sh and aria-surface.sh is a PORT-LEDGER surface and the
# drift checker reports it. Row must be present AND ok (a missing row is the failure this guards).
_drift=$(sh "$ROOT/plugin-claude-code/scripts/check-port-drift.sh" 2>/dev/null)
for _row in "openai-codex plugin-openai-codex/bin/lib-index-match.sh" "openai-codex plugin-openai-codex/bin/aria-surface.sh" \
            "cursor-template plugin-cursor-template/scripts/aria/lib-index-match.sh" "cursor-template plugin-cursor-template/scripts/aria/aria-surface.sh" \
            "antigravity plugin-antigravity/bin/lib-index-match.sh" "antigravity plugin-antigravity/bin/aria-surface.sh"; do
  _port=${_row%% *}; _path=${_row#* }
  _st=$(printf '%s\n' "$_drift" | awk -v p="$_port" -v s="$_path" '$1 == p && $2 == s { print $3 }')
  if [ "$_st" = "ok" ]; then ok "F2 ledger: $_port tracks $_path (ok)"
  else bad "F2 ledger: $_port tracks $_path (ok)" "status '${_st:-absent}'"; fi
done

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
