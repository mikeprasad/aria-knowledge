#!/bin/sh
# lib-session-state.sh — helpers for deterministic SESSION.md in-progress marking.
#
# Sourced by post-edit-check.sh (PostToolUse Edit|Write) to mark a project's
# SESSION.md as lastEvent: in-progress on the first edit of a session, WITHOUT
# relying on Claude executing a soft SessionStart instruction (v2.22.0's approach,
# which proved unreliable). Project is derived from the EDITED FILE PATH, so this
# works even when the session's cwd is the ~/Projects root.
#
# Functions:
#   kt_ss_find_root FILE_PATH            -> echoes nearest ancestor dir containing
#                                           CLAUDE.md or PROGRESS.md (the project
#                                           root), or empty if none below $HOME / /.
#   kt_ss_mark_inprogress ROOT SID [AUTHOR]
#                                        -> light-touch, idempotent write of
#                                           ROOT/SESSION.md to lastEvent: in-progress.
#                                           Preserves body + currentFocus/nextAction/by.
#
# All operations are fail-safe: any error is swallowed so the host hook never
# blocks an edit or errors out.
#
# Contract conformance: the SESSION.md shape written here is pinned to the canonical
# fixtures at tests/fixtures/session-contract-vendored/ (owned by aria-atlas); see
# that dir's VENDORED-FROM.md, and tests/repros/session-state.sh §H which asserts it.

# Walk up from the edited file's directory to the nearest project root.
kt_ss_find_root() {
  _ss_fp="$1"
  [ -z "$_ss_fp" ] && return 0
  # Start at the file's directory (or the path itself if it's already a dir).
  if [ -d "$_ss_fp" ]; then _ss_dir="$_ss_fp"; else _ss_dir=$(dirname "$_ss_fp" 2>/dev/null); fi
  [ -z "$_ss_dir" ] && return 0
  _ss_home="${HOME:-/root}"
  while [ -n "$_ss_dir" ] && [ "$_ss_dir" != "/" ]; do
    if [ -f "$_ss_dir/CLAUDE.md" ] || [ -f "$_ss_dir/PROGRESS.md" ]; then
      # Reject the top-level projects container — a direct child of $HOME (e.g.
      # ~/Projects) whose CLAUDE.md is the master index, not a project. Marking it
      # would write a spurious root SESSION.md. Real projects live inside it.
      if [ "$(dirname "$_ss_dir" 2>/dev/null)" = "$_ss_home" ]; then return 0; fi
      printf '%s\n' "$_ss_dir"
      return 0
    fi
    # Stop once we pass above $HOME (don't mark the home dir or above).
    [ "$_ss_dir" = "$_ss_home" ] && return 0
    _ss_parent=$(dirname "$_ss_dir" 2>/dev/null)
    [ "$_ss_parent" = "$_ss_dir" ] && return 0
    _ss_dir="$_ss_parent"
  done
  return 0
}

# Idempotent light-touch in-progress write. Safe to call repeatedly.
kt_ss_mark_inprogress() {
  _ss_root="$1"; _ss_sid="$2"; _ss_author="$3"
  [ -z "$_ss_root" ] || [ ! -d "$_ss_root" ] && return 0
  _ss_file="$_ss_root/SESSION.md"
  _ss_now=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || _ss_now=""
  _ss_branch=$(git -C "$_ss_root" rev-parse --abbrev-ref HEAD 2>/dev/null) || _ss_branch=""
  _ss_head=$(git -C "$_ss_root" rev-parse --short HEAD 2>/dev/null) || _ss_head=""

  if [ -f "$_ss_file" ] && IFS= read -r _ss_first < "$_ss_file" && [ "$_ss_first" = "---" ]; then
    # Existing parseable header: refresh keys in the first frontmatter block,
    # append any missing override keys before the closing fence, preserve body.
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
    # No file, or unparseable header: write a fresh minimal in-progress header.
    # If a file existed without a header, preserve its content as the body.
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

  # Ensure SESSION.md is gitignored (ephemeral per-session state, never committed).
  if git -C "$_ss_root" rev-parse --git-dir >/dev/null 2>&1; then
    if ! git -C "$_ss_root" check-ignore -q SESSION.md 2>/dev/null; then
      printf 'SESSION.md\n' >> "$_ss_root/.gitignore" 2>/dev/null
    fi
  fi
  return 0
}
