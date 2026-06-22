#!/usr/bin/env bash
#
# publish-release.sh — attach the complete stable-alias asset set to the
# canonical GitHub release, so the marketing site's
# https://github.com/mikeprasad/aria-knowledge/releases/latest/download/<name>
# links all resolve.
#
# WHY THIS EXISTS
# ---------------
# The site links to STABLE (non-versioned) asset names via /releases/latest/.
# /latest/ resolves to whichever release is newest — in practice the canonical
# v2.x tag — and the link only works if a fixed-name asset is attached there.
# Each release-*.sh BUILDS its stable alias at repo root but does NOT publish;
# publishing is this script's job. All 6 stable aliases ride the canonical
# release (Mike's decision 2026-06-23): canonical is the single asset hub
# /latest/ points at, regardless of how each port is versioned in source.
#
# It does NOT cut the release (no `gh release create`) or push tags — run your
# normal release ceremony first, then run this to attach assets. Idempotent
# (uses --clobber). Defaults to a DRY RUN; pass --apply to actually upload.
#
# USAGE
#   ./publish-release.sh                 # dry run against the canonical v<plugin.json version> tag
#   ./publish-release.sh --apply         # really upload
#   ./publish-release.sh v2.35.2 --apply # explicit tag
#
# PREREQ: run the build scripts first so the stable aliases exist at repo root:
#   ./release.sh ; ./release-antigravity.sh ; ./release-codex.sh ; ./release-cursor.sh
#   (cd plugin-claude-cowork && ./release.sh)

set -euo pipefail

REPO="mikeprasad/aria-knowledge"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- colors / logging -------------------------------------------------------
c() { printf '\033[%sm' "$1"; }
log()  { printf '%s[publish]%s %s\n' "$(c '0;36')" "$(c 0)" "$*"; }
ok()   { printf '%s[  ok   ]%s %s\n' "$(c '0;32')" "$(c 0)" "$*"; }
warn() { printf '%s[ warn  ]%s %s\n' "$(c '0;33')" "$(c 0)" "$*"; }
die()  { printf '%s[ fail  ]%s %s\n' "$(c '0;31')" "$(c 0)" "$*" >&2; exit 1; }

command -v gh >/dev/null || die "gh (GitHub CLI) required"

# --- args -------------------------------------------------------------------
APPLY=0
TAG=""
for arg in "$@"; do
    case "$arg" in
        --apply) APPLY=1 ;;
        --dry-run) APPLY=0 ;;
        -*) die "unknown flag: $arg" ;;
        *) TAG="$arg" ;;
    esac
done

# Default tag = v<canonical version> from plugin-claude-code/.claude-plugin/plugin.json
if [[ -z "$TAG" ]]; then
    MANIFEST="$REPO_ROOT/plugin-claude-code/.claude-plugin/plugin.json"
    [[ -f "$MANIFEST" ]] || die "canonical manifest not found: $MANIFEST"
    VER=$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' "$MANIFEST" | head -1 | sed -E 's/.*"([^"]+)"$/\1/')
    [[ -n "$VER" ]] || die "could not read version from $MANIFEST"
    TAG="v$VER"
    log "defaulting to canonical tag: $TAG (from plugin.json)"
fi

# --- the asset set ----------------------------------------------------------
# Stable aliases the SITE links to (must all be present on the /latest/ release),
# plus the versioned canonical zip for provenance. Cowork's stable .plugin lives
# under plugin-claude-cowork/ (its REPO_ROOT in that script is the port folder).
ASSETS=(
    "$REPO_ROOT/aria-knowledge-plugin.zip"
    "$REPO_ROOT/aria-knowledge-antigravity.zip"
    "$REPO_ROOT/aria-knowledge-codex.zip"
    "$REPO_ROOT/aria-knowledge-cursor.zip"
    "$REPO_ROOT/plugin-claude-cowork/aria-cowork.plugin"
)
# The versioned canonical zip is named with the bare version (no leading v).
VERSIONED_PLUGIN="$REPO_ROOT/aria-knowledge-plugin-${TAG#v}.zip"
[[ -f "$VERSIONED_PLUGIN" ]] && ASSETS+=("$VERSIONED_PLUGIN")

# --- preflight: every stable alias must exist -------------------------------
missing=0
for a in "${ASSETS[@]}"; do
    if [[ -f "$a" ]]; then
        log "found: $(basename "$a")  ($(du -h "$a" | cut -f1))"
    else
        warn "MISSING: $a  — run its release-*.sh first"
        missing=1
    fi
done
[[ "$missing" -eq 0 ]] || die "one or more stable aliases missing; build them, then re-run"

# --- confirm the release exists ---------------------------------------------
gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 \
    || die "release $TAG not found on $REPO — cut the release first (gh release create $TAG)"

# --- upload -----------------------------------------------------------------
if [[ "$APPLY" -eq 0 ]]; then
    warn "DRY RUN — would upload the above ${#ASSETS[@]} assets to $TAG (re-run with --apply)"
    exit 0
fi

log "uploading ${#ASSETS[@]} assets to $TAG ..."
gh release upload "$TAG" --repo "$REPO" --clobber "${ASSETS[@]}"
ok "uploaded ${#ASSETS[@]} assets to $TAG"

# --- verify the /latest/ links the site depends on --------------------------
log "verifying /releases/latest/download/ resolves ..."
fail=0
for name in aria-knowledge-plugin.zip aria-knowledge-antigravity.zip \
            aria-knowledge-codex.zip aria-knowledge-cursor.zip aria-cowork.plugin; do
    code=$(curl -s -o /dev/null -w "%{http_code}" -L \
        "https://github.com/$REPO/releases/latest/download/$name")
    if [[ "$code" == "200" ]]; then
        ok "200  $name"
    else
        warn "$code  $name  (is $TAG the newest release? /latest/ points at the newest tag)"
        fail=1
    fi
done
[[ "$fail" -eq 0 ]] || die "one or more /latest/ links did not resolve — see warnings above"
ok "all site download links resolve via /releases/latest/download/"
