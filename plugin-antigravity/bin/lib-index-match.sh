#!/bin/sh
# lib-index-match.sh — shared tag-match helper for aria-knowledge
# Sourced by hook scripts and (indirectly via skill-driven Bash) by skills
# that surface knowledge-index matches. Refactored out of the inline matcher
# previously living in task-context-check.sh (v2.14.x → v2.15.0).
#
# Usage:
#   SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
#   . "$SCRIPT_DIR/config.sh"           # provides KT_KNOWLEDGE_FOLDER
#   . "$SCRIPT_DIR/lib-index-match.sh"  # provides kt_index_match
#
#   kt_index_match "fix stripe webhook timeout"
#   if [ "$KT_MATCH_COUNT" -gt 0 ]; then
#     # KT_MATCH_TAGS       — space-separated matched known-tag list
#     # KT_MATCH_COUNT      — integer, files matched (≤5, post-dedupe)
#     # KT_MATCH_FILES_TMP  — path to temp file; one "path — description" per line
#     do_something_with "$KT_MATCH_FILES_TMP"
#   fi
#   kt_match_cleanup
#
# Contract:
#   - Sets/resets KT_MATCH_TAGS, KT_MATCH_COUNT, KT_MATCH_FILES_TMP on entry.
#   - Returns 0 in all states; callers branch on KT_MATCH_COUNT.
#   - Caller MUST invoke kt_match_cleanup to remove the temp file when done.
#   - Fires on ≥2 matched tags OR ≥1 matched project tag; caps emission at
#     5 files ranked project-first (order below, at the sort). Changing these
#     is a deliberate cross-cutting policy change, not a per-caller knob.
#
# Inputs (environment):
#   KT_KNOWLEDGE_FOLDER  — absolute path to the knowledge root (required)
#   KT_PROJECTS_LIST     — optional `tag:path,tag:path`; its tags join the
#                          match vocabulary as PROJECT tags (config.sh sets it)
#   KT_PROJECTS_ENABLED  — project tags apply only when this is "true"; unset
#                          or any other value means no project tags
#   KT_SURFACE_CACHE_DIR — optional dir for the parsed-index cache (default
#                          $TMPDIR, else /tmp); see kt_index_cache_path
#
# What this does NOT cover (caller's responsibility):
#   - Cooldowns / throttling — per-trigger policy, not shared mechanism.
#   - Output formatting — each caller formats matched paths its own way.
#   - Per-session dedup ledger (/tmp/aria-active-{session_id}) — added in
#     checkpoint 2 across active-mode hooks.
#   - Active vs passive wording — caller branches on KT_ACTIVE_SURFACING.

# Task words for ranking key 3: lowercase, split on non-alphanumerics, drop
# tokens of length <= 2 and a fixed stopword list. One per line, first-seen
# order, deduped. Distinct from the tag-matching tokenizer in kt_index_match,
# which keeps hyphenated tokens whole and keeps short tokens.
kt_index_tokens() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '\n' \
    | awk 'BEGIN {
             n = split("the and for from into with this that are was were have has add fix new update about make use", s, " ")
             for (i = 1; i <= n; i++) stop[s[i]] = 1
           }
           length($0) > 2 && !($0 in stop) && !seen[$0]++'
}

# Path of the parsed-index cache for "$KT_KNOWLEDGE_FOLDER/index.md":
#   ${KT_SURFACE_CACHE_DIR:-${TMPDIR:-/tmp}}/aria-surface-<cksum of the index PATH>.tsv
# Returns 1 (prints nothing) when KT_KNOWLEDGE_FOLDER is unset.
kt_index_cache_path() {
  [ -z "$KT_KNOWLEDGE_FOLDER" ] && return 1
  _kt_pk=$(printf '%s' "$KT_KNOWLEDGE_FOLDER/index.md" | cksum) || return 1
  printf '%s/aria-surface-%s.tsv\n' "${KT_SURFACE_CACHE_DIR:-${TMPDIR:-/tmp}}" "${_kt_pk%% *}"
}

# One awk pass over index.md → the cache, on stdout. $1 index path, $2 the
# first line (format version + cksum of the index content). TAB-separated:
#   @tag    <tag>  <first>  <last>   vocabulary (`### ` under `## Tag Index`, index
#                                    order) and the line range of its group
#   @dir    <dir>  <first>  <last>   a `projects/<dir>/` prefix and its group's range
#   @alias  <alias>  <canonical>     from `[aliases: …]` in `## Known Tags`, first wins
#   @end                             end of the header
#   <carrier>  <path>  <pos>  <line> one row per (carrier, path), grouped: all tag
#       groups, then all dir groups. <carrier> is the tag, or the dir for a dir
#       group; <pos> is the path's first position across Tag Index + Other Tags;
#       <line> is the path's FIRST `path — description` line.
# Groups and ranges exist so a query reads the small header and then pulls only
# the groups it matched (sed), never the whole file: reading the whole cache in
# awk costs about as much as parsing the index.
# Project config is deliberately NOT in the cache — a dir group is a property of
# the paths, and which dirs are projects is decided per query — so a
# projects_list or projects_enabled change never serves a stale result.
# Aliases: `tag [aliases: a, b]` or `tag [aliases: a b]`; an alias containing a
# character the tokenizer splits on (e.g. a dot) can never match and is inert.
_kt_index_cache_build() {
  _KT_HEAD="$2" awk '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function pathof(l,   i) { i = index(l, " — "); return i ? substr(l, 1, i - 1) : l }
    BEGIN { sec = ""; tag = ""; known = ""; nv = 0; nd = 0; nl = 0 }
    /^## / { sec = trim(substr($0, 4)); tag = ""; next }
    sec == "Known Tags" { known = known " " $0; next }
    /^### / {
      tag = ""
      if (sec == "Tag Index" || sec == "Other Tags") tag = tolower(trim(substr($0, 5)))
      # A tag holding a TAB or starting with @ can never be matched (tokens are
      # alnum and hyphen, aliases split on whitespace); drop it rather than let
      # it break or mimic a header row.
      if (index(tag, "\t") || substr(tag, 1, 1) == "@") tag = ""
      if (sec == "Tag Index" && tag != "" && !(tag in tn)) { tn[tag] = 0; vorder[++nv] = tag }
      next
    }
    /^- / && (sec == "Tag Index" || sec == "Other Tags") {
      line = substr($0, 3); p = pathof(line)
      if (!(p in pos)) { pos[p] = ++nl; desc[p] = line; k = p; gsub(/\t/, " ", k); key[p] = k }
      if (sec == "Tag Index" && tag != "" && !((tag SUBSEP p) in seen)) {
        seen[tag SUBSEP p] = 1; TG[tag, ++tn[tag]] = p
      }
      if (substr(p, 1, 9) == "projects/") {
        r = substr(p, 10); j = index(r, "/"); d = (j > 1) ? substr(r, 1, j - 1) : ""
        if (d != "" && !index(d, "\t") && !(("/" SUBSEP d SUBSEP p) in seen)) {
          seen["/" SUBSEP d SUBSEP p] = 1
          if (!(d in dn)) { dn[d] = 0; dorder[++nd] = d }
          DG[d, ++dn[d]] = p
        }
      }
      next
    }
    END {
      s = known; na = 0
      while ((i = index(s, "[aliases:")) > 0) {
        pre = substr(s, 1, i - 1); rest = substr(s, i + 9)
        j = index(rest, "]"); if (!j) break
        list = substr(rest, 1, j - 1); s = substr(rest, j + 1)
        n = split(pre, pw, /[ ,`*\t]+/); canon = ""
        for (k = n; k >= 1; k--) if (pw[k] != "") { canon = tolower(pw[k]); break }
        if (canon == "") continue
        m = split(list, al, /[ ,\t]+/)
        for (k = 1; k <= m; k++) { a = tolower(al[k]); if (a != "" && !(a in alias)) { alias[a] = canon; AL[++na] = a } }
      }
      print ENVIRON["_KT_HEAD"]
      at = 1 + nv + nd + na + 2
      for (i = 1; i <= nv; i++) {
        t = vorder[i]
        if (tn[t]) { printf "@tag\t%s\t%d\t%d\n", t, at, at + tn[t] - 1; at += tn[t] }
        else printf "@tag\t%s\t0\t0\n", t
      }
      for (i = 1; i <= nd; i++) { d = dorder[i]; printf "@dir\t%s\t%d\t%d\n", d, at, at + dn[d] - 1; at += dn[d] }
      for (i = 1; i <= na; i++) printf "@alias\t%s\t%s\n", AL[i], alias[AL[i]]
      print "@end"
      for (i = 1; i <= nv; i++) { t = vorder[i]; for (k = 1; k <= tn[t]; k++) { p = TG[t, k]; printf "%s\t%s\t%d\t%s\n", t, key[p], pos[p], desc[p] } }
      for (i = 1; i <= nd; i++) { d = dorder[i]; for (k = 1; k <= dn[d]; k++) { p = DG[d, k]; printf "%s\t%s\t%d\t%s\n", d, key[p], pos[p], desc[p] } }
    }
  ' "$1"
}

# Query step 1, reading the cache header on stdin (it stops at @end); uses
# _kt_words and _kt_plist from kt_index_match. Vocabulary = @tag rows ∪
# projects_list tags; an alias token is replaced by its canonical tag before
# matching, unless the token is itself a tag. Prints nothing when the match
# does not fire (>=2 matched tags, OR >=1 matched project tag), and the single
# line @stale when line 1 is not $_kt_head or the header is cut short; otherwise
# two lines: the matched tags (vocabulary order), and a sed script printing the
# groups that carry them — each matched tag's group, and for a matched project
# tag also the group of every listed path under `projects/<tag>/`.
_kt_index_cache_plan() {
  _KT_HEAD="$_kt_head" _KT_WORDS="$_kt_words" _KT_PROJECTS="$_kt_plist" awk '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function rng(a, b) { if (a > 0) { script = script a "," b "p;"; if (b > last) last = b } }
    BEGIN {
      FS = "\t"
      nw = split(ENVIRON["_KT_WORDS"], W, " ")
      npl = split(ENVIRON["_KT_PROJECTS"], PL, ",")
      for (i = 1; i <= npl; i++) {
        c = index(PL[i], ":"); if (!c) continue
        t = tolower(trim(substr(PL[i], 1, c - 1)))
        if (t != "" && !(t in isproj)) { isproj[t] = 1; porder[++npo] = t }
      }
      nv = 0
    }
    NR == 1 { if ($0 != ENVIRON["_KT_HEAD"]) { stale = 1; exit }; next }
    $1 == "@tag" { if (!($2 in hassec)) { hassec[$2] = 1; vorder[++nv] = $2; ta[$2] = $3; tb[$2] = $4 }; next }
    $1 == "@dir" { da[$2] = $3; db[$2] = $4; next }
    $1 == "@alias" { if (!($2 in alias)) alias[$2] = $3; next }
    $1 == "@end" { done = 1; exit }
    END {
      if (stale || !done) { print "@stale"; exit }
      for (i = 1; i <= nw; i++) {
        w = W[i]; if (w == "") continue
        c = w
        if (!(c in hassec) && !(c in isproj) && (w in alias)) c = alias[w]
        if ((c in hassec) || (c in isproj)) matched[c] = 1
      }
      out = ""; nm = 0; npm = 0; script = ""; last = 0
      for (i = 1; i <= nv; i++) { t = vorder[i]; if (t in matched) { out = out " " t; nm++; if (t in isproj) npm++; rng(ta[t], tb[t]) } }
      for (i = 1; i <= npo; i++) { t = porder[i]; if ((t in matched) && !(t in hassec)) { out = out " " t; nm++; npm++ } }
      if (nm < 2 && npm < 1) exit
      for (i = 1; i <= npo; i++) { t = porder[i]; if ((t in matched) && (t in da)) rng(da[t], db[t]) }
      print substr(out, 2)
      print (last ? script last "q" : "")
    }
  '
}

# Query step 2, reading on stdin the cache's line 1 followed by the carrying
# rows step 1 selected; uses _kt_head, _kt_mtags (the matched tags), _kt_task
# and _kt_plist. Prints the single line @stale when line 1 is not $_kt_head
# (the file was replaced after step 1 read it); otherwise one line per
# candidate:  C<TAB>k1<TAB>k2<TAB>k3<TAB>k4<TAB>k5<TAB>k6<TAB>path — description
_kt_index_cache_rank() {
  _KT_HEAD="$_kt_head" _KT_MATCHED="$_kt_mtags" _KT_TASK="$_kt_task" _KT_PROJECTS="$_kt_plist" awk '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    BEGIN {
      FS = "\t"
      n = split(ENVIRON["_KT_MATCHED"], M, " "); for (i = 1; i <= n; i++) matched[M[i]] = 1
      nt = split(ENVIRON["_KT_TASK"], T, " ")
      npl = split(ENVIRON["_KT_PROJECTS"], PL, ",")
      for (i = 1; i <= npl; i++) {
        c = index(PL[i], ":"); if (!c) continue
        t = tolower(trim(substr(PL[i], 1, c - 1))); if (t != "") isproj[t] = 1
      }
    }
    NR == 1 { if ($0 != ENVIRON["_KT_HEAD"]) { stale = 1; exit }; next }
    {
      t = $1; p = $2
      if (!((t SUBSEP p) in carries)) { carries[t SUBSEP p] = 1; cnt[t]++ }
      if (!(p in cpos)) {
        cpos[p] = $3; l = $0
        for (k = 1; k <= 3; k++) l = substr(l, index(l, "\t") + 1)
        cdesc[p] = l
      }
    }
    END {
      if (stale || NR == 0) { print "@stale"; exit }
      for (p in cpos) {
        k2 = 0; k1 = 0; k5 = 0
        for (t in matched) if ((t SUBSEP p) in carries) {
          k2++; if (t in isproj) k1 = 1
          if (k5 == 0 || cnt[t] < k5) k5 = cnt[t]
        }
        if (!k2) continue
        x = tolower(cdesc[p]); gsub(/[^a-z0-9]+/, " ", x); x = " " x " "
        k3 = 0
        for (k = 1; k <= nt; k++) if (T[k] != "" && index(x, " " T[k] " ")) k3++
        k4 = (index(p, "logs/") == 1) ? 0 : 1
        printf "C\t%d\t%d\t%d\t%d\t%d\t%d\t%s\n", k1, k2, k3, k4, k5, cpos[p], cdesc[p]
      }
    }
  '
}

# Rebuild from a SNAPSHOT of index.md into $1, and set _kt_head to the cksum of
# the bytes actually parsed. Parsing the live file while it is being edited
# could label one version's content with another version's cksum; with the
# snapshot, one header always means one byte-identical cache (the build is
# deterministic), which is what makes the header check in each read sufficient.
_kt_index_cache_snapshot_build() {
  _kt_snap=$(mktemp "${TMPDIR:-/tmp}/aria-match-index.XXXXXX") || return 1
  _kt_brc=1
  if cp "$_kt_index" "$_kt_snap" 2>/dev/null; then
    _kt_ssum=$(cksum < "$_kt_snap" 2>/dev/null)
    if [ -n "$_kt_ssum" ]; then
      _kt_head="aria-surface-cache 2 $_kt_ssum"
      _kt_index_cache_build "$_kt_snap" "$_kt_head" > "$1" 2>/dev/null && _kt_brc=0
    fi
  fi
  rm -f "$_kt_snap" 2>/dev/null
  return $_kt_brc
}

# Answer from cache file $1 into $_kt_raw. Returns 0 when answered (the raw
# file is empty when the match does not fire), 2 when a read saw a different
# cache than expected (stale, foreign, short or swapped mid-query by another
# writer's mv). The file is opened twice — the plan reads the header, sed
# pulls the row groups — and EACH read checks line 1 against $_kt_head, so
# both reads provably came from the same cache version.
_kt_index_cache_answer() {
  : > "$_kt_raw"
  _kt_plan=$(_kt_index_cache_plan < "$1" 2>/dev/null)
  [ "$_kt_plan" = "@stale" ] && return 2
  [ -z "$_kt_plan" ] && return 0
  _kt_mtags=${_kt_plan%%"$_kt_nl"*}
  _kt_sed=""
  case "$_kt_plan" in *"$_kt_nl"*) _kt_sed=${_kt_plan#*"$_kt_nl"} ;; esac
  _kt_rows=""
  if [ -n "$_kt_sed" ]; then
    _kt_rows=$(sed -n "1p;$_kt_sed" "$1" 2>/dev/null | _kt_index_cache_rank 2>/dev/null)
    [ "$_kt_rows" = "@stale" ] && return 2
  fi
  {
    printf 'T\t%s\n' "$_kt_mtags"
    [ -n "$_kt_rows" ] && printf '%s\n' "$_kt_rows"
  } > "$_kt_raw"
  return 0
}

kt_index_match() {
  KT_MATCH_TAGS=""
  KT_MATCH_COUNT=0
  KT_MATCH_FILES_TMP=""

  _kt_query="$1"
  [ -z "$_kt_query" ] && return 0
  [ -z "$KT_KNOWLEDGE_FOLDER" ] && return 0

  _kt_index="$KT_KNOWLEDGE_FOLDER/index.md"
  [ ! -f "$_kt_index" ] && return 0

  # Tokenize: lowercase, then emit TWO kinds of tokens, deduped together:
  #   1. hyphen-preserving whole tokens — so a multi-word directory/tag name
  #      like `web-app` survives as ONE token and can match its exact
  #      `### web-app` known tag (otherwise the hyphen is destroyed and only
  #      the broad parent token `web` matches → wrong files surface).
  #   2. fully-split alnum words — preserves the original single-word matching
  #      (`web`, `app`) for backward compatibility.
  # Both passes feed one deduped set; the matcher still does exact word==tag.
  _kt_lower=$(printf '%s' "$_kt_query" | tr '[:upper:]' '[:lower:]')
  _kt_whole=$(printf '%s' "$_kt_lower" | tr -cs '[:alnum:]-' ' ' | tr ' ' '\n')
  _kt_split=$(printf '%s' "$_kt_lower" | tr -cs '[:alnum:]' ' ' | tr ' ' '\n')
  _kt_words=$(printf '%s\n%s\n' "$_kt_whole" "$_kt_split" | grep -v '^-*$' | sort -u | tr '\n' ' ')
  [ -z "$_kt_words" ] && return 0
  _kt_task=$(kt_index_tokens "$_kt_query" | tr '\n' ' ')

  # Project tags exist only when projects are enabled; unset counts as off,
  # matching the other project features (config.sh defaults it to false).
  _kt_plist=""
  [ "$KT_PROJECTS_ENABLED" = "true" ] && _kt_plist="$KT_PROJECTS_LIST"

  _kt_tab=$(printf '\t')
  _kt_raw=$(mktemp "${TMPDIR:-/tmp}/aria-match-raw.XXXXXX") || return 0

  # Parse cache (D1a). The key is the cksum of index.md's CONTENT, stored in
  # the cache's first line; any change to the index rebuilds it. A stale,
  # foreign, unreadable or mid-query-swapped cache is never used for an answer
  # (see _kt_index_cache_answer). When the cache cannot be (re)written —
  # unwritable dir, a file owned by someone else — the parse goes to a private
  # temp file for this one call instead: same answer, only slower.
  _kt_sum=$(cksum < "$_kt_index" 2>/dev/null)
  if [ -z "$_kt_sum" ]; then rm -f "$_kt_raw" 2>/dev/null; return 0; fi
  _kt_head="aria-surface-cache 2 $_kt_sum"
  _kt_nl='
'
  _kt_arc=2
  _kt_cache=$(kt_index_cache_path 2>/dev/null) || _kt_cache=""
  if [ -n "$_kt_cache" ] && [ -f "$_kt_cache" ] && [ -O "$_kt_cache" ] 2>/dev/null; then
    _kt_index_cache_answer "$_kt_cache"; _kt_arc=$?
  fi
  if [ "$_kt_arc" -eq 2 ] && [ -n "$_kt_cache" ]; then
    # Temp file in the cache's own dir, then mv: a reader never sees half a cache.
    _kt_tmpc=$(mktemp "${_kt_cache%/*}/.aria-surface.XXXXXX" 2>/dev/null) || _kt_tmpc=""
    if [ -n "$_kt_tmpc" ]; then
      if _kt_index_cache_snapshot_build "$_kt_tmpc" && mv -f "$_kt_tmpc" "$_kt_cache" 2>/dev/null; then
        _kt_index_cache_answer "$_kt_cache"; _kt_arc=$?
      else
        rm -f "$_kt_tmpc" 2>/dev/null
      fi
    fi
  fi
  if [ "$_kt_arc" -eq 2 ]; then
    # Private, single-use: no other writer can touch it, so this cannot be stale.
    _kt_once=$(mktemp "${TMPDIR:-/tmp}/aria-match-cache.XXXXXX") || { rm -f "$_kt_raw" 2>/dev/null; return 0; }
    if _kt_index_cache_snapshot_build "$_kt_once"; then
      _kt_index_cache_answer "$_kt_once"; _kt_arc=$?
    fi
    rm -f "$_kt_once" 2>/dev/null
    [ "$_kt_arc" -eq 0 ] || : > "$_kt_raw"
  fi

  _kt_tags_line=$(grep "^T${_kt_tab}" "$_kt_raw" 2>/dev/null | head -1)
  if [ -z "$_kt_tags_line" ]; then
    rm -f "$_kt_raw" 2>/dev/null
    return 0
  fi

  _kt_files=$(mktemp "${TMPDIR:-/tmp}/aria-match-files.XXXXXX") || { rm -f "$_kt_raw"; return 0; }
  # Order (D2): 1 carries a matched project tag · 2 more matched tags ·
  # 3 more task-word overlap (path or description) · 4 authored before logs/ ·
  # 5 rarest matched tag carried (fewest files) · 6 index order. Cap 5.
  grep "^C${_kt_tab}" "$_kt_raw" \
    | sort -t "$_kt_tab" -k2,2nr -k3,3nr -k4,4nr -k5,5nr -k6,6n -k7,7n \
    | head -5 | cut -f8- > "$_kt_files"
  rm -f "$_kt_raw" 2>/dev/null

  if [ ! -s "$_kt_files" ]; then
    rm -f "$_kt_files" 2>/dev/null
    return 0
  fi

  KT_MATCH_COUNT=$(wc -l < "$_kt_files" | tr -d ' ')
  KT_MATCH_TAGS=$(printf '%s' "$_kt_tags_line" | cut -f2-)
  KT_MATCH_FILES_TMP="$_kt_files"
  return 0
}

# Release the temp file allocated by kt_index_match. Idempotent.
kt_match_cleanup() {
  if [ -n "$KT_MATCH_FILES_TMP" ] && [ -f "$KT_MATCH_FILES_TMP" ]; then
    rm -f "$KT_MATCH_FILES_TMP" 2>/dev/null
  fi
  KT_MATCH_FILES_TMP=""
}

# Filter currently-matched files against a session ledger: drop any line whose
# path-part (text before " — ") appears in the ledger file. Updates the temp
# file in place and refreshes KT_MATCH_COUNT. No-op if ledger missing/empty
# or no current matches. Used by active-mode hooks to avoid re-surfacing the
# same file twice across triggers within one session.
kt_match_filter_ledger() {
  _kt_ledger="$1"
  [ -z "$_kt_ledger" ] && return 0
  [ ! -f "$_kt_ledger" ] && return 0
  [ ! -s "$_kt_ledger" ] && return 0
  [ -z "$KT_MATCH_FILES_TMP" ] && return 0
  [ ! -f "$KT_MATCH_FILES_TMP" ] && return 0

  _kt_filtered=$(mktemp /tmp/aria-match-filtered.XXXXXX) || return 0
  # awk: build a set of ledger paths, then emit only current-match lines whose
  # path-before-em-dash is not in the set. Ledger entries are bare paths
  # (one per line); current-match lines are "path — description".
  awk -F ' — ' '
    NR==FNR { seen[$0]=1; next }
    !($1 in seen) { print }
  ' "$_kt_ledger" "$KT_MATCH_FILES_TMP" > "$_kt_filtered"

  if [ -s "$_kt_filtered" ]; then
    mv "$_kt_filtered" "$KT_MATCH_FILES_TMP"
    KT_MATCH_COUNT=$(wc -l < "$KT_MATCH_FILES_TMP" | tr -d ' ')
  else
    rm -f "$_kt_filtered" 2>/dev/null
    rm -f "$KT_MATCH_FILES_TMP" 2>/dev/null
    KT_MATCH_FILES_TMP=""
    KT_MATCH_COUNT=0
  fi
}

# Append currently-matched paths (before " — ") to the session ledger. Creates
# parent directory if needed. Used by active-mode hooks after a successful
# surfacing, so subsequent triggers in the same session can dedup against it.
kt_match_record_ledger() {
  _kt_ledger="$1"
  [ -z "$_kt_ledger" ] && return 0
  [ -z "$KT_MATCH_FILES_TMP" ] && return 0
  [ ! -f "$KT_MATCH_FILES_TMP" ] && return 0
  awk -F ' — ' '{print $1}' "$KT_MATCH_FILES_TMP" >> "$_kt_ledger" 2>/dev/null
}
