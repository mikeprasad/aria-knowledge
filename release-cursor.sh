#!/usr/bin/env bash
# release-cursor.sh — build a clean Cursor port zip.
#
# Reads version from plugin-cursor-template/scripts/aria/VERSION (source of truth),
# stages plugin-cursor-template/ with junk + maintainer-only files excluded, and emits
# aria-knowledge-cursor-<canonical-version>.zip at repo root.
#
# Excluded from shipped zip (per multi-port release decisions):
#   - audit/       — frozen audit artifacts (maintainer-facing, not user-facing)
#   - PORTING.md   — drift-tracking doc for maintainers
#
# The shipped zip is a repo skeleton: users unzip its contents into the root
# of their own project, then restart Cursor.
#
# Sibling of release.sh (Claude port) and release-codex.sh.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CURSOR_VERSION_FILE="$REPO_ROOT/plugin-cursor-template/scripts/aria/VERSION"

log()  { printf '\033[0;36m[release]\033[0m %s\n' "$*"; }
ok()   { printf '\033[0;32m[  ok   ]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[ warn  ]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[0;31m[ fail  ]\033[0m %s\n' "$*" >&2; exit 1; }

# --- preflight --------------------------------------------------------------
[[ -f "$CURSOR_VERSION_FILE" ]] || die "missing $CURSOR_VERSION_FILE"
command -v rsync >/dev/null     || die "rsync required"
command -v zip   >/dev/null     || die "zip required"
command -v unzip >/dev/null     || die "unzip required"

# --- read version -----------------------------------------------------------
CURSOR_VERSION=$(tr -d '[:space:]' < "$CURSOR_VERSION_FILE")
[[ -n "$CURSOR_VERSION" ]] || die "empty version in $CURSOR_VERSION_FILE"

# Canonical version for filename = strip the "-cursor.N" prerelease suffix
CANONICAL_VERSION="${CURSOR_VERSION%-cursor.*}"

CURSOR_NAME="aria-knowledge"
log "cursor:  $CURSOR_NAME v$CURSOR_VERSION (canonical $CANONICAL_VERSION)"

# --- stage ------------------------------------------------------------------
STAGING=$(mktemp -d -t "aria-cursor-release.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT

STAGE_DIR="$STAGING/$CURSOR_NAME"
log "staging: $STAGE_DIR"
rsync -a \
    --exclude='.DS_Store' \
    --exclude='__MACOSX' \
    --exclude='audit/' \
    --exclude='PORTING.md' \
    "$REPO_ROOT/plugin-cursor-template/" \
    "$STAGE_DIR/"

# --- zip --------------------------------------------------------------------
ZIP_PATH="$REPO_ROOT/$CURSOR_NAME-cursor-$CANONICAL_VERSION.zip"
[[ -f "$ZIP_PATH" ]] && warn "overwriting existing $ZIP_PATH"

log "zipping: $(basename "$ZIP_PATH")"
(cd "$STAGING" && zip -rXq "$ZIP_PATH" "$CURSOR_NAME")

# --- verify -----------------------------------------------------------------
junk=$(unzip -l "$ZIP_PATH" | grep -cE '(__MACOSX|\.DS_Store|audit/|PORTING\.md)' || true)
[[ "$junk" -eq 0 ]] || die "verification failed: $junk junk entries in zip"

# Cursor port has no plugin.json — verify .cursor/hooks.json + AGENTS.md instead
hooks=$(unzip -l "$ZIP_PATH" | grep -c "$CURSOR_NAME/\.cursor/hooks\.json" || true)
[[ "$hooks" -eq 1 ]] || die "verification failed: hooks.json missing or duplicated ($hooks found)"
agents=$(unzip -l "$ZIP_PATH" | grep -c "$CURSOR_NAME/AGENTS\.md" || true)
[[ "$agents" -eq 1 ]] || die "verification failed: AGENTS.md missing or duplicated ($agents found)"
rules=$(unzip -l "$ZIP_PATH" | grep -cE "$CURSOR_NAME/\.cursor/rules/.+\.mdc" || true)
[[ "$rules" -eq 5 ]] || die "verification failed: expected 5 .mdc rule files, found $rules"

# --- version-stable copy (for /releases/latest/download/<stable>.zip URLs) --
STABLE_ZIP_PATH="$REPO_ROOT/$CURSOR_NAME-cursor.zip"
cp "$ZIP_PATH" "$STABLE_ZIP_PATH"

# --- report -----------------------------------------------------------------
SIZE=$(stat -f%z "$ZIP_PATH")
ENTRIES=$(unzip -l "$ZIP_PATH" | tail -1 | awk '{print $2}')

ok "built $CURSOR_NAME cursor port v$CURSOR_VERSION"
printf '         path:    %s\n' "$ZIP_PATH"
printf '         stable:  %s\n' "$STABLE_ZIP_PATH"
printf '         size:    %s bytes\n' "$SIZE"
printf '         entries: %s files\n' "$ENTRIES"
