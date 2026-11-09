#!/bin/sh
# aria-surface.sh — CLI over the shared matcher (kt_index_match) so skills and
# other non-hook callers get the same ranked knowledge files the hooks get.
#
# Usage (a model, or anything that goes through a shell) — pass REFERENCES,
# never text. A path or a ref range carries no free text, so nothing in it can
# be parsed by the shell:
#   sh "<plugin-root>/scripts/aria-surface.sh" --file "<path>"
#   sh "<plugin-root>/scripts/aria-surface.sh" --git-range "<a>..<b>"
#   (either or both; the query is the file part followed by the git part)
# --file       the file's Markdown headings (lines starting 1-6 `#` and a space)
#              plus its first 40 non-blank lines. The path must be a readable
#              regular file, else `unavailable: invalid --file`.
# --git-range  up to 20 commit subjects of `<a>..<b>` in the current directory's
#              repo. Each side must match ^[A-Za-z0-9._/~^@{}][A-Za-z0-9._/~^@{}-]*$
#              (no leading `-`) and resolve with `git rev-parse --verify
#              --end-of-options`; git is always called with --end-of-options.
#              Anything else is `unavailable: invalid --git-range`.
# Any other `--option` (including the `--file=x` form) is `unavailable: unknown
# option <name>`, never a silent empty result.
# Positional text and `-` (stdin) remain for PROGRAMS that exec this without a
# shell (codex-hook.py passes an argv list): `-` reads the text from stdin, so
# does no argument when stdin is not a terminal. ⛔ A model must not put text on
# a command line or in a heredoc to this script — in double quotes, backticks and
# $(...) RUN and $VAR expands; use a reference instead.
#
# Output (stdout), exactly one of:
#   fired        line 1 `tags: <space-separated matched tags>`, then one ranked
#                PATH per line (the part before ` — `, no description)
#   nothing      the match did not fire (no tag matched, below the firing rule,
#                or fired on tags carrying no files), or there was no text
#   unavailable  one line `unavailable: <reason>` — config, knowledge folder or
#                matcher library missing, or the matcher reported an error (no
#                index, unreadable index, temp-file or cache failure). This is
#                "could not look", never "0 matches".
# Exit: 0 whenever this script runs. A caller must never be blocked by surfacing.

unavailable() { printf 'unavailable: %s\n' "$1"; exit 0; }

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || unavailable "cannot locate the plugin scripts"
[ -n "$SCRIPT_DIR" ] || unavailable "cannot locate the plugin scripts"

_as_text=""; _file=""; _range=""; _have_flag=0; _positional=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --file)
      [ "$#" -ge 2 ] || unavailable "invalid --file"
      _file=$2; _have_flag=1; shift 2 ;;
    --git-range)
      [ "$#" -ge 2 ] || unavailable "invalid --git-range"
      _range=$2; _have_flag=1; shift 2 ;;
    -)
      _as_text=$(cat); _positional=1; shift ;;
    --*)
      _opt=${1%%=*}; _opt=${_opt%%[[:space:]]*}
      unavailable "unknown option $_opt" ;;
    *)
      if [ "$_positional" -eq 0 ]; then _as_text=$1; _positional=1; fi
      shift ;;
  esac
done
if [ "$_have_flag" -eq 0 ] && [ "$_positional" -eq 0 ]; then
  [ -t 0 ] && exit 0
  _as_text=$(cat)
fi

if [ -n "$_file" ]; then
  [ -f "$_file" ] && [ -r "$_file" ] || unavailable "invalid --file"
  _fpart=$({ grep -E '^#{1,6} ' < "$_file"; grep -v '^[[:space:]]*$' < "$_file" | head -n 40; } 2>/dev/null)
  _as_text=$(printf '%s\n%s' "$_as_text" "$_fpart")
fi
if [ -n "$_range" ]; then
  _re='^[A-Za-z0-9._/~^@{}][A-Za-z0-9._/~^@{}-]*$'
  case "$_range" in *..*) ;; *) unavailable "invalid --git-range" ;; esac
  _ra=${_range%%..*}; _rb=${_range#*..}
  printf '%s\n' "$_ra" | grep -Eq "$_re" || unavailable "invalid --git-range"
  printf '%s\n' "$_rb" | grep -Eq "$_re" || unavailable "invalid --git-range"
  git rev-parse --verify --quiet --end-of-options "$_ra" >/dev/null 2>&1 || unavailable "invalid --git-range"
  git rev-parse --verify --quiet --end-of-options "$_rb" >/dev/null 2>&1 || unavailable "invalid --git-range"
  _gpart=$(git log --format=%s --end-of-options "$_ra..$_rb" 2>/dev/null | head -n 20)
  _as_text=$(printf '%s\n%s' "$_as_text" "$_gpart")
fi
[ -n "$(printf '%s' "$_as_text" | tr -d '[:space:]')" ] || exit 0

# shellcheck disable=SC1091
. "$SCRIPT_DIR/config.sh" >/dev/null 2>&1 || unavailable "config.sh failed to load"
[ -z "$KT_CONFIG_ERROR" ] || unavailable "config error (run /setup)"
[ -n "$KT_KNOWLEDGE_FOLDER" ] || unavailable "no knowledge folder configured"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib-index-match.sh" >/dev/null 2>&1 || unavailable "matcher library failed to load"

KT_MATCH_STATUS=""
kt_index_match "$_as_text" 2>/dev/null
case "$KT_MATCH_STATUS" in
  ok)
    if [ "${KT_MATCH_COUNT:-0}" -gt 0 ] 2>/dev/null && [ -f "$KT_MATCH_FILES_TMP" ]; then
      printf 'tags: %s\n' "$KT_MATCH_TAGS"
      awk -F ' — ' '{print $1}' "$KT_MATCH_FILES_TMP"
    else
      kt_match_cleanup 2>/dev/null
      unavailable "matcher reported a match but no files"
    fi
    ;;
  nofire) ;;
  error:*)
    kt_match_cleanup 2>/dev/null
    unavailable "matcher error: ${KT_MATCH_STATUS#error:}"
    ;;
  *)
    kt_match_cleanup 2>/dev/null
    unavailable "matcher reported no status"
    ;;
esac
kt_match_cleanup 2>/dev/null
exit 0
