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
    # ⛔ The sle/sat/sbr/shc/ssid flags are TESTED, not merely set. Without the test, every
    # matching line in the first frontmatter block was rewritten, not just the first — so a
    # block carrying STACKED entries (which unioning SESSION.md across a branch merge
    # produces: measured on a real repo, at/branch/headCommit/sessionId all x3) had every
    # entry collapsed to the current session on the first edit. 11 of 11 provenance values
    # destroyed, silently. Entry 1 is the current state and is refreshed; 2..N are history
    # and are preserved verbatim.
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
        if ($0 ~ /^lastEvent:/) { if (!sle) print "lastEvent: in-progress"; else print; sle = 1; next }
        if ($0 ~ /^at:/)        { if (!sat && now != "") { print "at: " now } else print; sat = 1; next }
        if ($0 ~ /^branch:/)    { if (!sbr && br != "")  { print "branch: " br } else print; sbr = 1; next }
        if ($0 ~ /^headCommit:/){ if (!shc && hc != "")  { print "headCommit: " hc } else print; shc = 1; next }
        if ($0 ~ /^sessionId:/) { if (!ssid && sid != "") { print "sessionId: " sid } else print; ssid = 1; next }
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
  # and this block appended one line per session forever. One observed project's
  # .gitignore reached 4 duplicate lines by 2026-08-14, was cleaned with an explicit
  # DO-NOT-ADD comment, and had accumulated 2 more directly beneath that warning
  # two days later.
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
  _ss_blkf="$_ss_f.$$.blk"

  # RC-3: skip ONLY a byte-identical block. There was no idempotency guard at all before this.
  #
  # ⛔⛔ THE KEY IS THE BLOCK, NEVER `(sessionId, at)`. That pair is NOT a handoff's identity, and a
  # guard keyed on it DISCARDS REAL CONTENT from the one function whose contract is that a stored
  # prompt is kept at FULL fidelity. Measured on a real ledger: the pair
  # `8d107131 · 2026-09-06T11:06:25Z` was TWO DIFFERENT 54-line bodies in the single commit that
  # created it, differing in one prompt line; and a second pair's sid is recorded in the file itself
  # as "a HOOK ARTIFACT, not attribution — post-edit-check.sh stamped session 1cabb22b onto this
  # entry's front-matter". So the key can hold a value a HOOK wrote rather than the author.
  # ⇒ A key collision carrying a DIFFERING body is WRITTEN, and reported at the read boundary. Only
  # an exact re-run is skipped, and a byte-identical skip has nothing to report.
  #
  # ⛔ THE EMPTY-BLOCK GUARD MUST BE THE SHELL `[ -s ]` TEST BELOW — an in-awk `bn == 0` branch is
  # STRUCTURALLY DEAD and must not be added. With an empty first file awk reads no records from it,
  # so NR == FNR is TRUE for the TARGET's first record and the block array fills FROM THE TARGET:
  # measured `bn=8079, tn=0`, never `bn=0`. A no-guard control returns the identical exit code,
  # proving such a branch changes nothing.
  #
  # The block reaches awk as a FILE, never via `awk -v` — POSIX awk errors on "newline in string".
  printf '%s' "$_ss_blk" > "$_ss_blkf" 2>/dev/null
  if [ -s "$_ss_blkf" ] && awk '
      NR == FNR { b[++bn] = $0; next }
                { L[FNR] = $0; tn = FNR }
      END {
        for (i = 1; i <= tn - bn + 1; i++) {
          ok = 1
          for (j = 1; j <= bn; j++) if (L[i + j - 1] != b[j]) { ok = 0; break }
          if (ok) exit 0
        }
        exit 1
      }' "$_ss_blkf" "$_ss_f" 2>/dev/null; then
    rm -f "$_ss_blkf" 2>/dev/null
    return 0
  fi
  rm -f "$_ss_blkf" 2>/dev/null
  # Grandfathering: an existing legacy '## Prior sessions' heading keeps receiving entries
  # so old files are never orphaned; anything new lands under '## Pending handoffs'.
  # RC-2: resolve the anchor ONCE, tolerantly, to a LINE NUMBER + canonical family name.
  #
  # ⛔ THE OLD FORM WAS `grep -q '^## Pending handoffs$'` AND THAT EXACT ANCHOR WAS THE DEFECT.
  # One trailing space defeats it, detection fails, and the else-branch below appends a SECOND
  # '## Pending handoffs' section at EOF — below every '## Archived' heading. Reproduced 2026-09-08
  # on a copy of an 8k-line ledger: the new entry landed at EOF while the real section sat at L141.
  # That one line explains three separately-catalogued findings: competing ledger sections, a block
  # "marooned below the archive sections", and much of a 42-entry invisibility.
  #
  # Collapsing detection and splice into ONE decision (a line number) removes the class where
  # `grep -q` says yes and the splice `awk` targets something else.
  #
  # ⛔ TOLERANCE IS A CLOSED SET, NOT A LOOSE REGEX — whitespace, bold markers, case, and heading
  # level. Deliberately NOT arbitrary trailing content: the paired write below canonicalises what
  # this accepts, so accepting '## Pending handoffs — superseded' would REWRITE it and destroy
  # information. Never loosen a read further than its paired write can safely canonicalise.
  #
  # ⛔ PENDING IS SCANNED FIRST OVER THE WHOLE FILE, THEN PRIOR — preserving the old if/elif
  # precedence. A single first-match scan would let a '## Prior sessions' high in the file beat a
  # '## Pending handoffs' lower down. Measured latent (0 of 18 ledgers carry both spellings), but
  # an unmeasured behaviour change riding inside a fix for a different defect is its own defect.
  _ss_anchor=$(awk '
    function norm(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); gsub(/[*]/, "", s); return tolower(s) }
    { L[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) { s = norm(L[i]); if (s == "## pending handoffs" || s == "### pending handoffs") { print i "|Pending handoffs"; exit } }
      for (i = 1; i <= NR; i++) { s = norm(L[i]); if (s == "## prior sessions"   || s == "### prior sessions")   { print i "|Prior sessions";   exit } }
    }' "$_ss_f" 2>/dev/null)
  _ss_ln=${_ss_anchor%%|*}
  _ss_can=${_ss_anchor#*|}
  if [ -n "$_ss_ln" ]; then
    # Insert the block immediately after the heading line (newest-first). Split the
    # file at the heading via awk (single-zone: head = through the heading + a blank
    # line; tail = the rest), then reassemble with the block via printf — NEVER pass
    # the multi-line block through awk -v (POSIX awk errors on "newline in string").
    _ss_head="$_ss_f.$$.head"; _ss_tail="$_ss_f.$$.tail"
    # head = lines through the "## Prior sessions" heading + one blank; tail = the rest.
    # The block is injected between head and tail by printf (not awk -v).
    # Splice by LINE NUMBER, and CANONICALISE the heading in the same pass — the PAIRED WRITE.
    #
    # ⛔ THE PAIRED WRITE IS LOAD-BEARING, NOT COSMETIC. A tolerant read that leaves a non-canonical
    # heading in place is strictly worse than the bug it replaces: the read-boundary checker's parent
    # test is an EXACT comparison, so every entry under '## Pending handoffs ' would flip to
    # "misparented" and the checker would go RED *because of* this fix. A loosened match whose paired
    # write stays anchored to the old shape is the shape where every cheap signal reports success and
    # nothing changes on disk.
    #
    # ⛔ CANONICALISE WITHIN THE MATCHED FAMILY, NEVER ACROSS IT. '## Prior sessions' is deliberate
    # grandfathering with live subjects; converting it to '## Pending handoffs' would orphan them.
    # `$_ss_can` carries the family, so this cannot cross.
    awk -v n="$_ss_ln" -v can="## $_ss_can" '
      FNR <  n { print     > h; next }
      FNR == n { print can > h; print "" > h; next }
               { print     > t }
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
  _ss_f="$1/SESSION.md"; _ss_sid="$2"; _ss_ts="$3"; _ss_by="$4"; _ss_want_at="$5"
  [ -f "$_ss_f" ] || return 0
  _ss_tmp="$_ss_f.$$.tmp"
  # THREE things matter here and they are interlocking; changing one alone reintroduces the bug.
  #
  # 1. The header match is `^### .*<sid>`, not `^### <sid> `. Entries are hand-written as well as
  #    generated — measured 2026-08-27, 2 of 25 real headers on one machine carry a parenthetical
  #    after the sid — and the anchored form silently matched nothing for a backticked sid.
  # 2. The status test is WORD-BOUNDED, not end-of-line anchored, so a trailing ` · title` or a bold
  #    `**unconsumed**` is still recognised.
  # 3. ⛔ THE WRITE REPLACES THE WORD, NOT THE ANCHORED PHRASE. This is the edit that is easy to omit
  #    and it is the one that matters: measured with 1 and 2 applied but not 3, bold and
  #    trailing-title headers MATCHED and were NEVER REWRITTEN — so instrumentation and review both
  #    read "handled" while the file was unchanged. That is the same silent no-op as the original
  #    bug, moved one layer in, and it is strictly worse because it now looks correct.
  #
  # ⚠ Word-bounding is what keeps this safe in the other direction: `unconsumed` does NOT match
  # /(^|[^a-z])consumed([^a-z]|$)/ because the `c` is preceded by `n`. prune depends on that.
  # ⚠ NOT closed, deliberately: a header carrying a TRUNCATED sid while the caller passes the full
  # one is matched by neither form — the full sid is not present in the line at all, so no loosening
  # of this pattern reaches it. Prefix matching could mark the WRONG entry, so it stays out.
  # ⛔ index(), NOT a regex. The old form was `$0 ~ ("^### .*" sid)`, which interpolated the caller's
  # sid into an awk REGEX unescaped. Two failure directions, both measured:
  #   under-match: sid `x[1]` is a character class, so it matches the string "x1" and leaves the
  #                entry whose sid is literally `x[1]` unmarked;
  #   OVER-match:  sid `a.c` matches the UNRELATED entry `abc` -- marking another session's handoff
  #                consumed. That is the dangerous direction and it was reachable today.
  # The live legacy sid `e95b0202 (contract-coherence)` matched only BY LUCK: its parentheses form a
  # group matching the same literal.
  #
  # ⛔ index() ON FIELD 1, NOT `==`. The loose match is deliberate and documented above -- headers are
  # hand-written too, and carry backticks or a trailing parenthetical around the sid. Strict equality
  # would regress every one of those. index() is a LITERAL substring search: it removes the regex
  # without removing the tolerance.
  #
  # ⛔ `at` (5th arg) IS OPTIONAL. Omitted => legacy behaviour, every entry for that sid marks --
  # guarded by S4, because making it mandatory-in-effect would silently change the recall of
  # post-edit-check.sh, whose entry was demoted with whatever `at` was current THEN. Supplied => an
  # exact (sid, at) match, which is what one sid under two timestamps needs.
  awk -v sid="$_ss_sid" -v ts="$_ss_ts" -v by="$_ss_by" -v want_at="$_ss_want_at" '
    /^### / {
      _nf = split(substr($0, 5), _f, " · ")
      _hsid = _f[1]; _hat = (_nf >= 2 ? _f[2] : "")
    }
    /^### / && index(_hsid, sid) > 0 && (want_at == "" || _hat == want_at) && /(^|[^a-z])unconsumed([^a-z]|$)/ {
      sub(/unconsumed/, "consumed " ts " by " by); print; next
    }
    { print }
  ' "$_ss_f" > "$_ss_tmp" 2>/dev/null && mv "$_ss_tmp" "$_ss_f" 2>/dev/null
  rm -f "$_ss_tmp" 2>/dev/null
  return 0
}

# Flip "### <SID> … · unconsumed" to "· consumed <TS> by <BY> (superseded)" for the named session.
#
# ⛔ WHY THIS EXISTS — the D3 defect, closed 2026-09-14. Before it, a human who wanted to retire an
# entry that was never "consumed" by a resuming session had no sanctioned verb, so they hand-typed a
# status: `superseded`, `complete`, `⛔ RETIRED`. That free text broke BOTH layers at once —
#   · `kt_ss_ledger_prune` reaps only a word-bounded `consumed`, so the entry was UNPRUNABLE and
#     accumulated forever (a real ledger reached 7,958 lines partly this way); and
#   · the reader (`tools/check-session-ledger.py`) classified anything not `consumed` as LIVE, so
#     deleting one by hand was reported as a DESTROYED HANDOFF. Measured 2026-09-12: 24 correctly
#     dispositioned entries produced 23 false "structural damage" findings. The cost is not the
#     noise — it is alarm fatigue on the one detector that catches real handoff loss.
#
# ⛔ THE EMITTED TOKEN CONTAINS THE WORD `consumed` ON PURPOSE. Do not "improve" this to emit a
# bare `superseded`. Two reasons, both measured:
#   1. `prune` must reap it. Its predicate is /(^|[^a-z])consumed([^a-z]|$)/ — a bare `superseded`
#      matches NEITHER prune nor mark_consumed, which is exactly the stuck-forever half of D3.
#      Teaching prune a second word would mean two predicates to keep in sync across the ports.
#   2. It must NOT re-match mark_consumed's `unconsumed` matcher, and it does not — verified
#      two-sided: this token → prune YES / mark_consumed NO; plain `unconsumed` → the inverse.
#
# ⛔ NO FREE-TEXT REASON IN THE HEADER — the reason belongs in the entry BODY. The header is a
# machine-parsed ` · `-delimited field, and putting unstructured text there is the defect this
# function closes; a remedy that emits free text into the same field reproduces it. (Caught by the
# pre-mortem on this change: the first draft appended `(superseded: <reason>)`.)
#
# Shape is mirrored from kt_ss_ledger_mark_consumed above — the same three interlocking properties
# apply here verbatim, and the comment block there is the canonical explanation of why.
kt_ss_ledger_mark_superseded() {
  _ss_f="$1/SESSION.md"; _ss_sid="$2"; _ss_ts="$3"; _ss_by="$4"
  [ -f "$_ss_f" ] || return 0
  _ss_tmp="$_ss_f.$$.tmp"
  awk -v sid="$_ss_sid" -v ts="$_ss_ts" -v by="$_ss_by" '
    $0 ~ ("^### .*" sid) && /(^|[^a-z])unconsumed([^a-z]|$)/ {
      sub(/unconsumed/, "consumed " ts " by " by " (superseded)"); print; next
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
# The receipts file. Durable and OUTSIDE every repo on purpose: SESSION.md is git-TRACKED in 8
# repos, so a sibling receipts file would mean per-repo gitignore churn and an untracked stray in a
# tracked tree — the shape that gets committed by accident. TMPDIR was also rejected: the gap this
# closes spans a wrapup (session N) to a SessionStart (session N+1), which TMPDIR need not survive.
KT_SS_RECEIPTS="${KT_SS_RECEIPTS:-$HOME/.gemini/antigravity/session-ledger-receipts}"

kt_ss_ledger_prune() {
  _ss_f="$1/SESSION.md"
  [ -f "$_ss_f" ] || return 0
  _ss_tmp="$_ss_f.$$.tmp"
  # ⛔ RECEIPTS — read the census BEFORE, compare AFTER, append only once the mv has succeeded.
  #
  # WHY IT IS OUT HERE AND NOT INSIDE THE awk. The awk below is a two-pass filter whose STDOUT IS
  # THE NEW FILE, guarded by `... > tmp 2>/dev/null && mv tmp file`. A receipt write inside it would
  # put the receipt path into prune own failure path: a write that fails makes awk exit non-zero,
  # the && short-circuits, mv never runs, and because stderr is discarded PRUNE SILENTLY STOPS
  # PRUNING. A fix for a data-loss detector must never be able to disable the thing it monitors.
  #
  # WHY BEFORE-MINUS-AFTER AND NOT "headers carrying a terminal token". Those two sets are NOT the
  # same: the hasterm and "## "-reset branches below mean some marked entries are deliberately not
  # reaped. A receipt naming an entry that SURVIVED would later suppress a genuine loss report for
  # it. The difference between the sets is exactly where that bug would live, so the receipt is
  # derived from what the operation DID, never from what it was likely to do.
  #
  # A receipt is ADVISORY: it can only ever SUPPRESS a loss finding for an id it names. It can never
  # create one. So a missing, truncated or corrupt receipts file degrades to the behaviour we had
  # before it existed — a false positive — and never to a missed destruction. Do not trade that away.
  _ss_before="$(grep '^### ' "$_ss_f" 2>/dev/null || true)"
  # A "### " line is an ENTRY HEADER only if it carries >= 2 " · " separators. Everything else at
  # column 0 inside an open block is CONTENT and is dropped with the block.
  #
  # ⛔⛔ DO NOT "SIMPLIFY" THIS TO AN UNCONDITIONAL `if (drop) next`. Measured 2026-08-27 on fixtures:
  # the unconditional form closes the inner-"### " leak AND swallows a LIVE handoff whenever a
  # consumed block lacks a terminator, because this reset is the only recovery path in that case —
  # one fixture was reduced to its bare "## Pending handoffs" heading. It trades a bounded 2-line leak
  # for unbounded deletion, which is the same class of harm as demoting over a live pickup.
  # ⚠ And it PASSES a leak-only fixture, so tests/repros/session-state.sh carries M9c specifically to
  # fail it. If M9c is ever deleted, this comment is the only thing left standing between the two.
  #
  # ⛔ The threshold is MEASURED, not chosen: across all 28 column-0 "### " lines in all 80 SESSION.md
  # on one machine, 25/25 real entry headers carry >= 3 separators and 3/3 prose headings carry 0.
  # A token-shape test was tried first and FAILED on 2 of 25 (a parenthetical after the sid).
  # ⚑ Failure direction is safe: a prose heading with >= 2 separators degrades to the old bounded
  # leak, never to deletion.
  #
  # The status test is word-bounded for the same reason as mark_consumed's, and this is where that
  # matters most: a naive /consumed/ ALSO matches `unconsumed`, which would make prune delete live
  # handoffs. `unconsumed` fails /(^|[^a-z])consumed([^a-z]|$)/ because the `c` is preceded by `n`.
  awk '
    function is_entry_header(s, n) { n = gsub(/ · /, " · ", s); return (n >= 2) }

    # pass 1: does this file use explicit terminators, and which entries actually HAVE one?
    # hasterm[] is keyed on the line number of the entry header, so pass 2 can tell a block with
    # a declared end from a block without one. The span closes only at a WELL-FORMED entry header,
    # never at a bare column-0 "## " -- closing at any heading is fence-blind, so a "## " inside a
    # stored prompt would mark a TERMINATED entry as unterminated and re-arm the recovery branch
    # below inside the prompt. Measured 2026-09-09 on fixtures: that form LEAKS.
    NR == FNR {
      if ($0 ~ /^### / && is_entry_header($0)) cur = FNR
      else if ($0 == "<!-- aria:entry-end -->") { term = 1; if (cur) hasterm[cur] = 1; cur = 0 }
      next
    }

    # pass 2 — terminator format: boundaries are an entry header and the terminator only.
    term {
      if ($0 ~ /^### / && is_entry_header($0)) {
        drop = ($0 ~ /(^|[^a-z])consumed([^a-z]|$)/) ? 1 : 0
        opened = FNR
        if (drop) next
        print; next
      }
      if ($0 == "<!-- aria:entry-end -->") { if (drop) { drop = 0; next } print; next }
      # RECOVERY, and it is SCOPED ON PURPOSE. An unterminated consumed block has no declared
      # end, so a section heading is the only boundary left; without this, such a block swallows
      # the next "## " heading and everything under it -- measured, 16 lines to 9 on a fixture,
      # and this is the class that deleted two unconsumed handoffs on 2026-09-04.
      # !hasterm[opened] is what keeps this from being the old unconditional reset that LEAKED:
      # a block that HAS a terminator keeps declared boundaries, so a "## " inside its stored
      # prompt cannot close it early. Removing that one clause makes the leak fixture leak.
      if (drop && !hasterm[opened] && $0 ~ /^## / && $0 !~ /^### /) { drop = 0; print; next }
      if (!drop) print
      next
    }

    # pass 2 — legacy format: prompts are single-line, so "## " inference is safe. The header
    # inference stays as-is here (the only boundary mechanism this format has); only the status test
    # gains the word boundary, so a legacy bold `**consumed**` entry prunes too.
    /^### / { drop = ($0 ~ /(^|[^a-z])consumed([^a-z]|$)/) ? 1 : 0; if (drop) next }
    /^## / && $0 !~ /^### / { drop = 0 }
    { if (!drop) print }
  ' "$_ss_f" "$_ss_f" > "$_ss_tmp" 2>/dev/null && mv "$_ss_tmp" "$_ss_f" 2>/dev/null
  rm -f "$_ss_tmp" 2>/dev/null

  # ── Receipt epilogue. Everything below is best-effort and swallows its own failures: the prune
  # has ALREADY happened and committed by this point, so nothing here can undo or prevent it.
  _ss_abs="$(cd "$1" 2>/dev/null && pwd)/SESSION.md"
  _ss_after="$(grep '^### ' "$_ss_f" 2>/dev/null || true)"
  _ss_rdir="$(dirname "$KT_SS_RECEIPTS")"
  # ⛔ GUARD ON WRITABILITY, do not just add another 2>/dev/null. When a REDIRECTION fails the SHELL
  # reports it, not the command, so `>> "$path" 2>/dev/null` still prints "no such file or
  # directory" — measured. prune runs inside hooks, where stray stderr is noise in every session.
  if [ "$_ss_before" != "$_ss_after" ] && mkdir -p "$_ss_rdir" 2>/dev/null && [ -w "$_ss_rdir" ]; then
    # Reaped = present before, absent after. comm needs sorted input; the header text is the key.
    printf '%s\n' "$_ss_before" | sort > "$_ss_tmp.b" 2>/dev/null || true
    printf '%s\n' "$_ss_after"  | sort > "$_ss_tmp.a" 2>/dev/null || true
    # Field 1 is "### <sid>", field 2 is the timestamp — emit "<abs>|<sid>|<ts>", the same
    # sid|ts key shape the reader already builds, so it compares like with like.
    comm -23 "$_ss_tmp.b" "$_ss_tmp.a" 2>/dev/null \
      | awk -F' · ' -v p="$_ss_abs" 'NF>=2 { s=$1; sub(/^### +/,"",s); print p "|" s "|" $2 }' \
      >> "$KT_SS_RECEIPTS" 2>/dev/null || true
    rm -f "$_ss_tmp.b" "$_ss_tmp.a" 2>/dev/null
    # Bound growth at the WRITER — the reader is read-only by design and must never truncate this.
    if [ -f "$KT_SS_RECEIPTS" ]; then
      _ss_n="$(wc -l < "$KT_SS_RECEIPTS" 2>/dev/null | tr -d ' ')"
      case "$_ss_n" in ''|*[!0-9]*) _ss_n=0 ;; esac
      if [ "$_ss_n" -gt 500 ]; then
        tail -n 500 "$KT_SS_RECEIPTS" > "$KT_SS_RECEIPTS.$$.trim" 2>/dev/null \
          && mv "$KT_SS_RECEIPTS.$$.trim" "$KT_SS_RECEIPTS" 2>/dev/null
        rm -f "$KT_SS_RECEIPTS.$$.trim" 2>/dev/null
      fi
    fi
  fi
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

# Read the ACTIVE front-matter `at:`. Sibling of kt_ss_read_active_sid -- same guard, same
# front-matter walk, same `return 0`; only the key differs. Deliberately a sibling rather than a
# parameterised kt_ss_read_front_matter: two call sites do not earn a generalised reader, and the
# sibling shape is what every caller in this file already reads like.
kt_ss_read_active_at() {
  _ss_f="$1/SESSION.md"
  [ -f "$_ss_f" ] || return 0
  awk 'NR==1 && $0!="---"{exit} /^---$/ && NR>1{exit} /^at:[[:space:]]*/{sub(/^at:[[:space:]]*/,""); print; exit}' "$_ss_f" 2>/dev/null
  return 0
}

# Is the SESSION.md at $1 owned by a session whose state is STRICTLY NEWER than $2?
#
#   exit 0  -> incumbent IS newer   => the caller MUST NOT rewrite the front matter.
#                                      Self-demote instead: kt_ss_ledger_add your own prompt into
#                                      `## Pending handoffs` and leave the active slot alone.
#   exit 1  -> anything else        => the caller rewrites exactly as it does today.
#
# ⛔ EVERY AMBIGUOUS INPUT RETURNS 1, and the direction is load-bearing. A brand-new guard must not
# be able to BLOCK a write that works today; the damage it then fails to prevent is the damage that
# already exists, which is strictly the better failure direction. So: file missing, `at:` absent,
# either value unparseable, equal stamps -- all 1.
#
# ⛔ SECOND-PRECISION Z ONLY, AND THAT NARROWNESS IS MEASURED. All 8 tracked ledgers carry a
# second-precision Z front-matter `at:` (censused 2026-09-15). Minute-precision exists only in ENTRY
# HEADERS, which this function never reads -- censusing headers instead of front matter is how the
# first draft acquired a requirement for a case unreachable on this path. If a minute-precision
# front matter ever does appear it falls through the shape gate to 1 = today's behaviour.
#
# ⛔ A NON-Z STAMP IS REJECTED, NEVER COMPARED. `2026-09-02T00:20:21+09:00` is live in the corpus; a
# local-offset stamp compares lexicographically against a Z stamp and silently mis-orders while
# looking entirely reasonable. Rejecting it costs one skipped guard; comparing it inverts the answer.
#
# ⛔ THE COMPARISON IS awk, NOT `[ "$a" \> "$b" ]`. POSIX `test` does not define `<`/`>` for strings
# -- it is a widely-implemented extension, not a guarantee, and this library is plain `sh`. Both
# operands are non-numeric (they carry `-`, `T`, `:`, `Z`), so awk compares them as strings.
kt_ss_active_is_newer() {
  _ss_inc=$(kt_ss_read_active_at "$1" 2>/dev/null)
  _ss_mine="$2"
  _ss_isoz='^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$'
  printf '%s' "$_ss_inc"  | grep -Eq "$_ss_isoz" || return 1
  printf '%s' "$_ss_mine" | grep -Eq "$_ss_isoz" || return 1
  awk -v a="$_ss_inc" -v b="$_ss_mine" 'BEGIN { exit (a > b) ? 0 : 1 }'
}

# Emit every RESUMABLE candidate in a SESSION.md, one per line: `<sid>|<at>|<status>|<source>`
# where source is `active` (the `## Next session prompt` block) or `pending` (an unconsumed entry
# under `## Pending handoffs` or the legacy `## Prior sessions`). Read-only; never writes.
#
# ⛔ ONE HELPER, THREE CONSUMERS. resume, the picker and the token lookup all need this parse. Left
# as prose in a SKILL.md it would be re-derived three times -- three call sites, one defect -- and
# no shell suite could exercise it, which is what made the legacy-parity acceptance criterion
# unimplementable as written.
#
# THE FOUR AXES, each of which silently DROPS candidates when missed:
#   1. two headings  -- `## Pending handoffs` and the legacy `## Prior sessions`, both still live.
#   2. two terminators -- the explicit marker, or NOTHING. Nothing here depends on the terminator:
#      an entry is recognised by its own `### ` header, so a missing terminator cannot hide it.
#   3. two prompt serializations -- irrelevant to enumeration, which reads headers only. Deliberate:
#      the picker renders `focus`/`next`, and reading those is the caller's job, not this parse's.
#   4. status forms -- only a word-bounded `unconsumed` is a candidate. `unconsumed` CONTAINS
#      `consumed`, so the bounding is what keeps a live entry from reading as terminal.
#
# ⛔ ARCHIVED SECTIONS ARE NOT CANDIDATES, and this is load-bearing rather than tidy: 89 entries
# were archived out of one ledger on 2026-09-15 specifically so they would stop being offered. Only
# the two LEDGER headings qualify; everything else -- archives included -- is skipped.
#
# ⛔ FENCE-AWARE, AND THE RULE ORDER IS THE MECHANISM. The fence toggle is tested BEFORE the heading
# rule, so a column-0 `## ` or `### ` inside a STORED PROMPT cannot move the current section or be
# counted as an entry. Stored prompts routinely contain both -- that is why full-fidelity demotion
# exists -- and a parse without this reads one entry's prompt as a new section.
#
# ⛔ NO TERNARIES. BSD awk rejects `print (c > 0) ? x : y`, and this library is plain `sh` on BSD
# userland. if/else throughout, deliberately.
kt_ss_ledger_candidates() {
  _ss_f="$1/SESSION.md"
  [ -f "$_ss_f" ] || return 0
  awk '
    BEGIN { fm = 0; infence = 0; sec = ""; actseen = 0; fsid = ""; fat = "" }
    NR == 1 && $0 == "---" { fm = 1; next }
    fm == 1 && $0 == "---" { fm = 0; next }
    fm == 1 {
      if ($0 ~ /^sessionId:[[:space:]]*/) { s = $0; sub(/^sessionId:[[:space:]]*/, "", s); fsid = s }
      if ($0 ~ /^at:[[:space:]]*/)        { s = $0; sub(/^at:[[:space:]]*/, "", s);        fat  = s }
      next
    }
    /^```/ { if (infence == 1) { infence = 0 } else { infence = 1 } next }
    infence == 1 {
      if (sec == "ACTIVE" && $0 ~ /[^[:space:]]/) { actseen = 1 }
      next
    }
    /^## / {
      if ($0 ~ /^## Next session prompt[[:space:]]*$/) { sec = "ACTIVE" }
      else if ($0 ~ /^## Pending handoffs[[:space:]]*$/) { sec = "LEDGER" }
      else if ($0 ~ /^## Prior sessions[[:space:]]*$/)   { sec = "LEDGER" }
      else { sec = "OTHER" }
      next
    }
    sec == "ACTIVE" && $0 ~ /[^[:space:]]/ { actseen = 1; next }
    sec == "LEDGER" && /^### / {
      if ($0 ~ /(^|[^a-z])unconsumed([^a-z]|$)/) {
        n = split(substr($0, 5), f, " · ")
        if (n >= 2) {
          sid = f[1]; at = f[2]
          gsub(/^[ \t]+/, "", sid); gsub(/[ \t]+$/, "", sid)
          gsub(/^[ \t]+/, "", at);  gsub(/[ \t]+$/, "", at)
          print sid "|" at "|unconsumed|pending"
        }
      }
    }
    END { if (actseen == 1 && fsid != "") { print fsid "|" fat "|unconsumed|active" } }
  ' "$_ss_f" 2>/dev/null
  return 0
}

# Locate a PASTED prompt by its provenance token. Emits `<sid>|<at>|<status>|<source>` for the
# candidate whose stored prompt carries <token>, or nothing. Read-only.
#
# ⛔ LOCATE BY THE TOKEN STRING, NEVER BY SID. The token is self-locating because the Step 3e opener
# is reused verbatim in both the pasteable artifact and the SESSION.md prompt block -- the same bytes
# exist in both places. Between a /handoff and the paste, another session can DEMOTE the prompt out
# of the active slot, which is not hypothetical: measured 2026-09-14, a demote 14 minutes later. A
# sid- or slot-based lookup misses that; the token follows the body wherever it goes.
#
# ⛔ THREE OUTCOMES, NOT TWO -- `archived` is a distinct answer from EMPTY, and collapsing them is a
# data decision, not a formatting one. A token under an archive heading was deliberately taken out of
# the offer (89 entries were archived for exactly that reason). Reporting it EMPTY invites a caller
# to treat the prompt as lost and resurrect it; reporting it offerable undoes the archiving. It is
# LOCATED BUT NOT OFFERED, and the caller decides.
#
# ⛔ THE TOKEN TEST RUNS BEFORE THE FENCE SKIP, and that ordering is the whole mechanism. The token
# lives INSIDE the opener fence, so a fence-skipping walk never sees it -- while headings and entry
# headers must stay OUTSIDE the fence, or a column-0 marker inside a stored prompt is read as
# structure. Both requirements are satisfied by rule order alone: token first, then the fence toggle,
# then the skip, then headings and headers.
#
# ⛔ index(), not a regex: the token contains `/` and `@` and is caller-supplied.
kt_ss_ledger_token_locate() {
  _ss_f="$1/SESSION.md"
  [ -f "$_ss_f" ] || return 0
  awk -v tok="$2" '
    BEGIN { fm = 0; infence = 0; sec = ""; hsid = ""; hat = ""; hst = "unconsumed" }
    NR == 1 && $0 == "---" { fm = 1; next }
    fm == 1 && $0 == "---" { fm = 0; next }
    fm == 1 {
      if ($0 ~ /^sessionId:[[:space:]]*/) { s = $0; sub(/^sessionId:[[:space:]]*/, "", s); fsid = s }
      if ($0 ~ /^at:[[:space:]]*/)        { s = $0; sub(/^at:[[:space:]]*/, "", s);        fat  = s }
      next
    }
    index($0, tok) > 0 {
      if (sec == "ACTIVE") { print fsid "|" fat "|unconsumed|active"; exit }
      if (sec == "LEDGER" && hsid != "")   { print hsid "|" hat "|" hst "|pending";  exit }
      if (sec == "ARCHIVED" && hsid != "") { print hsid "|" hat "|" hst "|archived"; exit }
      next
    }
    /^```/ { if (infence == 1) { infence = 0 } else { infence = 1 } next }
    infence == 1 { next }
    /^## / {
      if ($0 ~ /^## Next session prompt[[:space:]]*$/)   { sec = "ACTIVE" }
      else if ($0 ~ /^## Pending handoffs[[:space:]]*$/) { sec = "LEDGER" }
      else if ($0 ~ /^## Prior sessions[[:space:]]*$/)   { sec = "LEDGER" }
      else if ($0 ~ /^## Archived/)                      { sec = "ARCHIVED" }
      else { sec = "OTHER" }
      hsid = ""; hat = ""; hst = "unconsumed"
      next
    }
    /^### / {
      n = split(substr($0, 5), f, " · ")
      if (n >= 2) {
        hsid = f[1]; hat = f[2]
        gsub(/^[ \t]+/, "", hsid); gsub(/[ \t]+$/, "", hsid)
        gsub(/^[ \t]+/, "", hat);  gsub(/[ \t]+$/, "", hat)
        if ($0 ~ /(^|[^a-z])unconsumed([^a-z]|$)/) { hst = "unconsumed" } else { hst = "terminal" }
      }
    }
  ' "$_ss_f" 2>/dev/null
  return 0
}
