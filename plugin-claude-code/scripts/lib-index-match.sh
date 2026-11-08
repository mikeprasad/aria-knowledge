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

  _kt_tab=$(printf '\t')
  _kt_raw=$(mktemp "${TMPDIR:-/tmp}/aria-match-raw.XXXXXX") || return 0

  # One pass over index.md, then rank in END. Output lines:
  #   T<TAB>matched tags (vocabulary order)
  #   C<TAB>k1<TAB>k2<TAB>k3<TAB>k4<TAB>k5<TAB>k6<TAB>path — description
  # Vocabulary = `### ` headers under `## Tag Index` ∪ projects_list tags.
  # File-listing sections are `## Tag Index` and `## Other Tags`; only
  # Tag Index sections make a file CARRY a tag, while a project tag also
  # carries every listed path under `projects/<tag>/` (either section).
  # Aliases: `tag [aliases: a, b]` or `tag [aliases: a b]` anywhere in
  # `## Known Tags`; an alias token is replaced by its canonical tag before
  # matching. An alias containing a character the tokenizer splits on
  # (e.g. a dot) can never match a token and is inert.
  _KT_WORDS="$_kt_words" _KT_TASK="$_kt_task" _KT_PROJECTS="$KT_PROJECTS_LIST" awk '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function pathof(l,   i) { i = index(l, " — "); return i ? substr(l, 1, i - 1) : l }
    BEGIN {
      nw = split(ENVIRON["_KT_WORDS"], W, " ")
      nt = split(ENVIRON["_KT_TASK"], T, " ")
      npl = split(ENVIRON["_KT_PROJECTS"], PL, ",")
      for (i = 1; i <= npl; i++) {
        c = index(PL[i], ":"); if (!c) continue
        t = tolower(trim(substr(PL[i], 1, c - 1)))
        if (t != "" && !(t in isproj)) { isproj[t] = 1; porder[++npo] = t }
      }
      sec = ""; tag = ""; known = ""; nv = 0; nl = 0
    }
    /^## / { sec = trim(substr($0, 4)); tag = ""; next }
    sec == "Known Tags" { known = known " " $0; next }
    /^### / {
      tag = ""
      if (sec == "Tag Index" || sec == "Other Tags") tag = tolower(trim(substr($0, 5)))
      if (sec == "Tag Index" && tag != "" && !(tag in hassec)) { hassec[tag] = 1; vorder[++nv] = tag }
      next
    }
    /^- / && (sec == "Tag Index" || sec == "Other Tags") {
      line = substr($0, 3); p = pathof(line)
      if (!(p in pos)) { pos[p] = ++nl; desc[p] = line }
      if (sec == "Tag Index" && tag != "" && !((tag SUBSEP p) in carries)) { carries[tag SUBSEP p] = 1; cnt[tag]++ }
      next
    }
    END {
      s = known
      while ((i = index(s, "[aliases:")) > 0) {
        pre = substr(s, 1, i - 1); rest = substr(s, i + 9)
        j = index(rest, "]"); if (!j) break
        list = substr(rest, 1, j - 1); s = substr(rest, j + 1)
        n = split(pre, pw, /[ ,`*\t]+/); canon = ""
        for (k = n; k >= 1; k--) if (pw[k] != "") { canon = tolower(pw[k]); break }
        if (canon == "") continue
        m = split(list, al, /[ ,\t]+/)
        for (k = 1; k <= m; k++) { a = tolower(al[k]); if (a != "" && !(a in alias)) alias[a] = canon }
      }

      for (i = 1; i <= nw; i++) {
        w = W[i]; if (w == "") continue
        c = w
        if (!(c in hassec) && !(c in isproj) && (w in alias)) c = alias[w]
        if ((c in hassec) || (c in isproj)) matched[c] = 1
      }
      out = ""; nm = 0; npm = 0
      for (i = 1; i <= nv; i++) { t = vorder[i]; if (t in matched) { out = out " " t; nm++; if (t in isproj) npm++ } }
      for (i = 1; i <= npo; i++) { t = porder[i]; if ((t in matched) && !(t in hassec)) { out = out " " t; nm++; npm++ } }
      # Firing: >=2 matched tags, OR >=1 matched project tag.
      if (nm < 2 && npm < 1) exit

      for (i = 1; i <= npo; i++) {
        t = porder[i]; if (!(t in matched)) continue
        pfx = "projects/" t "/"
        for (p in pos) if (index(p, pfx) == 1 && !((t SUBSEP p) in carries)) { carries[t SUBSEP p] = 1; cnt[t]++ }
      }

      printf "T\t%s\n", substr(out, 2)
      for (p in pos) {
        k2 = 0; k1 = 0; k5 = 0
        for (t in matched) if ((t SUBSEP p) in carries) {
          k2++; if (t in isproj) k1 = 1
          if (k5 == 0 || cnt[t] < k5) k5 = cnt[t]
        }
        if (!k2) continue
        x = tolower(desc[p]); gsub(/[^a-z0-9]+/, " ", x); x = " " x " "
        k3 = 0
        for (k = 1; k <= nt; k++) if (T[k] != "" && index(x, " " T[k] " ")) k3++
        k4 = (index(p, "logs/") == 1) ? 0 : 1
        printf "C\t%d\t%d\t%d\t%d\t%d\t%d\t%s\n", k1, k2, k3, k4, k5, pos[p], desc[p]
      }
    }
  ' "$_kt_index" > "$_kt_raw" 2>/dev/null

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
