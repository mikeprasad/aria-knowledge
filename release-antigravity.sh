#!/usr/bin/env bash
# release-antigravity.sh — build a clean Antigravity port zip.
#
# Reads version from plugin-antigravity/version.txt (source of truth —
# Antigravity plugin.json schema has no version field per Antigravity docs).
# Stages plugin-antigravity/ CONTENTS (flat, no wrapper dir) with junk
# excluded, and emits aria-knowledge-antigravity-<version>.zip at repo root.
#
# Sibling of release.sh / release-codex.sh / release-cursor.sh. Independent
# build per the multi-port release decision: each port is built standalone.
#
# Output structure matches the prior ad-hoc 2.20.2 release zip: contents
# unpack directly into the consumer's plugin dir (no top-level wrapper).
# Includes port-generation tooling (build.sh, overlays/, tests/, PORTING.md,
# workflows/) to match historical install shape — restructure belongs in a
# version bump, not a refresh.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANTI_DIR="$REPO_ROOT/plugin-antigravity"
VERSION_FILE="$ANTI_DIR/version.txt"
PLUGIN_MANIFEST="$ANTI_DIR/plugin.json"

log()  { printf '\033[0;36m[release]\033[0m %s\n' "$*"; }
ok()   { printf '\033[0;32m[  ok   ]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[ warn  ]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[0;31m[ fail  ]\033[0m %s\n' "$*" >&2; exit 1; }

# --- preflight --------------------------------------------------------------
[[ -d "$ANTI_DIR" ]]          || die "missing $ANTI_DIR"
[[ -f "$VERSION_FILE" ]]       || die "missing $VERSION_FILE (run plugin-antigravity/build.sh to regenerate)"
[[ -f "$PLUGIN_MANIFEST" ]]    || die "missing $PLUGIN_MANIFEST"
command -v rsync   >/dev/null  || die "rsync required"
command -v zip     >/dev/null  || die "zip required"
command -v unzip   >/dev/null  || die "unzip required"

# --- read version -----------------------------------------------------------
VERSION=$(tr -d '[:space:]' < "$VERSION_FILE")
[[ -n "$VERSION" ]] || die "version.txt is empty"

NAME="aria-knowledge-antigravity"
log "antigravity: $NAME v$VERSION"

# --- stage ------------------------------------------------------------------
STAGING=$(mktemp -d -t "aria-antigravity-release.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT

log "staging: $STAGING (flat layout — no wrapper dir)"
rsync -a \
    --exclude='.DS_Store' \
    --exclude='__MACOSX' \
    --exclude='.claude/' \
    --exclude='.git/' \
    "$ANTI_DIR/" \
    "$STAGING/"

# --- zip --------------------------------------------------------------------
ZIP_PATH="$REPO_ROOT/$NAME-$VERSION.zip"
[[ -f "$ZIP_PATH" ]] && warn "overwriting existing $ZIP_PATH"

log "zipping: $(basename "$ZIP_PATH")"
(cd "$STAGING" && zip -rXq "$ZIP_PATH" .)

# --- verify -----------------------------------------------------------------
junk=$(unzip -l "$ZIP_PATH" | grep -cE '(__MACOSX|\.DS_Store|\.claude/settings|\.git/)' || true)
[[ "$junk" -eq 0 ]] || die "verification failed: $junk junk entries in zip"

manifest=$(unzip -l "$ZIP_PATH" | grep -c " plugin\.json$" || true)
[[ "$manifest" -eq 1 ]] || die "verification failed: plugin.json missing or duplicated ($manifest found)"

version_sidecar=$(unzip -l "$ZIP_PATH" | grep -c " version\.txt$" || true)
[[ "$version_sidecar" -eq 1 ]] || die "verification failed: version.txt sidecar missing or duplicated ($version_sidecar found)"

# Flat-layout sanity: no top-level wrapper dir matching the zip name
wrapper=$(unzip -l "$ZIP_PATH" | awk 'NR>3 {print $4}' | grep -cE "^$NAME/" || true)
[[ "$wrapper" -eq 0 ]] || die "verification failed: unexpected wrapper dir ($wrapper entries under $NAME/)"

# --- version-stable copy (for /releases/latest/download/<stable>.zip URLs) --
STABLE_ZIP_PATH="$REPO_ROOT/$NAME.zip"
cp "$ZIP_PATH" "$STABLE_ZIP_PATH"

# --- report -----------------------------------------------------------------
SIZE=$(stat -f%z "$ZIP_PATH")
ENTRIES=$(unzip -l "$ZIP_PATH" | tail -1 | awk '{print $2}')

ok "built $NAME v$VERSION"
printf '         path:    %s\n' "$ZIP_PATH"
printf '         stable:  %s\n' "$STABLE_ZIP_PATH"
printf '         size:    %s bytes\n' "$SIZE"
printf '         entries: %s files\n' "$ENTRIES"
