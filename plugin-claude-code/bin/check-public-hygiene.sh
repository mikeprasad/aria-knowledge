#!/bin/sh
# check-public-hygiene.sh — fail a release when a private project identifier is
# about to ship in this PUBLIC repository.
#
# WHY THIS EXISTS
# ---------------
# On 2026-08-25 a repo-wide census found 113 occurrences across 35 files: client
# project directory names, both repo names of one project, a private domain with
# its file count, a design-system artifact name in the shipped Rule 22 template,
# and — worst — a full portfolio inventory with per-repo commit counts. None of it
# was malicious; every one entered as a worked example in a design doc or a test
# fixture, which is exactly the writing that makes good documentation. Nothing
# connected "internal name" to "public artifact", so the class accumulated
# silently across many releases.
#
# The fix is not vigilance. It is this gate.
#
# EXIT CODES — a broken instrument must never read as a clean result
#   0  clean
#   1  findings (named on stdout)
#   2  SELF-TEST FAILED — the matcher is broken; treat as unknown, never as clean
#
# KNOWN BOUND — state it rather than oversell the check
# -----------------------------------------------------
# This detects the identifiers listed in TERMS and CODES below. It cannot detect
# a project whose name nobody has added here. A new client project is invisible
# to this gate until its name is added, so ADD IT when one appears. The gate
# closes the known class; it does not make the repo self-policing.
#
# THREE INSTRUMENT LESSONS ARE ENCODED HERE, each paid for during that census:
#
#   1. BOUNDARY ANCHORING. A bare `cs/` substring matches `docs/` — 499 of them
#      in this repo. Every short-code pattern is anchored on a leading
#      non-path character. The self-test proves it.
#
#   2. WIDTH-BOUNDED CONTEXT HIDES MATCHES. A `.{45}` context pattern silently
#      skipped five files whose match sat near a line boundary. This script
#      never uses a fixed-width context window.
#
#   3. A SCANNER FLAGS THE DOCUMENT DESCRIBING THE SCANNER. This file names every
#      term it hunts, so it excludes itself by construction. If you copy the term
#      list anywhere else, exclude that too, or the gate reports itself forever
#      and gets muted — which is worse than not having it.
set -eu

ROOT="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
SELF_NAME="check-public-hygiene.sh"

# Private project identifiers. Word-matched, case-insensitive.
# NOTE: the singular "archetype" is deliberately ABSENT — it is legitimate ARIA
# taxonomy vocabulary ("31-archetype tagging"), and banning it would flag six
# correct files forever. Only the directory-name plural is private.
TERMS="archetypes commonspace seersite designframe shopsource voxflow currentfi japan10best thecollab kindred"

# Short workspace path codes. Matched only in PATH POSITION, boundary-anchored.
CODES="cs df ss"

# Private artifact names that carry a project prefix no CODES pattern can see.
ARTIFACTS="df-input df-working cs-mobile cs-space"

FOUND=0
report() { printf '  %s\n' "$*"; FOUND=$((FOUND + 1)); }

# --- self-test: prove the matcher can both fire AND stay silent --------------
# A gate that cannot fail is a false green. Both directions are checked, because
# a matcher that fires on everything is as useless as one that never fires.
code_pat=""
for c in $CODES; do
    if [ -z "$code_pat" ]; then code_pat="$c"; else code_pat="$code_pat|$c"; fi
done
CODE_RE="(^|[^A-Za-z0-9._/-])($code_pat)/"

st_fail=0
printf 'see cs/PROGRESS.md\n' | grep -Eq "$CODE_RE" || st_fail=1          # must FIRE
printf 'see docs/architecture.md\n' | grep -Eq "$CODE_RE" && st_fail=1    # must STAY SILENT
printf 'commonspace-app\n' | grep -qi "commonspace" || st_fail=1          # must FIRE
printf 'a normal sentence\n' | grep -qiE "$(echo "$TERMS" | tr ' ' '|')" && st_fail=1

if [ "$st_fail" -ne 0 ]; then
    printf 'gate D SELF-TEST FAILED — the hygiene matcher is broken.\n' >&2
    printf 'This is NOT a clean result. Fix the matcher before releasing.\n' >&2
    exit 2
fi

# --- scan --------------------------------------------------------------------
# SCOPE IS TRACKED FILES, NOT THE WORKING TREE. What publishes is what git
# carries; a gitignored scratch directory is not the artifact. On the run that
# validated this gate, an untracked `.superpowers/sdd/` tree produced ten hits
# that could never ship — noise that would have trained a reader to mute it.
#
# Matching is CASE-INSENSITIVE, and that is load-bearing: the last real finding
# in this repo was "real CS/SS work" — private projects referenced by their
# uppercase initials, which every case-sensitive census before this one missed.
#
# This file names every term it hunts, so it excludes itself (lesson 3 above).
# Falls back to a filesystem walk when not in a git repo, so the script stays
# usable standalone; the fallback is loudly less precise, hence the notice.
scan() {
    if [ -n "$TRACKED_OK" ]; then
        # Self-exclusion filters the FILE LIST, never the output lines.
        # A `grep -v "$SELF_NAME"` on results looked equivalent and was fail-open:
        # it silently dropped any finding whose line merely MENTIONED this script,
        # anywhere in the repo. That bug hid a real `CS/SS` leak in CLAUDE.md on the
        # very commit that introduced the gate — the guard was scoped to the wrong
        # unit (a line) instead of the right one (a file).
        ( cd "$ROOT" && git ls-files -z 2>/dev/null \
            | grep -zv "$SELF_NAME" \
            | xargs -0 grep -niE "$1" 2>/dev/null ) || true
    else
        grep -rniE "$1" "$ROOT" \
            --exclude-dir=.git \
            --exclude="*.zip" \
            --exclude="$SELF_NAME" \
            2>/dev/null || true
    fi
}

TRACKED_OK=""
if ( cd "$ROOT" && git rev-parse --is-inside-work-tree >/dev/null 2>&1 ); then
    TRACKED_OK="yes"
else
    printf 'gate D: not a git repo — scanning the working tree instead of tracked files.\n' >&2
    printf '         Results may include files that never publish.\n' >&2
fi

for t in $TERMS; do
    hits=$(scan "$t" | head -20)
    [ -z "$hits" ] && continue
    printf 'private project name "%s":\n' "$t"
    echo "$hits" | while IFS= read -r line; do
        printf '  %s\n' "$(echo "$line" | cut -c1-160)"
    done
    FOUND=$((FOUND + 1))
done

for a in $ARTIFACTS; do
    hits=$(scan "$a" | head -10)
    [ -z "$hits" ] && continue
    printf 'private artifact name "%s":\n' "$a"
    echo "$hits" | while IFS= read -r line; do
        printf '  %s\n' "$(echo "$line" | cut -c1-160)"
    done
    FOUND=$((FOUND + 1))
done

code_hits=$(scan "$CODE_RE" | head -20)
if [ -n "$code_hits" ]; then
    printf 'private workspace path code (boundary-anchored, does not match docs/):\n'
    echo "$code_hits" | while IFS= read -r line; do
        printf '  %s\n' "$(echo "$line" | cut -c1-160)"
    done
    FOUND=$((FOUND + 1))
fi

# FOUND is incremented inside pipelines in some shells, so re-derive the verdict
# from a direct test rather than trusting the counter across a subshell boundary.
any=$(
    { for t in $TERMS; do scan "$t"; done
      for a in $ARTIFACTS; do scan "$a"; done
      scan "$CODE_RE"
    } | head -1
)

if [ -n "$any" ]; then
    printf '\ngate D: private identifiers found above. Genericize them (this repo uses\n'
    printf 'proj-a / proj-b / proj-c as placeholders) before publishing.\n'
    exit 1
fi

printf 'gate D: public hygiene clean (self-test passed; %s terms, %s codes, %s artifacts checked)\n' \
    "$(echo "$TERMS" | wc -w | tr -d ' ')" \
    "$(echo "$CODES" | wc -w | tr -d ' ')" \
    "$(echo "$ARTIFACTS" | wc -w | tr -d ' ')"
exit 0
