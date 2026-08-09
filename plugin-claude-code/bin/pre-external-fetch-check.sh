#!/bin/sh
# pre-external-fetch-check.sh — PreToolUse hook for WebFetch|WebSearch
#
# Denies the FIRST external fetch per session per surface when a recorded local
# reference already covers that surface, naming the matched paths. The retry
# passes. The point is to surface what is already written down AT THE MOMENT OF
# THE FETCH — not to prevent fetching.
#
# It is an INTERRUPT, not a verification: it cannot confirm the reference was
# read, and the cooldown clears on the retry either way.
#
# Scope: coverage, not currency. "A local note exists" is not "the note is true."
#
# Fail-open on everything — unparseable input, missing config, absent folder,
# grep failure, a failed cooldown write, or exceeding the runtime budget.
# A gate that cannot read its own input must never block.

INPUT=$(cat)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/config.sh"

[ "$KT_EXTERNAL_FETCH_GATE" = "on" ] || exit 0
[ -n "$KT_KNOWLEDGE_FOLDER" ] || exit 0
[ -d "$KT_KNOWLEDGE_FOLDER" ] || exit 0

# --- extract the surface key ------------------------------------------------
# printf '%s' not echo: echo expands the \n inside JSON strings, splitting the
# value across lines so the single-line grep below matches nothing — a silent
# fail-open in exactly the case this guard exists for. See pre-cron-check.sh.
URL=$(printf '%s' "$INPUT"   | grep -o '"url":"[^"]*"'   | head -1 | sed 's/.*"url":"//;s/"$//')
QUERY=$(printf '%s' "$INPUT" | grep -o '"query":"[^"]*"' | head -1 | sed 's/.*"query":"//;s/"$//')

# Ordinary English words that are also domain stems in a real corpus. Matching
# these against prose is pure noise (measured: `index` fires on "postgres index
# bloat"). Inline rather than a data file: bin/ holds only .sh, template/ is the
# user-copied knowledge skeleton, and there is no data/ convention to invent for
# ~60 words.
EF_STOPWORDS=" common session index key space field head body size style text card gate
medium message parent schema template run seen secondary subscription material local
brand daily example archive extend icon input meta prism python render segment
universe wallet the and for how what where when with from this that your api docs doc
help support cloud "

# Normalise before matching. The literal above spans several lines for
# readability, and `case "$EF_STOPWORDS" in *" $w "*` CANNOT match a word with a
# NEWLINE on one side instead of a space — measured: in a two-line list the word
# after the break leaks through unfiltered. Roughly 8 of ~60 entries would
# silently stop filtering.
EF_STOPWORDS=" $(printf '%s' "$EF_STOPWORDS" | tr -s '[:space:]' ' ' | sed 's/^ *//;s/ *$//') "

EF_KEY=""       # cooldown key — must be stable across a retry
EF_PATTERN=""   # ERE handed to grep

if [ -n "$URL" ]; then
  HOST=$(printf '%s' "$URL" | sed 's|^[a-zA-Z][a-zA-Z0-9+.-]*://||; s|[/?#].*$||; s|:[0-9]*$||')
  EF_KEY=$(printf '%s' "$HOST" | awk -F. '{ if (NF>=2) print $(NF-1)"."$NF; else print $0 }')
  [ -n "$EF_KEY" ] && EF_PATTERN=$(printf '%s' "$EF_KEY" | sed 's/\./\\./g')
elif [ -n "$QUERY" ]; then
  # Longest-first (most specific), capped at 4 so the alternation stays bounded.
  # Then sorted, because the cooldown key is built from these: without a
  # canonical order the same query could mint a different key on the retry and
  # the one-shot gate would never clear.
  EF_WORDS=$(printf '%s' "$QUERY" | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9' '\n' \
    | awk 'length($0) >= 4' \
    | while read -r w; do
        # Leading '(' on each pattern is required, not cosmetic: this case sits
        # inside a $( ) substitution, where a bare pattern-opening ')' is
        # ambiguous with the substitution's terminator and `sh` fails to parse
        # the whole file. Measured: without it, "syntax error near `;;'".
        case "$EF_STOPWORDS" in (*" $w "*) ;; (*) printf '%s\n' "$w" ;; esac
      done \
    | awk '{ print length, $0 }' | LC_ALL=C sort -rn | cut -d' ' -f2- | head -4 \
    | LC_ALL=C sort)
  if [ -n "$EF_WORDS" ]; then
    EF_KEY=$(printf '%s' "$EF_WORDS" | tr '\n' '_' | sed 's/_$//')
    EF_ALT=$(printf '%s' "$EF_WORDS" | tr '\n' '|' | sed 's/|$//')
    EF_PATTERN="($EF_ALT)\\.[a-z]"
  fi
fi

[ -n "$EF_KEY" ] || exit 0
[ -n "$EF_PATTERN" ] || exit 0

# Sanitise for use in a filename.
EF_KEY=$(printf '%s' "$EF_KEY" | tr -cs 'a-zA-Z0-9._-' '-')

# --- look up local coverage -------------------------------------------------
# /usr/bin/grep, never bare grep: the workspace grep may be a ugrep wrapper that
# honours .gitignore and silently skips embedded repos.
# -l (stop at first match per file), never -o (measured ~3x slower).
EF_MEMDIR="${ARIA_EF_MEMDIR:-$HOME/.claude/projects}"

EF_HITS=$(
  {
    /usr/bin/grep -rlE --include='*.md' --exclude-dir=archive \
      "$EF_PATTERN" "$KT_KNOWLEDGE_FOLDER" 2>/dev/null
    for d in "$EF_MEMDIR"/*/memory; do
      [ -d "$d" ] || continue
      /usr/bin/grep -rlE "$EF_PATTERN" "$d" 2>/dev/null
    done
  } | LC_ALL=C sort -u
)

[ -n "$EF_HITS" ] || exit 0

EF_COUNT=$(printf '%s\n' "$EF_HITS" | grep -c . 2>/dev/null || echo 0)

# Ambient-surface cap. A host mentioned everywhere carries no signal, and
# surfacing 76 files trains the reader to dismiss the hook — worse than silence.
case "$KT_EXTERNAL_FETCH_MAX_HITS" in ''|*[!0-9]*) KT_EXTERNAL_FETCH_MAX_HITS=8 ;; esac
[ "$EF_COUNT" -gt "$KT_EXTERNAL_FETCH_MAX_HITS" ] && exit 0

# --- one-shot gate ----------------------------------------------------------
SESSION_ID=$(printf '%s' "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/.*"session_id":"//;s/"$//')
[ -z "$SESSION_ID" ] && SESSION_ID="$$"

COOLDOWN_FILE="${TMPDIR:-/tmp}/aria-extfetch-${SESSION_ID}-${EF_KEY}"
[ -f "$COOLDOWN_FILE" ] && exit 0

# >>> TASK-3 INSERTION POINT A: circuit-breaker check <<<

# C1 — the cooldown write is a PRECONDITION of denying, not a consequence.
# pre-explore-codemap-check.sh:66 writes its cooldown unchecked, which is safe
# THERE because that hook is ADVISORY. Here a failed write means:
#   deny -> retry -> cooldown still absent -> deny -> ...  (unbounded)
# So: write first, verify, and allow the fetch if it did not land.
date +%s > "$COOLDOWN_FILE" 2>/dev/null
[ -f "$COOLDOWN_FILE" ] || exit 0

# >>> TASK-3 INSERTION POINT B: breaker increment <<<

# Render paths relative to the knowledge folder where possible — an absolute
# temp path is noise in the reason text.
EF_LIST=$(printf '%s\n' "$EF_HITS" | sed "s|^${KT_KNOWLEDGE_FOLDER}/||" | tr '\n' ';' | sed 's/;$//; s/;/; /g')

REASON="A recorded local reference already covers this surface (${EF_KEY}). Read these before fetching externally: ${EF_LIST}. Then fetch only what they do not answer — coverage is not currency, so re-verify anything they assert. This fires once per surface per session; the retry will pass."
REASON=$(kt_json_escape "$REASON")

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$REASON"
