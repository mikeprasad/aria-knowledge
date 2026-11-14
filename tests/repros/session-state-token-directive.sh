#!/bin/sh
# tests/repros/session-state-token-directive.sh — the SESSION STATE directive's TOKEN branch (D5)
# and the operator-precedence clause (D7), asserted on the DELIVERED copy.
#
# ⛔ RE-POINTED 2026-10-25. This used to drive session-start-check.sh and read its stdout. That
# stdout was a systemMessage, which renders to the user and never reaches the model (measured from
# a transcript's API request records), so the suite was guarding a copy nobody received — and the
# copy the model DID receive, the bundled digest, lacked one of these clauses the whole time.
# The digest is loaded verbatim as an instruction file, so reading it IS reading the payload.
#
# Scoped to the SESSION STATE section on purpose: the same phrases could appear elsewhere in the
# digest, and a whole-file grep would pass on a stray mention.
#
# ⚠ STATED BOUND: this proves what is DELIVERED. It cannot prove an agent OBEYS it.
set -e
DIR="$(cd "$(dirname "$0")/../.." && pwd)"
DIGEST="$DIR/plugin-claude-code/rules/aria-rules.md"
GATE='### When `session_state` is `true`'

# The section: from the gate heading to the next ### heading.
section=$(awk -v g="$GATE" '$0==g{f=1;next} f&&/^### /{exit} f' "$DIGEST")
fail=0
# Positive control FIRST: an empty extraction would make every grep below fail for the wrong reason.
if [ -n "$section" ] && printf '%s' "$section" | grep -q 'SESSION STATE —'; then
  printf '  PASS  control — the SESSION STATE directive sits under the session_state gate heading\n'
else
  printf '  FAIL  control — no SESSION STATE directive under %s\n' "$GATE"; fail=1
fi
chk() { # $1 = label, $2 = needle
  if printf '%s' "$section" | grep -qF "$2"; then printf '  PASS  %s\n' "$1"
  else printf '  FAIL  %s — not in the delivered directive\n' "$1"; fail=1; fi
}
# D5 — the five outcomes, each asserted by the phrase that carries it.
chk "D5 token is scanned for"                "aria-handoff: <project>/<sid>@<at>"
chk "R1 the WHOLE message is scanned"        "ENTIRE opening message"
chk "D5 locate helper is named"              "kt_ss_ledger_token_locate"
chk "D5 consume passes the exact at"         "FIFTH argument"
chk "D5 archived is its own outcome"         "'|archived'"
chk "D5 empty result does not fabricate"     "do NOT fabricate an entry"
chk "D5 terminal entry stops the resume"     "SURFACE AND STOP"
# D7 — operator precedence.
chk "R2 operator text outranks the prompt"   "OUTRANKS the stored prompt"
chk "R2 names the gate shape"                "state-verify gate, not a preamble"
# Backwards compatibility — the word trigger survives for tokenless prompts.
chk "fallback word trigger retained"         "If no token is present"

# B6 (2.57.8) — consume_active takes the located token and refuses a slot holding another one. Every
# copy of the directive must say both, or a resuming session calls the old three-argument form and
# gets a refusal it has no instruction for. Four copies: two digests (section-scoped as above) and
# the Codex and Cursor hooks, which carry the directive as one inline SESSION STATE string.
# Final fix wave (F2): the token is copied from the user's PASTED text, so it must never be composed
# into a shell command. Every copy names the _file forms, tells the model to write the token to a NEW
# file with its file-write tool, and no longer carries the token-taking call shape at all.
b6() { # $1 = label, $2 = text
  for _n in 'kt_ss_ledger_token_locate_file <project_root>' 'kt_ss_ledger_consume_active_file <project_root>' \
            'file-write tool' 'never consume whatever is now active'; do
    if printf '%s' "$2" | grep -qF -- "$_n"; then printf '  PASS  B6 %s — %s\n' "$1" "$_n"
    else printf '  FAIL  B6 %s — missing: %s\n' "$1" "$_n"; fail=1; fi
  done
  for _n in 'kt_ss_ledger_token_locate <' 'kt_ss_ledger_consume_active <' 'with the same token'; do
    if printf '%s' "$2" | grep -qF -- "$_n"; then printf '  FAIL  B6 %s — still carries: %s\n' "$1" "$_n"; fail=1
    else printf '  PASS  B6 %s — retired form absent: %s\n' "$1" "$_n"; fi
  done
}
b6 "claude-code digest" "$section"
ag_section=$(awk -v g="$GATE" '$0==g{f=1;next} f&&/^### /{exit} f' "$DIR/plugin-antigravity/rules/aria-rules.md")
b6 "antigravity digest" "$ag_section"
b6 "codex hook"  "$(grep 'SESSION STATE —' "$DIR/plugin-openai-codex/bin/session-start-check.sh")"
b6 "cursor hook" "$(grep 'SESSION STATE —' "$DIR/plugin-cursor-template/scripts/aria/session-start-check.sh")"

# B7 (2.58.0) — entries stored since 2.58.0 escape structural lines with one leading backslash, so
# the model must be told to read them without it. Asserted on the RENDERED output of each hook (run
# with an isolated HOME, a session_state: true config, a scratch state base and stdin closed), not on
# the source line: a source grep cannot see a render that drops or duplicates the sentence. The
# sentence is the same literal session-state.sh's AH2 strips, so the two arms agree on its text.
# The Claude Code and Antigravity digests are NOT covered here: their resume path is the /handoff
# skill's Step 0r, which carries its own escape note.
AH_EMITTER_SENTENCE='A stored prompt line that begins with one backslash before ##, ###, a code fence or the entry-end terminator line is escaped; read it without that one backslash. '
B7R=$(mktemp -d "${TMPDIR:-/tmp}/aria-ssd-b7.XXXXXX") || exit 1
B7R=$(cd "$B7R" && pwd)
trap 'rm -rf "$B7R"' EXIT
mkdir -p "$B7R/home" "$B7R/base" "$B7R/tmp" "$B7R/sweep" "$B7R/kf/logs" "$B7R/w"
printf -- '- **Date:** 2026-11-01 — audit\n' > "$B7R/kf/logs/knowledge-audit-log.md"
printf -- '- **Date:** 2026-11-01 — audit\n' > "$B7R/kf/logs/config-audit-log.md"
printf -- '---\nknowledge_folder: %s\nsession_state: true\n---\n' "$B7R/kf" > "$B7R/cfg.md"
b7() { # $1 = label, $2 = hook path
  (cd "$B7R/w" && env -u XDG_RUNTIME_DIR -u KT_STATE_DIR -u CLAUDE_CODE_SESSION_ID -u CODEX_THREAD_ID \
    HOME="$B7R/home" TMPDIR="$B7R/tmp" KT_TMP_SWEEP_ROOT="$B7R/sweep" KT_STATE_BASE="$B7R/base" \
    KT_CONFIG="$B7R/cfg.md" sh "$2" < /dev/null > "$B7R/out" 2>/dev/null) || true
  _ctl=$(awk -v s='SESSION STATE —' '{ while ((i = index($0, s)) > 0) { c++; $0 = substr($0, i + length(s)) } } END { print c + 0 }' "$B7R/out")
  _got=$(awk -v s="$AH_EMITTER_SENTENCE" '{ while ((i = index($0, s)) > 0) { c++; $0 = substr($0, i + length(s)) } } END { print c + 0 }' "$B7R/out")
  if [ "$_ctl" -ne 1 ]; then
    printf '  FAIL  B7 %s — control: rendered output carries %s SESSION STATE directives, want 1\n' "$1" "$_ctl"; fail=1
  elif [ "$_got" -eq 1 ]; then
    printf '  PASS  B7 %s — rendered SESSION STATE directive carries the escape sentence once\n' "$1"
  else
    printf '  FAIL  B7 %s — rendered output carries the escape sentence %s times, want 1\n' "$1" "$_got"; fail=1
  fi
}
b7 "codex hook"  "$DIR/plugin-openai-codex/bin/session-start-check.sh"
b7 "cursor hook" "$DIR/plugin-cursor-template/scripts/aria/session-start-check.sh"

[ "$fail" -eq 0 ] || { echo "session-state-token-directive: FAIL"; exit 1; }
echo "session-state-token-directive: PASS"
