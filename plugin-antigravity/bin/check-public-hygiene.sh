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
# ⚠ `alter` lives HERE and not in TERMS on purpose: as a bare word it would fire on
# "alter", "altered", "alternative". Path-anchoring is FP-free BY CONSTRUCTION, which a
# measurement of "zero occurrences today" is NOT — a fatal gate must survive tomorrow's
# prose too. Measured surface when added: 2 lines, both real leaks.
CODES="cs df ss alter"

# Private artifact names that carry a project prefix no CODES pattern can see.
ARTIFACTS="df-input df-working cs-mobile cs-space"

# Own-org repos that are PUBLIC. Anything else under this owner is treated as private.
# ⛔ DENY-BY-DEFAULT, and it is the OPPOSITE trade from TERMS above — deliberately. A
# denylist of private repo names admits every repo created LATER by default, which is a
# silent leak. An allowlist fails LOUDLY on release when a new public repo is referenced,
# and that is a one-word fix. Loud-and-fixable beats silent. Same posture as the
# deny-by-default ~/.gemini/antigravity/.gitignore, whose own header says "do not invert it".
# ⚠ Accepted cost: referencing a NEW public own-org repo breaks the release until added here.
OWNER="mikeprasad"
OWN_PUBLIC="aria-knowledge aria-knowledge-core-spec"

# A home-directory path leaks an OS username and is a broken instruction for every other
# reader. Placeholders are fine — the point is that no REAL account name ships.
HOME_PLACEHOLDERS="you user USER USERNAME me example someone yourname alice bob x"

FOUND=0
report() { printf '  %s\n' "$*"; FOUND=$((FOUND + 1)); }

# --- matchers, factored so the SELF-TESTS exercise the same code the scan uses ---------
# A self-test against a parallel reimplementation proves nothing about the scan; these two
# functions are the single definition, called from both places.
_kt_own_repo_leak() {   # stdin: text -> stdout: offending repo names, one per line
    grep -o -E "github\.com/$OWNER/[A-Za-z0-9._-]+" 2>/dev/null | sed 's|.*/||' \
    | while IFS= read -r _repo; do
        _ok=0
        for _p in $OWN_PUBLIC; do [ "$_repo" = "$_p" ] && _ok=1; done
        [ "$_ok" -eq 0 ] && printf '%s\n' "$_repo"
      done
}
_kt_home_leak() {       # stdin: text -> stdout: offending account names, one per line
    # BOUNDARY-ANCHORED, the same technique this file already uses for CODES ("a bare `cs/`
    # substring matches `docs/`"). Without the anchor, `"$SC/home/Library"` — a test scratch
    # tree that merely CONTAINS a dir named home — matched and captured "Library". Measured
    # as a live false positive on this repo's own tests.
    grep -o -E "(^|[^A-Za-z0-9._$-])/(Users|home)/[A-Za-z0-9._-]+" 2>/dev/null | sed 's|.*/||' \
    | while IFS= read -r _u; do
        # A capture with NO alphanumeric character is a placeholder (`/Users/...`), not an
        # account name. Measured as a live false positive on this repo's own docs: `.` is in
        # the character class, so `...` matched. This is the FP that would have broken every
        # future release.
        printf '%s' "$_u" | grep -q '[A-Za-z0-9]' || continue
        _ok=0
        for _p in $HOME_PLACEHOLDERS; do [ "$_u" = "$_p" ] && _ok=1; done
        [ "$_ok" -eq 0 ] && printf '%s\n' "$_u"
      done
}

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

# own-org repo links: must FIRE on a private one, STAY SILENT on a public one, and STAY
# SILENT on another owner entirely (the pattern is owner-scoped, not repo-name-scoped).
printf 'see https://github.com/mikeprasad/knowledge/blob/main/a.md\n' \
    | _kt_own_repo_leak | grep -q . || st_fail=1                           # must FIRE
printf 'see https://github.com/mikeprasad/aria-knowledge/blob/main/a.md\n' \
    | _kt_own_repo_leak | grep -q . && st_fail=1                           # must STAY SILENT
printf 'see https://github.com/someoneelse/knowledge/blob/main/a.md\n' \
    | _kt_own_repo_leak | grep -q . && st_fail=1                           # must STAY SILENT
# home paths: must FIRE on a real account name, STAY SILENT on a placeholder.
# ⚠ jdoe, NOT alice: alice/bob are on the placeholder list because the repo's own docs use
# them illustratively (\`e.g. /Users/alice/.claude/…\`). The self-test caught that contradiction.
printf 'cd /Users/jdoe/Projects\n'  | _kt_home_leak | grep -q . || st_fail=1   # must FIRE
printf 'cd /Users/you/Projects\n'   | _kt_home_leak | grep -q . && st_fail=1   # must STAY SILENT
printf 'Resolved path: /Users/.../aria\n' | _kt_home_leak | grep -q . && st_fail=1  # must STAY SILENT
printf 'mkdir -p "$SC/home/Library/x"\n'   | _kt_home_leak | grep -q . && st_fail=1  # must STAY SILENT

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

# --- own-org links to a repo that is not on the public allowlist ---------------
# A line is reported if ANY own-org repo on it is unlisted — not just the first. Taking
# only the first match would let `[public](…/aria-knowledge) and [private](…/knowledge)`
# pass on one line, which is a guard scoped to the wrong unit.
own_hits=$(scan "github\.com/$OWNER/[A-Za-z0-9._-]+" | while IFS= read -r line; do
    if printf '%s\n' "$line" | _kt_own_repo_leak | grep -q .; then printf '%s\n' "$line"; fi
done | head -20)
if [ -n "$own_hits" ]; then
    printf 'link to a NON-PUBLIC %s repo (allowlist: %s):\n' "$OWNER" "$OWN_PUBLIC"
    echo "$own_hits" | while IFS= read -r line; do
        printf '  %s\n' "$(echo "$line" | cut -c1-160)"
    done
    FOUND=$((FOUND + 1))
fi

# --- home-directory paths carrying a real account name ------------------------
home_hits=$(scan "(^|[^A-Za-z0-9._$-])/(Users|home)/[A-Za-z0-9._-]+" | while IFS= read -r line; do
    if printf '%s\n' "$line" | _kt_home_leak | grep -q .; then printf '%s\n' "$line"; fi
done | head -20)
if [ -n "$home_hits" ]; then
    printf 'home path with a real account name (placeholders allowed: %s):\n' "$HOME_PLACEHOLDERS"
    echo "$home_hits" | while IFS= read -r line; do
        printf '  %s\n' "$(echo "$line" | cut -c1-160)"
    done
    FOUND=$((FOUND + 1))
fi

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
      # ⛔ Every reporting class MUST feed this derivation. These two were printed but not
      # counted, so the gate reported leaks and exited 0 — a fatal gate that does not fail.
      # The variables are the EXACT strings printed above, so the verdict cannot disagree
      # with the report; re-scanning here would duplicate the pattern and could drift.
      # ⚠ IF YOU ADD A CLASS, ADD IT HERE TOO. The durable shape is to accumulate every
      # printed finding into one variable and derive from that; not done now only because a
      # parallel session is live in this tree.
      printf '%s' "$own_hits"
      printf '%s' "$home_hits"
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
