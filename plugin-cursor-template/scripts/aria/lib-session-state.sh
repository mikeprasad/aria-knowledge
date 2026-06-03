#!/bin/sh
# lib-session-state.sh — helpers for deterministic SESSION.md in-progress marking.
#
# Cursor port: project root = nearest ancestor with AGENTS.md, CLAUDE.md, or PROGRESS.md.

kt_ss_find_root() {
  _ss_fp="$1"
  [ -z "$_ss_fp" ] && return 0
  if [ -d "$_ss_fp" ]; then _ss_dir="$_ss_fp"; else _ss_dir=$(dirname "$_ss_fp" 2>/dev/null); fi
  [ -z "$_ss_dir" ] && return 0
  _ss_home="${HOME:-/root}"
  while [ -n "$_ss_dir" ] && [ "$_ss_dir" != "/" ]; do
    if [ -f "$_ss_dir/AGENTS.md" ] || [ -f "$_ss_dir/CLAUDE.md" ] || [ -f "$_ss_dir/PROGRESS.md" ]; then
      if [ "$(dirname "$_ss_dir" 2>/dev/null)" = "$_ss_home" ]; then return 0; fi
      printf '%s\n' "$_ss_dir"
      return 0
    fi
    [ "$_ss_dir" = "$_ss_home" ] && return 0
    _ss_parent=$(dirname "$_ss_dir" 2>/dev/null)
    [ "$_ss_parent" = "$_ss_dir" ] && return 0
    _ss_dir="$_ss_parent"
  done
  return 0
}

kt_ss_mark_inprogress() {
  _ss_root="$1"; _ss_sid="$2"; _ss_author="$3"
  [ -z "$_ss_root" ] || [ ! -d "$_ss_root" ] && return 0
  _ss_file="$_ss_root/SESSION.md"
  _ss_now=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || _ss_now=""
  _ss_branch=$(git -C "$_ss_root" rev-parse --abbrev-ref HEAD 2>/dev/null) || _ss_branch=""
  _ss_head=$(git -C "$_ss_root" rev-parse --short HEAD 2>/dev/null) || _ss_head=""

  if [ -f "$_ss_file" ] && IFS= read -r _ss_first < "$_ss_file" && [ "$_ss_first" = "---" ]; then
    _ss_tmp="$_ss_file.$$.tmp"
    awk -v now="$_ss_now" -v br="$_ss_branch" -v hc="$_ss_head" -v sid="$_ss_sid" '
      BEGIN { infm = 0 }
      NR == 1 && $0 == "---" { infm = 1; print; next }
      infm == 1 && $0 == "---" {
        if (!sle) print "lastEvent: in-progress"
        if (!sat && now != "") print "at: " now
        if (!sbr && br != "") print "branch: " br
        if (!shc && hc != "") print "headCommit: " hc
        if (!ssid && sid != "") print "sessionId: " sid
        infm = 2; print; next
      }
      infm == 1 {
        if ($0 ~ /^lastEvent:/) { print "lastEvent: in-progress"; sle = 1; next }
        if ($0 ~ /^at:/)        { if (now != "") { print "at: " now } else print; sat = 1; next }
        if ($0 ~ /^branch:/)    { if (br != "")  { print "branch: " br } else print; sbr = 1; next }
        if ($0 ~ /^headCommit:/){ if (hc != "")  { print "headCommit: " hc } else print; shc = 1; next }
        if ($0 ~ /^sessionId:/) { if (sid != "") { print "sessionId: " sid } else print; ssid = 1; next }
        print; next
      }
      { print }
    ' "$_ss_file" > "$_ss_tmp" 2>/dev/null && mv "$_ss_tmp" "$_ss_file" 2>/dev/null
    rm -f "$_ss_tmp" 2>/dev/null
  else
    _ss_body=""
    if [ -f "$_ss_file" ]; then _ss_body=$(cat "$_ss_file" 2>/dev/null); fi
    {
      printf -- '---\n'
      printf 'lastEvent: in-progress\n'
      [ -n "$_ss_now" ] && printf 'at: %s\n' "$_ss_now"
      printf 'currentFocus: \n'
      printf 'nextAction: \n'
      [ -n "$_ss_branch" ] && printf 'branch: %s\n' "$_ss_branch"
      [ -n "$_ss_head" ] && printf 'headCommit: %s\n' "$_ss_head"
      [ -n "$_ss_author" ] && printf 'by: %s\n' "$_ss_author"
      [ -n "$_ss_sid" ] && printf 'sessionId: %s\n' "$_ss_sid"
      printf -- '---\n\n'
      if [ -n "$_ss_body" ]; then
        printf '%s\n' "$_ss_body"
      else
        printf '## Where we left off\n\n(session in progress)\n'
      fi
    } > "$_ss_file" 2>/dev/null
  fi

  if git -C "$_ss_root" rev-parse --git-dir >/dev/null 2>&1; then
    if ! git -C "$_ss_root" check-ignore -q SESSION.md 2>/dev/null; then
      printf 'SESSION.md\n' >> "$_ss_root/.gitignore" 2>/dev/null
    fi
  fi
  return 0
}
