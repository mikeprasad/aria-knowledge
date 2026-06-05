#!/bin/sh
set -eu
# pm-notify.sh TITLE BODY [--dry-run]
# Desktop banner (always-works) + best-effort iMessage-to-self. Never fails the caller.
# Config via config.sh + pm_cfg: pm_notify_desktop, pm_notify_imessage, pm_imessage_handle.
BIN="$(cd "$(dirname "$0")" && pwd)"
. "$BIN/config.sh"
. "$BIN/pm-lib.sh"
TITLE="${1:-ARIA}"; BODY="${2:-}"; DRY=""
[ "${3:-}" = "--dry-run" ] && DRY=1

esc() { printf '%s' "$1" | sed 's/"/\\"/g'; }

DESK=$(pm_cfg pm_notify_desktop true)
if [ "$DESK" = "true" ]; then
  cmd="display notification \"$(esc "$BODY")\" with title \"$(esc "$TITLE")\""
  if [ -n "$DRY" ]; then printf 'osascript -e %s\n' "$cmd"
  else osascript -e "$cmd" >/dev/null 2>&1 || true; fi
fi

IM=$(pm_cfg pm_notify_imessage false)
HANDLE=$(pm_cfg pm_imessage_handle "")
if [ "$IM" = "true" ] && [ -n "$HANDLE" ]; then
  msg="$TITLE — $BODY"
  script="tell application \"Messages\" to send \"$(esc "$msg")\" to buddy \"$(esc "$HANDLE")\" of (1st service whose service type = iMessage)"
  if [ -n "$DRY" ]; then printf 'osascript -e %s\n' "$script"
  else osascript -e "$script" >/dev/null 2>&1 || true; fi
fi
exit 0
