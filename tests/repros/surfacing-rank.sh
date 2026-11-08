#!/bin/sh
# surfacing-rank.sh — tests for kt_index_match in scripts/lib-index-match.sh:
# the D2 project-first ranking, the D3 project vocabulary taken from
# projects_list, and D4 aliases from `## Known Tags`.
#
# Run under sh or bash only. Under zsh word-splitting differs and the lib
# reads 0 matches for queries that do match.
#
# Every arm states its expected ranked paths. Each arm was seen RED against
# the pre-2.58.0 lib before the lib change, EXCEPT the arms labelled GUARD:
# those pass on the old lib by design and exist to stop a regression, so they
# are not evidence that the change landed.
#
# SURFACING_LIB overrides the lib path (used for mutation checks).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="${SURFACING_LIB:-$REPO_ROOT/plugin-claude-code/scripts/lib-index-match.sh}"
FIX="$SCRIPT_DIR/fixtures/surfacing"

PASS=0
FAIL=0
ok()  { printf "PASS  %s\n" "$1"; PASS=$((PASS + 1)); }
bad() { printf "FAIL  %s — %s\n" "$1" "$2"; FAIL=$((FAIL + 1)); }

SCRATCH=$(mktemp -d "${TMPDIR:-/tmp}/aria-surfacing-test.XXXXXX") || exit 1
trap 'rm -rf "$SCRATCH"' EXIT
mkdir -p "$SCRATCH/tmp" "$SCRATCH/home"
TMPDIR="$SCRATCH/tmp"; export TMPDIR
HOME="$SCRATCH/home"; export HOME
KT_KNOWLEDGE_FOLDER="$FIX"; export KT_KNOWLEDGE_FOLDER

# projects_list comes from the fixture config, extracted the way config.sh does
# it, and is pinned to the literal the arms below were designed against.
KT_PROJECTS_LIST=$(sed -n '/^---$/,/^---$/p' "$FIX/config.md" | grep '^projects_list:' | sed 's/^projects_list: *//')
export KT_PROJECTS_LIST
if [ "$KT_PROJECTS_LIST" != "proj-a:proj-a,proj-b:proj-b,proj-c:proj-c" ]; then
  echo "fixture config.md projects_list is '$KT_PROJECTS_LIST' — arms assume proj-a,proj-b,proj-c"; exit 1
fi

# shellcheck disable=SC1090
. "$LIB"

# Ranked paths of the last match, space-joined (empty when nothing fired).
ranked() {
  if [ -n "$KT_MATCH_FILES_TMP" ] && [ -f "$KT_MATCH_FILES_TMP" ]; then
    awk -F ' — ' '{print $1}' "$KT_MATCH_FILES_TMP" | tr '\n' ' ' | sed 's/ $//'
  fi
}

S=projects/proj-b/deposits.md
L1=logs/retrospect/2026-10-01-proj-b-crew-review.md
L2=logs/retrospect/2026-10-02-proj-b-invoice-review.md
A1=projects/proj-b/crew-notes.md
A2=projects/proj-b/estimates.md
MAINQ="add the roof job to the proj-b payments tab"

# Expected for MAINQ: S carries 2 matched tags (rank 1); the other four proj-b
# files outrank every proj-c file on key 1, even billing-1 whose description
# overlaps the task words most; L2 beats the rest on task words (key 3); A1/A2
# beat L1 on authored-before-logs (key 4); A1 before A2 by index order.
MAIN_EXPECT="$S $L2 $A1 $A2 $L1"

kt_index_match "$MAINQ"
MAIN_GOT=$(ranked)
MAIN_COUNT=$KT_MATCH_COUNT
MAIN_TAGS=$KT_MATCH_TAGS
kt_match_cleanup

# --- project_first_over_longer_tag ---
first2=$(printf '%s' "$MAIN_GOT" | cut -d' ' -f1-2)
[ "$first2" = "$S $L2" ] && ok "project_first_over_longer_tag" \
  || bad "project_first_over_longer_tag" "first two '$first2', want '$S $L2' (full: '$MAIN_GOT')"

# --- full ranked list for MAINQ (pins every key at once) ---
[ "$MAIN_GOT" = "$MAIN_EXPECT" ] && ok "main_query_full_order" \
  || bad "main_query_full_order" "got '$MAIN_GOT' want '$MAIN_EXPECT'"

# --- two_matched_tags_outrank_one ---
first1=$(printf '%s' "$MAIN_GOT" | cut -d' ' -f1)
[ "$first1" = "$S" ] && ok "two_matched_tags_outrank_one" \
  || bad "two_matched_tags_outrank_one" "rank 1 '$first1', want '$S'"

# position of a path in MAIN_GOT (0 when absent)
pos() { printf '%s\n' $MAIN_GOT | awk -v p="$1" '$0==p{print NR; f=1; exit} END{if(!f)print 0}'; }

# --- task_words_break_tie --- (L1 is listed first in the index, so index order alone fails)
pL1=$(pos "$L1"); pL2=$(pos "$L2")
if [ "$pL2" -gt 0 ] && [ "$pL1" -gt 0 ] && [ "$pL2" -lt "$pL1" ]; then ok "task_words_break_tie"
else bad "task_words_break_tie" "L2 at $pL2, L1 at $pL1 (want both present, L2 first)"; fi

# --- authored_before_logs --- (L1 is listed before A1/A2 in the index)
pA1=$(pos "$A1"); pA2=$(pos "$A2")
if [ "$pA1" -gt 0 ] && [ "$pA2" -gt 0 ] && [ "$pL1" -gt 0 ] && [ "$pA1" -lt "$pL1" ] && [ "$pA2" -lt "$pL1" ]; then
  ok "authored_before_logs"
else bad "authored_before_logs" "A1 $pA1, A2 $pA2, L1 $pL1 (want A1,A2 before L1)"; fi

# --- rarest_tag_breaks_tie --- two generic tags, no project. billing-1 wins on
# task words (its description says "payments"); every other candidate ties on
# keys 1-4, so the webhooks files (2 in that section) beat the payments files
# (7) even though every payments line precedes them in index order.
kt_index_match "check webhooks and payments"
got=$(ranked)
want="projects/proj-c/billing-1.md projects/proj-a/hooks.md references/webhook-basics.md projects/proj-c/billing-2.md projects/proj-c/billing-3.md"
[ "$got" = "$want" ] && ok "rarest_tag_breaks_tie" || bad "rarest_tag_breaks_tie" "got '$got' want '$want'"
kt_match_cleanup

# --- lone_project_tag_fires ---
kt_index_match "look at proj-b"
got=$(ranked); want="$S $A1 $A2 $L1 $L2"
if [ "$KT_MATCH_COUNT" -gt 0 ] && [ "$KT_MATCH_TAGS" = "proj-b" ] && [ "$got" = "$want" ]; then ok "lone_project_tag_fires"
else bad "lone_project_tag_fires" "count $KT_MATCH_COUNT tags '$KT_MATCH_TAGS' got '$got' want '$want'"; fi
kt_match_cleanup

# --- lone_generic_tag_silent --- GUARD (negative arm): green on the old lib too,
# which needed >=2 tags. Its red-on-old partner is lone_project_tag_fires.
kt_index_match "look at payments"
if [ "$KT_MATCH_COUNT" -eq 0 ] && [ -z "$KT_MATCH_FILES_TMP" ]; then ok "lone_generic_tag_silent (GUARD)"
else bad "lone_generic_tag_silent (GUARD)" "count $KT_MATCH_COUNT got '$(ranked)'"; fi
kt_match_cleanup

# --- project_without_tag_section --- proj-a has no `### proj-a`; its only
# Tag Index line sits under `### webhooks`. The `## Stale Files` line for
# projects/proj-a/ must NOT surface (not a file-listing section).
kt_index_match "work on proj-a"
got=$(ranked); want="projects/proj-a/hooks.md"
if [ "$KT_MATCH_TAGS" = "proj-a" ] && [ "$got" = "$want" ]; then ok "project_without_tag_section"
else bad "project_without_tag_section" "tags '$KT_MATCH_TAGS' got '$got' want '$want'"; fi
kt_match_cleanup

# --- alias_comma_and_space --- comma-separated list (site-1, site-2) and a
# whitespace-separated list (threejs three.js) both resolve to the canonical tag.
kt_index_match "site-1 skylights"
a_tags=$KT_MATCH_TAGS; a_got=$(ranked); kt_match_cleanup
kt_index_match "site-2 skylights"
b_tags=$KT_MATCH_TAGS; kt_match_cleanup
kt_index_match "threejs scene for webhooks"
c_tags=$KT_MATCH_TAGS; c_got=$(ranked); kt_match_cleanup
c_want="references/three-js-scenes.md projects/proj-a/hooks.md references/webhook-basics.md"
if [ "$a_tags" = "proj-b" ] && [ "$b_tags" = "proj-b" ] && [ "$a_got" = "$S $A1 $A2 $L1 $L2" ] \
   && [ "$c_tags" = "three-js webhooks" ] && [ "$c_got" = "$c_want" ]; then ok "alias_comma_and_space"
else bad "alias_comma_and_space" "site-1 tags '$a_tags' got '$a_got'; site-2 tags '$b_tags'; threejs tags '$c_tags' got '$c_got'"; fi

# --- cd_query_lone_project_fires --- bash-cd-check.sh builds "$PARENT $LAST"
# from the cd target's last two path components (intended change, G2-6).
CD_PATH="/home/someone/work/proj-b"
cdq="$(basename "$(dirname "$CD_PATH")") $(basename "$CD_PATH")"
kt_index_match "$cdq"
got=$(ranked)
if [ "$KT_MATCH_COUNT" -gt 0 ] && [ "$KT_MATCH_TAGS" = "proj-b" ] && [ "$(printf '%s' "$got" | cut -d' ' -f1)" = "$S" ]; then
  ok "cd_query_lone_project_fires ('$cdq')"
else bad "cd_query_lone_project_fires" "query '$cdq' count $KT_MATCH_COUNT tags '$KT_MATCH_TAGS' got '$got'"; fi
kt_match_cleanup

# --- no_projects_list_no_project_tags --- GUARD: with projects_list empty,
# proj-b is an ordinary Tag Index tag and a lone mention stays silent.
_saved=$KT_PROJECTS_LIST; KT_PROJECTS_LIST=""
kt_index_match "look at proj-b"
[ "$KT_MATCH_COUNT" -eq 0 ] && ok "no_projects_list_no_project_tags (GUARD)" \
  || bad "no_projects_list_no_project_tags (GUARD)" "count $KT_MATCH_COUNT"
kt_match_cleanup
KT_PROJECTS_LIST=$_saved

# --- task_word_tokens --- kt_index_tokens: lowercase, split on non-alnum,
# drop length <=2 and the stopword list, one per line, first-seen order.
got=$( (kt_index_tokens "Add the ROOF job to the proj-b payments tab, with a fix from this new update" ) 2>/dev/null | tr '\n' ' ' | sed 's/ $//')
[ "$got" = "roof job proj payments tab" ] && ok "task_word_tokens" \
  || bad "task_word_tokens" "got '$got' want 'roof job proj payments tab'"

# --- cap_is_five --- GUARD on the cap (old lib capped at 5 too).
[ "$MAIN_COUNT" -eq 5 ] && ok "cap_is_five (GUARD)" || bad "cap_is_five (GUARD)" "count $MAIN_COUNT"

# --- existing_callers_contract --- GUARD: line shape, tags, cleanup, no-match reset.
kt_index_match "$MAINQ"
shape_bad=0
if [ -n "$KT_MATCH_FILES_TMP" ] && [ -f "$KT_MATCH_FILES_TMP" ]; then
  shape_bad=$(awk '!/^[^ ][^ ]* — ./' "$KT_MATCH_FILES_TMP" | wc -l | tr -d ' ')
  lines=$(wc -l < "$KT_MATCH_FILES_TMP" | tr -d ' ')
else lines=0; fi
tmpf=$KT_MATCH_FILES_TMP
kt_match_cleanup
cleaned=yes; [ -n "$tmpf" ] && [ -f "$tmpf" ] && cleaned=no
kt_index_match "nothing relevant here"
nm_count=$KT_MATCH_COUNT; nm_tmp=$KT_MATCH_FILES_TMP; nm_tags=$KT_MATCH_TAGS
kt_match_cleanup
if [ "$lines" -eq 5 ] && [ "$shape_bad" -eq 0 ] && [ "$cleaned" = yes ] \
   && [ "$nm_count" -eq 0 ] && [ -z "$nm_tmp" ] && [ -z "$nm_tags" ] \
   && printf '%s' "$MAIN_TAGS" | grep -qw payments && printf '%s' "$MAIN_TAGS" | grep -qw proj-b; then
  ok "existing_callers_contract (GUARD)"
else
  bad "existing_callers_contract (GUARD)" "lines $lines shape_bad $shape_bad cleaned $cleaned no-match count '$nm_count' tmp '$nm_tmp' tags '$nm_tags' main tags '$MAIN_TAGS'"
fi

# --- ledger_filter_drops_surfaced --- GUARD (regression): recording the top
# path and filtering drops exactly it.
LEDGER="$SCRATCH/ledger"
kt_index_match "$MAINQ"
top=$(ranked | cut -d' ' -f1)
printf '%s\n' "$top" > "$LEDGER"
kt_match_filter_ledger "$LEDGER"
after=$(ranked)
if [ -n "$top" ] && [ "$KT_MATCH_COUNT" -eq 4 ] && ! printf '%s\n' $after | grep -qx "$top"; then
  ok "ledger_filter_drops_surfaced (GUARD)"
else bad "ledger_filter_drops_surfaced (GUARD)" "top '$top' count $KT_MATCH_COUNT after '$after'"; fi
kt_match_record_ledger "$LEDGER"
[ "$(wc -l < "$LEDGER" | tr -d ' ')" -eq 5 ] && ok "ledger_record_appends (GUARD)" \
  || bad "ledger_record_appends (GUARD)" "ledger has $(wc -l < "$LEDGER" | tr -d ' ') lines, want 5"
kt_match_cleanup

# No temp files may outlive cleanup. GUARD: vacuous on the old lib, which
# wrote its temp files to a hard-coded /tmp instead of $TMPDIR.
left=$(find "$SCRATCH/tmp" -type f | wc -l | tr -d ' ')
[ "$left" -eq 0 ] && ok "no_temp_files_left (GUARD)" || bad "no_temp_files_left (GUARD)" "$left file(s) left in TMPDIR"

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
