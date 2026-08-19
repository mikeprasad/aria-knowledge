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

# C3 — bound our OWN runtime rather than relying on undocumented PreToolUse
# timeout semantics. The unit is SECONDS: `date +%s` has whole-second
# resolution, so a name promising milliseconds would promise precision the
# mechanism does not have.
EF_BUDGET_S="${ARIA_EF_BUDGET_S:-4}"
EF_START=$(date +%s)

SESSION_ID=$(printf '%s' "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | sed 's/.*"session_id":"//;s/"$//')
[ -z "$SESSION_ID" ] && SESSION_ID="$$"
EF_DENY_FILE="${TMPDIR:-/tmp}/aria-extfetch-denies-${SESSION_ID}"

# Every path that lets a fetch through clears the breaker counter, so three
# consecutive denials means three with nothing allowed in between.
ef_allow() { rm -f "$EF_DENY_FILE" 2>/dev/null; exit 0; }

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
# UNUSED since 2.45.1 — the query branch below no longer matches prose words, so
# nothing reads this list. Deliberately left in place rather than deleted: the
# `case` construct that consumed it carries a measured parse trap (dropping the
# leading `(` on a pattern inside `$( )` breaks the WHOLE file with "syntax error
# near ';;'"), and touching it buys nothing while the list is inert. Removal
# trigger (Rule 37): delete this block if a future change reintroduces any
# prose-word matching, or at the next cleanup pass that already edits this file.
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
  # The gate's contract is DOMAIN coverage — "aimed at a domain the knowledge
  # folder or memory dirs already cover". A bare-prose query has no domain, and
  # matching query WORDS against the corpus cannot express that contract.
  #
  # v2.45.0 took the four longest non-stopword query words and built
  # `(w1|w2|w3|w4)\.[a-z]` — the domain shape from the URL branch above. Against
  # prose that reads "any query word followed by a dot and a lowercase letter",
  # which matches every `guidelines.md`, `screening.md` or dotted path in the
  # corpus. MEASURED 2026-08-14: three consecutive medical-literature searches
  # denied, citing prospect logs and design-token decision docs from unrelated
  # projects — zero topical relation. The whole match was `guidelines.m` (7x),
  # the word "guidelines" inside a FILENAME. Isolated: guidelines -> 4 files,
  # screening -> 0, participation -> 0. One common English word did all the work.
  #
  # Word filtering CANNOT rescue this, measured rather than assumed: the design
  # intended "dictionary-filtered vendor stems", but /usr/share/dict/words holds
  # `guideline` and NOT `guidelines`, so every English plural reads as a vendor
  # stem — while `render` IS in the dictionary, so filtering would also stop
  # detecting render.com, a vendor the corpus really covers. Wrong in both
  # directions; the dictionary dependency was dropped during design for
  # unrelated reasons and reinstating it would not have caught the reported bug.
  #
  # So: a query CAN name a domain ("cdc.gov vaccination schedule",
  # "site:auanet.org ..."), and there the domain logic is correct unchanged.
  # Otherwise there is nothing to gate on, and the gate stays silent.
  #
  # Keying on the domain also repairs the retry promise the reason text makes.
  # The old key was the four longest words, so REPHRASING a denied query minted
  # a NEW key and denied again — punishing the natural response to a blocked
  # search, and the reason one denial became three. Same domain, same key now.
  #
  # The explicit TLD list is load-bearing, not decoration: a generic
  # `\.[a-z]{2,}` reintroduces the exact bug by matching "screening.the" in
  # prose. Requiring a real TLD is what makes a match MEAN "domain". Extend the
  # list if a new TLD is needed; do not generalise it.
  #
  # Bare `grep` is correct here and consistent with lines ~34/46/47: the
  # /usr/bin/grep rule applies to the CORPUS scan below, where a ugrep wrapper
  # would honour .gitignore. This parses an input string, traverses nothing.
  EF_QTLD='(com|org|net|gov|edu|int|mil|io|ai|co|dev|app|jp|uk|de|fr|cn|kr)'
  EF_DOM=$(printf '%s' "$QUERY" | tr 'A-Z' 'a-z' \
    | grep -oE "[a-z0-9][a-z0-9-]*(\.[a-z0-9][a-z0-9-]*)*\.$EF_QTLD" | head -1)
  if [ -n "$EF_DOM" ]; then
    EF_KEY=$(printf '%s' "$EF_DOM" | awk -F. '{ if (NF>=2) print $(NF-1)"."$NF; else print $0 }')
    [ -n "$EF_KEY" ] && EF_PATTERN=$(printf '%s' "$EF_KEY" | sed 's/\./\\./g')
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

[ -n "$EF_HITS" ] || ef_allow

EF_COUNT=$(printf '%s\n' "$EF_HITS" | grep -c . 2>/dev/null || echo 0)

# Ambient-surface cap. A host mentioned everywhere carries no signal, and
# surfacing 76 files trains the reader to dismiss the hook — worse than silence.
case "$KT_EXTERNAL_FETCH_MAX_HITS" in ''|*[!0-9]*) KT_EXTERNAL_FETCH_MAX_HITS=8 ;; esac
[ "$EF_COUNT" -gt "$KT_EXTERNAL_FETCH_MAX_HITS" ] && ef_allow

# C3 budget check — placed after the lookup, which is the only expensive work.
# Over budget we ALLOW: a slow gate must never become a blocking gate.
EF_ELAPSED=$(( $(date +%s) - EF_START ))
[ "$EF_ELAPSED" -ge "$EF_BUDGET_S" ] && exit 0

# --- one-shot gate ----------------------------------------------------------
COOLDOWN_FILE="${TMPDIR:-/tmp}/aria-extfetch-${SESSION_ID}-${EF_KEY}"
[ -f "$COOLDOWN_FILE" ] && exit 0

# C2 — deny-rate circuit breaker, mirroring pre-edit-check.sh's v2.30.0
# mechanism. Three consecutive denials with no intervening allowed fetch
# degrade to allow. C1 below fixes the one deadlock cause we know about; this
# closes the class, including causes not yet enumerated.
EF_DENIES=0
[ -f "$EF_DENY_FILE" ] && EF_DENIES=$(cat "$EF_DENY_FILE" 2>/dev/null)
case "$EF_DENIES" in ''|*[!0-9]*) EF_DENIES=0 ;; esac
[ "$EF_DENIES" -ge 3 ] && exit 0

# C1 — the cooldown write is a PRECONDITION of denying, not a consequence.
# pre-explore-codemap-check.sh:66 writes its cooldown unchecked, which is safe
# THERE because that hook is ADVISORY. Here a failed write means:
#   deny -> retry -> cooldown still absent -> deny -> ...  (unbounded)
# So: write first, verify, and allow the fetch if it did not land.
date +%s > "$COOLDOWN_FILE" 2>/dev/null
[ -f "$COOLDOWN_FILE" ] || exit 0

# The denial is now certain to be emitted, so record it. Ordering matters: this
# sits AFTER the verified cooldown write, so the counter can never advance for a
# denial that was not actually issued.
printf '%s' "$(( EF_DENIES + 1 ))" > "$EF_DENY_FILE" 2>/dev/null

# Render paths relative to the knowledge folder where possible — an absolute
# temp path is noise in the reason text.
EF_LIST=$(printf '%s\n' "$EF_HITS" | sed "s|^${KT_KNOWLEDGE_FOLDER}/||" | tr '\n' ';' | sed 's/;$//; s/;/; /g')

REASON="A recorded local reference already covers this surface (${EF_KEY}). Read these before fetching externally: ${EF_LIST}. Then fetch only what they do not answer — coverage is not currency, so re-verify anything they assert. This fires once per surface per session; the retry will pass."
REASON=$(kt_json_escape "$REASON")

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$REASON"
