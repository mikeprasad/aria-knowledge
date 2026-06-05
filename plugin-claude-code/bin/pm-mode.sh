#!/bin/sh
set -eu
# pm-mode.sh -> prints "review" or "generate" for a bare /aria-assist invocation.
# Digest dir = pm_digest_dir, default <knowledge_folder>/pm-reviews.
BIN="$(cd "$(dirname "$0")" && pwd)"
. "$BIN/config.sh"
. "$BIN/pm-lib.sh"
OUTDIR=$(apm_expand_tilde "$(pm_cfg pm_digest_dir "$KT_KNOWLEDGE_FOLDER/pm-reviews")")
apm_decide_mode "$OUTDIR"
