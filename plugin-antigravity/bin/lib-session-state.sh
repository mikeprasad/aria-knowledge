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

# Returns 0 (true) if DIR is a workspace-index root that must NOT own a SESSION.md
# (it indexes multiple child projects rather than describing one). Two opt-in markers:
# a `.aria-workspace-root` sentinel file, or an `aria_workspace_root: true` line in CLAUDE.md.
kt_ss_is_workspace_root() {
  _ss_d="$1"
  [ -f "$_ss_d/.aria-workspace-root" ] && return 0
  [ -f "$_ss_d/CLAUDE.md" ] && grep -qE '^aria_workspace_root:[[:space:]]*true[[:space:]]*$' "$_ss_d/CLAUDE.md" 2>/dev/null && return 0
  return 1
}

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
      # Reject an explicit workspace-index root (a nested container like collab/ or
      # aria/ that indexes child projects); keep walking up toward the real root.
      # The walk starts at the edited file, so the first UNMARKED root is the deepest
      # one — the actual sub-project. A marked-only container yields empty (correct).
      if kt_ss_is_workspace_root "$_ss_dir"; then
        [ "$_ss_dir" = "$_ss_home" ] && return 0
        _ss_parent=$(dirname "$_ss_dir" 2>/dev/null)
        [ "$_ss_parent" = "$_ss_dir" ] && return 0
        _ss_dir="$_ss_parent"
        continue
      fi
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

  # Ensure SESSION.md is gitignored — but ONLY where that is actually wanted, and only
  # once. Four conditions, each closing a different hole:
  #
  #   1. `session_state_tracked` — the user's standing ruling. Workspace repos TRACK
  #      SESSION.md (it carries the decision trail); some sub-repos deliberately do not.
  #      v2.46.0 wired this knob into wrapup/SKILL.md and handoff/SKILL.md only; this
  #      library was a THIRD code path that never read it, so the ruling had no effect
  #      here. Read via `${VAR:-}` rather than the bare form the hooks use: those are
  #      entry points that always source config.sh first, whereas this is a *library* and
  #      must stay safe when sourced without it (see validation arm 4).
  #   2. is this even a git repo
  #   3. is SESSION.md TRACKED — if so, never touch .gitignore. An ignore rule is a
  #      NO-OP on an already-tracked path, so appending one achieves nothing except
  #      growing the file.
  #   4. is the line ALREADY present — idempotence.
  #
  # ⛔ `git check-ignore` CANNOT be the test, and was the bug. It consults the INDEX, so
  # for a TRACKED file it exits 1 ("not ignored") — which made the old negated guard
  # ALWAYS true. Measured 2026-08-17: it exits 1 for a tracked SESSION.md *even when
  # SESSION.md is already listed in .gitignore*, so the guard could never be satisfied
  # and this block appended one line per session forever. archetypes/.gitignore reached
  # 4 duplicate lines by 2026-08-14, was cleaned in 3a77b34 with an explicit DO-NOT-ADD
  # comment, and had accumulated 2 more directly beneath that warning by 08-16.
  # The plugin's own docs already prescribed the right test (`git ls-files
  # --error-unmatch`) at wrapup/SKILL.md:202, handoff/SKILL.md:241, setup/SKILL.md:202.
  # Keep this comment: without it the next reader reintroduces check-ignore.
  if [ "${KT_SESSION_STATE_TRACKED:-}" != "true" ] \
     && git -C "$_ss_root" rev-parse --git-dir >/dev/null 2>&1 \
     && ! git -C "$_ss_root" ls-files --error-unmatch SESSION.md >/dev/null 2>&1 \
     && ! grep -qxF 'SESSION.md' "$_ss_root/.gitignore" 2>/dev/null; then
    printf 'SESSION.md\n' >> "$_ss_root/.gitignore" 2>/dev/null
  fi
  return 0
}

# --- Multi-session ledger (## Prior sessions) ---------------------------------
# The active session lives in the front-matter + "## Next session prompt" (atlas's
# single view). Demoted/prior sessions live under a "## Prior sessions" heading,
# which the atlas parser ignores (it stops at the first "## " after the prompt).
# All three helpers write via temp-file + mv and swallow errors (return 0).

# Prepend a ### block under "## Prior sessions" (created if absent). Newest-first.
kt_ss_ledger_add() {
  _ss_f="$1/SESSION.md"; _ss_sid="$2"; _ss_at="$3"; _ss_focus="$4"; _ss_next="$5"; _ss_prompt="$6"
  [ -f "$_ss_f" ] || return 0
  _ss_blk="### $_ss_sid · $_ss_at · handoff · unconsumed
- focus: $_ss_focus
- next: $_ss_next
- prompt:
$_ss_prompt
<!-- aria:entry-end -->
"
  _ss_tmp="$_ss_f.$$.tmp"
  # Grandfathering: an existing legacy '## Prior sessions' heading keeps receiving entries
  # so old files are never orphaned; anything new lands under '## Pending handoffs'.
  if grep -q '^## Pending handoffs$' "$_ss_f" 2>/dev/null; then
    _ss_head_re='^## Pending handoffs$'
  elif grep -q '^## Prior sessions$' "$_ss_f" 2>/dev/null; then
    _ss_head_re='^## Prior sessions$'
  else
    _ss_head_re=''
  fi
  if [ -n "$_ss_head_re" ]; then
    # Insert the block immediately after the heading line (newest-first). Split the
    # file at the heading via awk (single-zone: head = through the heading + a blank
    # line; tail = the rest), then reassemble with the block via printf — NEVER pass
    # the multi-line block through awk -v (POSIX awk errors on "newline in string").
    _ss_head="$_ss_f.$$.head"; _ss_tail="$_ss_f.$$.tail"
    # head = lines through the "## Prior sessions" heading + one blank; tail = the rest.
    # The block is injected between head and tail by printf (not awk -v).
    awk -v hre="$_ss_head_re" 'BEGIN{z=0}
      z==1 {print > t; next}
      {print > h}
      $0 ~ hre && z==0 {print "" > h; z=1}
    ' h="$_ss_head" t="$_ss_tail" "$_ss_f" 2>/dev/null
    { cat "$_ss_head" 2>/dev/null; printf '%s' "$_ss_blk"; cat "$_ss_tail" 2>/dev/null; } > "$_ss_tmp" 2>/dev/null && mv "$_ss_tmp" "$_ss_f" 2>/dev/null
    rm -f "$_ss_head" "$_ss_tail" 2>/dev/null
  else
    # append a new heading + block at EOF. '## Pending handoffs' is deliberate: these are
    # still-valid prompts awaiting use, not history -- naming them "prior" is what made a
    # writer read demotion as a downgrade and skip rather than demote.
    { cat "$_ss_f"; printf '\n## Pending handoffs\n\n%s' "$_ss_blk"; } > "$_ss_tmp" 2>/dev/null && mv "$_ss_tmp" "$_ss_f" 2>/dev/null
  fi
  rm -f "$_ss_tmp" 2>/dev/null
  return 0
}

# Flip "### <SID> … · unconsumed" to "· consumed <TS> by <BY>" for the named session only.
kt_ss_ledger_mark_consumed() {
  _ss_f="$1/SESSION.md"; _ss_sid="$2"; _ss_ts="$3"; _ss_by="$4"
  [ -f "$_ss_f" ] || return 0
  _ss_tmp="$_ss_f.$$.tmp"
  awk -v sid="$_ss_sid" -v ts="$_ss_ts" -v by="$_ss_by" '
    $0 ~ ("^### " sid " ") && /· unconsumed$/ {
      sub(/· unconsumed$/, "· consumed " ts " by " by); print; next
    }
    { print }
  ' "$_ss_f" > "$_ss_tmp" 2>/dev/null && mv "$_ss_tmp" "$_ss_f" 2>/dev/null
  rm -f "$_ss_tmp" 2>/dev/null
  return 0
}

# Remove every ### block whose header carries a "· consumed " token.
#
# BOUNDARIES ARE DECLARED, NOT INFERRED. Each block written by kt_ss_ledger_add ends with an
# explicit `<!-- aria:entry-end -->` line, so prune never has to guess where a block stops.
# That is load-bearing: a stored prompt is kept at FULL fidelity (a still-valid handoff must
# not be degraded), and real openers contain column-0 "## " lines. The previous version reset
# `drop` on /^## /, so a consumed block containing such a line lost its boundary and leaked
# its tail into the file — reproduced, not theorised. Fence-tracking cannot substitute here,
# because an opener may itself contain nested ``` fences.
#
# Legacy files (written before terminators existed) carry single-line prompts by the old
# invariant, so a column-0 "## " inside one is impossible and the old inference is still
# sound for them. A first pass detects which format the file is in and picks the matching
# rule, so old and new files both prune correctly.
kt_ss_ledger_prune() {
  _ss_f="$1/SESSION.md"
  [ -f "$_ss_f" ] || return 0
  _ss_tmp="$_ss_f.$$.tmp"
  awk '
    # pass 1: does this file use explicit terminators?
    NR == FNR { if ($0 == "<!-- aria:entry-end -->") term = 1; next }

    # pass 2 — terminator format: boundaries are the header and the terminator only.
    term {
      if ($0 ~ /^### /) { drop = ($0 ~ /· consumed /) ? 1 : 0; if (drop) next; print; next }
      if ($0 == "<!-- aria:entry-end -->") { if (drop) { drop = 0; next } print; next }
      if (!drop) print
      next
    }

    # pass 2 — legacy format: prompts are single-line, so "## " inference is safe.
    /^### / { drop = ($0 ~ /· consumed /) ? 1 : 0; if (drop) next }
    /^## / && $0 !~ /^### / { drop = 0 }
    { if (!drop) print }
  ' "$_ss_f" "$_ss_f" > "$_ss_tmp" 2>/dev/null && mv "$_ss_tmp" "$_ss_f" 2>/dev/null
  rm -f "$_ss_tmp" 2>/dev/null
  return 0
}

# Echo the active sessionId from ROOT/SESSION.md front-matter (empty if none).
# Scans only the first --- ... --- block; stops at the closing fence.
kt_ss_read_active_sid() {
  _ss_f="$1/SESSION.md"
  [ -f "$_ss_f" ] || return 0
  awk 'NR==1 && $0!="---"{exit} /^---$/ && NR>1{exit} /^sessionId:[[:space:]]*/{sub(/^sessionId:[[:space:]]*/,""); print; exit}' "$_ss_f" 2>/dev/null
  return 0
}
