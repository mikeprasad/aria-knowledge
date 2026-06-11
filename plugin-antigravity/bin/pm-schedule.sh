#!/bin/sh
set -eu
# pm-schedule.sh [--uninstall] — render the launchd plist from pm_schedule_time and (un)load it.
# Code-only (launchd is macOS). Schedule time from pm_schedule_time (default 07:30).
BIN="$(cd "$(dirname "$0")" && pwd)"
. "$BIN/config.sh"
. "$BIN/pm-lib.sh"
LABEL="com.aria.morning"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOGDIR="$HOME/.gemini/antigravity/logs"; mkdir -p "$LOGDIR"

if [ "${1:-}" = "--uninstall" ]; then
  launchctl unload "$PLIST" 2>/dev/null || true; rm -f "$PLIST"
  apm_write_assist_status schedule "$(jq -n --arg u "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{enabled:false, updatedAt:$u}')" || true
  echo "uninstalled $LABEL"; exit 0
fi

TIME=$(pm_cfg pm_schedule_time "07:30")
HOUR=${TIME%%:*}; MIN=${TIME##*:}
# base-10 coercion: a leading-zero hour like "08"/"09" is NOT valid octal — printf '%d' would error
HOUR=$((10#$HOUR)); MIN=$((10#$MIN))
RUN="sh \"$BIN/pm-morning-run.sh\""

mkdir -p "$HOME/Library/LaunchAgents"
sed -e "s#__RUN__#$RUN#g" \
    -e "s#__LOG__#$LOGDIR/aria-pm.log#g" \
    -e "s#__ERRLOG__#$LOGDIR/aria-pm.err.log#g" \
    -e "s#__HOUR__#$HOUR#g" -e "s#__MIN__#$MIN#g" \
    "$BIN/../templates/com.aria.morning.plist.tmpl" > "$PLIST"

plutil -lint "$PLIST"
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
TIMEFMT=$(printf '%02d:%02d' "$HOUR" "$MIN")
apm_write_assist_status schedule "$(jq -n --arg t "$TIMEFMT" --arg l "$LABEL" --arg u "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{enabled:true, time:$t, label:$l, updatedAt:$u}')" || true
echo "installed $LABEL at $TIMEFMT -> $PLIST"
