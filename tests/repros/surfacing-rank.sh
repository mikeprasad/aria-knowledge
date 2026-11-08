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
trap 'chmod -R u+w "$SCRATCH" 2>/dev/null; rm -rf "$SCRATCH"' EXIT
mkdir -p "$SCRATCH/tmp" "$SCRATCH/home" "$SCRATCH/cache"
TMPDIR="$SCRATCH/tmp"; export TMPDIR
HOME="$SCRATCH/home"; export HOME
# The parse cache lives here, not in TMPDIR, so no_temp_files_left still
# means "no stray temp files" and the cache arms own their directories.
KT_SURFACE_CACHE_DIR="$SCRATCH/cache"; export KT_SURFACE_CACHE_DIR
KT_KNOWLEDGE_FOLDER="$FIX"; export KT_KNOWLEDGE_FOLDER

# projects_list comes from the fixture config, extracted the way config.sh does
# it, and is pinned to the literal the arms below were designed against.
KT_PROJECTS_LIST=$(sed -n '/^---$/,/^---$/p' "$FIX/config.md" | grep '^projects_list:' | sed 's/^projects_list: *//')
export KT_PROJECTS_LIST
if [ "$KT_PROJECTS_LIST" != "proj-a:proj-a,proj-b:proj-b,proj-c:proj-c" ]; then
  echo "fixture config.md projects_list is '$KT_PROJECTS_LIST' — arms assume proj-a,proj-b,proj-c"; exit 1
fi
# Project vocabulary applies only when projects_enabled is "true" (the
# fixture config sets it). Every project arm below relies on this.
KT_PROJECTS_ENABLED=true; export KT_PROJECTS_ENABLED

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

# --- projects_disabled_no_project_tags --- projects_enabled false, list still
# set: proj-b is an ordinary tag. A lone mention stays silent, and with two
# generic tags billing-1 (2 task words, authored) takes rank 2 — with key 1
# active every proj-b file would outrank it.
KT_PROJECTS_ENABLED=false
kt_index_match "look at proj-b"
d1_count=$KT_MATCH_COUNT; kt_match_cleanup
kt_index_match "proj-b payments"
d2_tags=$KT_MATCH_TAGS; d2_got=$(ranked); kt_match_cleanup
KT_PROJECTS_ENABLED=true
d2_want="$S projects/proj-c/billing-1.md $L2 $A1 $A2"
if [ "$d1_count" -eq 0 ] && [ "$d2_tags" = "payments proj-b" ] && [ "$d2_got" = "$d2_want" ]; then
  ok "projects_disabled_no_project_tags"
else
  bad "projects_disabled_no_project_tags" "lone count $d1_count; tags '$d2_tags' got '$d2_got' want '$d2_want'"
fi

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

# --- parse cache (D1a, C2) --- the three arms below were seen RED on the
# bbe22d3 lib, which had no cache. Each copies what it mutates.
idx_key() { printf '%s' "$1" | cksum | cut -d' ' -f1; }
sum_of() { cksum < "$1" | cut -d' ' -f1-2; }

# --- cache_built_on_first_call --- one match writes the cache, named from the
# cksum of the index PATH, its first line naming the cksum of the index CONTENT;
# a second (warm) call answers the same. With KT_SURFACE_CACHE_DIR unset the
# cache goes to TMPDIR.
C1="$SCRATCH/cache-built"; mkdir -p "$C1"
_saved_cd=$KT_SURFACE_CACHE_DIR; KT_SURFACE_CACHE_DIR="$C1"
c1_file="$C1/aria-surface-$(idx_key "$FIX/index.md").tsv"
kt_index_match "$MAINQ"; c1_cold=$(ranked); kt_match_cleanup
c1_exists=no; [ -f "$c1_file" ] && c1_exists=yes
c1_head=""; [ -f "$c1_file" ] && IFS= read -r c1_head < "$c1_file"
kt_index_match "$MAINQ"; c1_warm=$(ranked); kt_match_cleanup
KT_SURFACE_CACHE_DIR=$_saved_cd
mkdir -p "$SCRATCH/tmp2"
c1_default=$( unset KT_SURFACE_CACHE_DIR; TMPDIR="$SCRATCH/tmp2"; export TMPDIR
  kt_index_match "$MAINQ"; kt_match_cleanup
  [ -f "$SCRATCH/tmp2/aria-surface-$(idx_key "$FIX/index.md").tsv" ] && echo yes || echo no )
case "$c1_head" in *" $(sum_of "$FIX/index.md")") c1_keyed=yes ;; *) c1_keyed=no ;; esac
if [ "$c1_exists" = yes ] && [ "$c1_keyed" = yes ] && [ "$c1_default" = yes ] \
   && [ "$c1_cold" = "$MAIN_EXPECT" ] && [ "$c1_warm" = "$MAIN_EXPECT" ]; then
  ok "cache_built_on_first_call"
else
  bad "cache_built_on_first_call" "exists $c1_exists keyed $c1_keyed (head '$c1_head') default-dir $c1_default cold '$c1_cold' warm '$c1_warm'"
fi

# --- cache_invalidates_on_index_change --- warm the cache on a copy, add a
# `### gadgets` section to its Tag Index, and the next match must see it:
# "gadgets and webhooks" is silent before (one tag) and fires after. No sleep
# is needed because the key is the content, not the mtime.
KF="$SCRATCH/kf"; cp -R "$FIX" "$KF"
C2="$SCRATCH/cache-inval"; mkdir -p "$C2"
_saved_kf=$KT_KNOWLEDGE_FOLDER; KT_KNOWLEDGE_FOLDER="$KF"; KT_SURFACE_CACHE_DIR="$C2"
c2_file="$C2/aria-surface-$(idx_key "$KF/index.md").tsv"
kt_index_match "gadgets and webhooks"; c2_before=$KT_MATCH_COUNT; kt_match_cleanup
c2_head1=""; [ -f "$c2_file" ] && IFS= read -r c2_head1 < "$c2_file"
awk '/^## Other Tags/ { print "### gadgets"; print "- references/gadget-guide.md — Gadget guide"; print "" } { print }' \
  "$FIX/index.md" > "$KF/index.md"
kt_index_match "gadgets and webhooks"; c2_tags=$KT_MATCH_TAGS; c2_got=$(ranked); kt_match_cleanup
c2_head2=""; [ -f "$c2_file" ] && IFS= read -r c2_head2 < "$c2_file"
KT_KNOWLEDGE_FOLDER=$_saved_kf; KT_SURFACE_CACHE_DIR=$_saved_cd
c2_want="references/gadget-guide.md projects/proj-a/hooks.md references/webhook-basics.md"
case "$c2_head2" in *" $(sum_of "$KF/index.md")") c2_keyed=yes ;; *) c2_keyed=no ;; esac
if [ "$c2_before" -eq 0 ] && [ -n "$c2_head1" ] && [ "$c2_head1" != "$c2_head2" ] && [ "$c2_keyed" = yes ] \
   && [ "$c2_tags" = "webhooks gadgets" ] && [ "$c2_got" = "$c2_want" ]; then
  ok "cache_invalidates_on_index_change"
else
  bad "cache_invalidates_on_index_change" "before $c2_before head1 '$c2_head1' head2 '$c2_head2' keyed $c2_keyed tags '$c2_tags' got '$c2_got' want '$c2_want'"
fi

# --- cache_survives_unwritable_dir --- with the cache dir read-only the match
# is still correct and returns 0, and nothing is written there. Then the dir
# is made writable and the next match must build the cache IN IT, which proves
# the read-only dir was the cache target (otherwise this arm passes on any lib).
if [ "$(id -u)" -eq 0 ]; then
  printf "SKIP  cache_survives_unwritable_dir — running as root, a read-only dir does not stop writes\n"
else
  C3="$SCRATCH/cache-ro"; mkdir -p "$C3"; chmod 555 "$C3"
  KT_SURFACE_CACHE_DIR="$C3"
  kt_index_match "$MAINQ"; c3_rc=$?; c3_main=$(ranked); kt_match_cleanup
  kt_index_match "check webhooks and payments"; c3_rc2=$?; c3_rar=$(ranked); kt_match_cleanup
  c3_files_ro=$(find "$C3" -type f | wc -l | tr -d ' ')
  chmod 755 "$C3"
  kt_index_match "$MAINQ"; kt_match_cleanup
  c3_built=no; [ -f "$C3/aria-surface-$(idx_key "$FIX/index.md").tsv" ] && c3_built=yes
  KT_SURFACE_CACHE_DIR=$_saved_cd
  c3_rar_want="projects/proj-c/billing-1.md projects/proj-a/hooks.md references/webhook-basics.md projects/proj-c/billing-2.md projects/proj-c/billing-3.md"
  if [ "$c3_rc" -eq 0 ] && [ "$c3_rc2" -eq 0 ] && [ "$c3_main" = "$MAIN_EXPECT" ] && [ "$c3_rar" = "$c3_rar_want" ] \
     && [ "$c3_files_ro" -eq 0 ] && [ "$c3_built" = yes ]; then
    ok "cache_survives_unwritable_dir"
  else
    bad "cache_survives_unwritable_dir" "rc $c3_rc/$c3_rc2 main '$c3_main' rarest '$c3_rar' files-in-ro $c3_files_ro built-after-chmod $c3_built"
  fi
fi

# --- cache_swap_mid_query_is_consistent --- another process can mv a rebuilt
# cache into place between the query's plan step (which computes line ranges)
# and its row extraction. Deterministic window: _kt_index_cache_plan is wrapped
# (its definition is copied out of the lib under another name; sh functions are
# late-bound) so that right after it runs, a VALID cache built from a shifted
# index replaces the one it read. The answer must still equal a clean run.
# Seen RED on 0f5c0f3, which applied the old ranges to the new file.
KF5="$SCRATCH/kf5"; cp -R "$FIX" "$KF5"
KF5S="$SCRATCH/kf5-shifted"; cp -R "$FIX" "$KF5S"
awk '/^### payments/ { print "### aaa-shift"; for (i = 1; i <= 6; i++) print "- references/shift-" i ".md — Shift filler " i; print "" } { print }' \
  "$FIX/index.md" > "$KF5S/index.md"
C5="$SCRATCH/cache-swap"; C5S="$SCRATCH/cache-swap-src"; mkdir -p "$C5" "$C5S"
_saved_kf=$KT_KNOWLEDGE_FOLDER
KT_KNOWLEDGE_FOLDER="$KF5S"; KT_SURFACE_CACHE_DIR="$C5S"
kt_index_match "$MAINQ"; kt_match_cleanup
c5_shifted=$(kt_index_cache_path)
KT_KNOWLEDGE_FOLDER="$KF5"; KT_SURFACE_CACHE_DIR="$C5"
kt_index_match "$MAINQ"; c5_clean=$(ranked); c5_clean_tags=$KT_MATCH_TAGS; kt_match_cleanup
C5_TARGET=$(kt_index_cache_path)
C5_SWAP="$SCRATCH/swap-pending.tsv"; cp "$c5_shifted" "$C5_SWAP"
eval "$(sed -n '/^_kt_index_cache_plan() {/,/^}/p' "$LIB" | sed '1s/^_kt_index_cache_plan()/_kt_orig_plan()/')"
_kt_index_cache_plan() {
  _kt_orig_plan; _kt_w_rc=$?
  [ -f "$C5_SWAP" ] && mv -f "$C5_SWAP" "$C5_TARGET"
  return $_kt_w_rc
}
kt_index_match "$MAINQ"; c5_got=$(ranked); c5_tags=$KT_MATCH_TAGS; kt_match_cleanup
c5_swapped=no; [ ! -f "$C5_SWAP" ] && c5_swapped=yes
eval "$(sed -n '/^_kt_index_cache_plan() {/,/^}/p' "$LIB")"
KT_KNOWLEDGE_FOLDER=$_saved_kf; KT_SURFACE_CACHE_DIR=$_saved_cd
if [ -n "$c5_shifted" ] && [ "$c5_clean" = "$MAIN_EXPECT" ] && [ "$c5_swapped" = yes ] \
   && [ "$c5_got" = "$c5_clean" ] && [ "$c5_tags" = "$c5_clean_tags" ]; then
  ok "cache_swap_mid_query_is_consistent"
else
  bad "cache_swap_mid_query_is_consistent" "swapped $c5_swapped clean '$c5_clean' got '$c5_got' tags '$c5_tags' vs '$c5_clean_tags'"
fi

# --- aria-surface.sh CLI arms --- the script is run as a subprocess with HOME,
# TMPDIR and KT_SURFACE_CACHE_DIR already isolated above. The config is written
# in the format config.sh parses (YAML-ish front matter between --- lines); the
# committed fixture config.md has no knowledge_folder, so it is not used here.
CLI="$REPO_ROOT/plugin-claude-code/scripts/aria-surface.sh"
CLIHOME="$SCRATCH/clihome"; mkdir -p "$CLIHOME/.claude"
cat > "$CLIHOME/.claude/aria-knowledge.local.md" <<CFG
---
knowledge_folder: $FIX
projects_enabled: true
projects_list: proj-a:proj-a,proj-b:proj-b,proj-c:proj-c
---
CFG
cli_run() { # $1 text; stdout only, exit code in cli_rc
  cli_out=$(HOME="$CLIHOME" KT_CONFIG= KT_KNOWLEDGE_FOLDER= KT_PROJECTS_LIST= KT_PROJECTS_ENABLED= \
    sh "$CLI" "$1" 2>/dev/null); cli_rc=$?
}
cli_run "$MAINQ"
cli_want_paths=$(printf '%s\n' $MAIN_EXPECT)
cli_first=$(printf '%s\n' "$cli_out" | sed -n 1p)
cli_rest=$(printf '%s\n' "$cli_out" | sed 1d)
if [ "$cli_rc" -eq 0 ] && [ -n "${cli_first#tags: }" ] && [ "${cli_first#tags: }" != "$cli_first" ] \
   && [ "$cli_rest" = "$cli_want_paths" ]; then
  ok "cli_prints_tags_then_paths"
else
  bad "cli_prints_tags_then_paths" "rc $cli_rc first '$cli_first' paths '$(printf '%s' "$cli_rest" | tr '\n' ' ')'"
fi

cli_run "nothing relevant here at all"
if [ "$cli_rc" -eq 0 ] && [ -z "$cli_out" ]; then
  ok "cli_silent_when_not_fired"
else
  bad "cli_silent_when_not_fired" "rc $cli_rc out '$cli_out'"
fi

EMPTYHOME="$SCRATCH/emptyhome"; mkdir -p "$EMPTYHOME"
cli_e1=$(HOME="$EMPTYHOME" KT_CONFIG= KT_KNOWLEDGE_FOLDER= sh "$CLI" "$MAINQ" 2>&1); cli_e1rc=$?
cli_e2=$(HOME="$EMPTYHOME" KT_CONFIG= KT_KNOWLEDGE_FOLDER= sh "$CLI" 2>&1); cli_e2rc=$?
if [ "$cli_e1rc" -eq 0 ] && [ -z "$cli_e1" ] && [ "$cli_e2rc" -eq 0 ] && [ -z "$cli_e2" ]; then
  ok "cli_exit0_without_config"
else
  bad "cli_exit0_without_config" "rc $cli_e1rc/$cli_e2rc out '$cli_e1' '$cli_e2'"
fi

# --- many_matched_tags_still_ranks --- a query matching hundreds of tags or
# project dirs must still rank. The cache path once returned 0 files, silently,
# past ~175 matched tags: BSD sed rejects a script line over 2,048 bytes and the
# extraction script was one line. Synthetic index generated here: 420 tags
# (tag001-010 carry 3 files each, the rest 1; tag200 is an empty section; the
# tag300 file has a 10 KB description), one 300-char tag, and a `### misc`
# section listing projects/p001..p400/notes.md. Seen RED on a8c0a2d.
KFM="$SCRATCH/kfm"; mkdir -p "$KFM"
LONGTAG=$(awk 'BEGIN { s = "long"; for (i = 0; i < 296; i++) s = s "x"; print s }')
awk -v longtag="$LONGTAG" 'BEGIN {
  print "# Knowledge Index"; print ""; print "## Known Tags"; print ""; print "none"; print ""; print "## Tag Index"; print ""
  for (i = 1; i <= 420; i++) {
    n = sprintf("%03d", i); print "### tag" n
    if (i <= 10) { print "- references/n" n "-a.md — Note " n " a"; print "- references/n" n "-b.md — Note " n " b"; print "- references/n" n "-c.md — Note " n " c" }
    else if (i == 200) { }
    else if (i == 300) { d = ""; for (k = 0; k < 1000; k++) d = d "filler-txt"; print "- references/n" n ".md — " d }
    else print "- references/n" n ".md — Note " n
    print ""
  }
  print "### " longtag; print "- references/long.md — Long tag note"; print ""
  print "### misc"
  for (j = 1; j <= 400; j++) { n = sprintf("%03d", j); print "- projects/p" n "/notes.md — Project " n " notes" }
  print ""; print "## Other Tags"; print ""
}' > "$KFM/index.md"
mq_all=$(awk 'BEGIN { for (i = 1; i <= 420; i++) printf "tag%03d ", i }')"$LONGTAG"
mq_odd=$(awk 'BEGIN { for (i = 1; i <= 420; i += 2) printf "tag%03d ", i }')
mq_proj=$(awk 'BEGIN { for (j = 1; j <= 400; j += 2) printf "p%03d ", j }')
mp_list=$(awk 'BEGIN { for (j = 1; j <= 400; j++) printf "%sp%03d:p%03d", (j > 1 ? "," : ""), j, j }')
_saved_kf=$KT_KNOWLEDGE_FOLDER; _saved_pl=$KT_PROJECTS_LIST
# The uncached fallback is disabled here, so this arm proves the CACHE path
# ranks dense queries; a fallback rescuing a broken cache path would mask it.
_kt_index_full_parse() { : > "$_kt_raw"; }
KT_KNOWLEDGE_FOLDER="$KFM"; KT_SURFACE_CACHE_DIR="$SCRATCH/cache-many"; mkdir -p "$KT_SURFACE_CACHE_DIR"
kt_index_match "$mq_all"; m_all_n=$KT_MATCH_COUNT; m_all_t=$(printf '%s' "$KT_MATCH_TAGS" | wc -w | tr -d ' '); m_all=$(ranked); kt_match_cleanup
kt_index_match "$mq_odd"; m_odd_n=$KT_MATCH_COUNT; m_odd=$(ranked); kt_match_cleanup
KT_PROJECTS_LIST="$mp_list"
kt_index_match "$mq_proj"; m_proj_n=$KT_MATCH_COUNT; m_proj_t=$(printf '%s' "$KT_MATCH_TAGS" | wc -w | tr -d ' '); m_proj=$(ranked); kt_match_cleanup
KT_KNOWLEDGE_FOLDER=$_saved_kf; KT_PROJECTS_LIST=$_saved_pl; KT_SURFACE_CACHE_DIR=$_saved_cd
unset -f _kt_index_full_parse
eval "$(sed -n '/^_kt_index_full_parse() {/,/^}/p' "$LIB")"
m_all_want="references/n011.md references/n012.md references/n013.md references/n014.md references/n015.md"
m_odd_want="references/n011.md references/n013.md references/n015.md references/n017.md references/n019.md"
m_proj_want="projects/p001/notes.md projects/p003/notes.md projects/p005/notes.md projects/p007/notes.md projects/p009/notes.md"
if [ "$m_all_n" -eq 5 ] && [ "$m_all_t" -eq 421 ] && [ "$m_all" = "$m_all_want" ] \
   && [ "$m_odd_n" -eq 5 ] && [ "$m_odd" = "$m_odd_want" ] \
   && [ "$m_proj_n" -eq 5 ] && [ "$m_proj_t" -eq 200 ] && [ "$m_proj" = "$m_proj_want" ]; then
  ok "many_matched_tags_still_ranks"
else
  bad "many_matched_tags_still_ranks" "all: n $m_all_n tags $m_all_t got '$m_all' | odd: n $m_odd_n got '$m_odd' | proj: n $m_proj_n tags $m_proj_t got '$m_proj'"
fi

# --- cache_failure_falls_back_to_full_parse --- if every cache attempt fails,
# the answer must come from an uncached full parse, never be an empty "no
# match". Every attempt is forced to fail by wrapping _kt_index_cache_answer
# (late-bound) to report failure; the answers must equal the normal path's.
# Seen RED on a8c0a2d, which answered nothing.
kt_index_match "$MAINQ"; fb_n1=$(ranked); fb_t1=$KT_MATCH_TAGS; kt_match_cleanup
kt_index_match "check webhooks and payments"; fb_n2=$(ranked); kt_match_cleanup
kt_index_match "site-1 skylights"; fb_n3=$(ranked); fb_t3=$KT_MATCH_TAGS; kt_match_cleanup
kt_index_match "look at payments"; fb_n4=$KT_MATCH_COUNT; kt_match_cleanup
_kt_index_cache_answer() { : > "$_kt_raw"; return 2; }
kt_index_match "$MAINQ"; fb_f1=$(ranked); fb_ft1=$KT_MATCH_TAGS; kt_match_cleanup
kt_index_match "check webhooks and payments"; fb_f2=$(ranked); kt_match_cleanup
kt_index_match "site-1 skylights"; fb_f3=$(ranked); fb_ft3=$KT_MATCH_TAGS; kt_match_cleanup
kt_index_match "look at payments"; fb_f4=$KT_MATCH_COUNT; kt_match_cleanup
eval "$(sed -n '/^_kt_index_cache_answer() {/,/^}/p' "$LIB")"
if [ "$fb_n1" = "$MAIN_EXPECT" ] && [ "$fb_f1" = "$fb_n1" ] && [ "$fb_ft1" = "$fb_t1" ] \
   && [ -n "$fb_n2" ] && [ "$fb_f2" = "$fb_n2" ] && [ -n "$fb_n3" ] && [ "$fb_f3" = "$fb_n3" ] && [ "$fb_ft3" = "$fb_t3" ] \
   && [ "$fb_n4" -eq 0 ] && [ "$fb_f4" -eq 0 ]; then
  ok "cache_failure_falls_back_to_full_parse"
else
  bad "cache_failure_falls_back_to_full_parse" "main '$fb_f1' vs '$fb_n1'; rarest '$fb_f2' vs '$fb_n2'; alias '$fb_f3' vs '$fb_n3'; lone-generic $fb_f4 vs $fb_n4"
fi

# No temp files may outlive cleanup. GUARD: vacuous on the old lib, which
# wrote its temp files to a hard-coded /tmp instead of $TMPDIR.
left=$(find "$SCRATCH/tmp" -type f | wc -l | tr -d ' ')
[ "$left" -eq 0 ] && ok "no_temp_files_left (GUARD)" || bad "no_temp_files_left (GUARD)" "$left file(s) left in TMPDIR"

printf "\n%d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
