#!/bin/sh
# usage-metrics.sh — deterministic value/ROI metrics over the user's knowledge corpus.
# Emits a labeled key-value block on stdout. Consumed by skills/audit-usage.
# Usage: sh usage-metrics.sh   (reads KT_KNOWLEDGE_FOLDER via config.sh)
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/config.sh" 2>/dev/null || true
KF="${KT_KNOWLEDGE_FOLDER}"
if [ -z "$KF" ] || [ ! -d "$KF" ]; then
  echo "USAGE_METRICS_ERROR knowledge_folder-unset-or-missing"
  exit 0
fi

# --- Prospect verdict distribution (primary key only) ---
pdir="$KF/logs/prospect"
p_total=0; p_pwc=0; p_clean=0; p_hold=0
if [ -d "$pdir" ]; then
  for f in "$pdir"/*.md; do
    [ -e "$f" ] || continue
    v=$(grep -m1 '^overall_verdict:' "$f" 2>/dev/null | sed 's/^overall_verdict: *//')
    [ -z "$v" ] && continue
    p_total=$((p_total+1))
    case "$v" in
      PROCEED-WITH-CHANGES) p_pwc=$((p_pwc+1)) ;;
      PROCEED)              p_clean=$((p_clean+1)) ;;
      *)                    p_hold=$((p_hold+1)) ;;
    esac
  done
fi
echo "PROSPECT_TOTAL $p_total"
echo "PROSPECT_PWC $p_pwc"
echo "PROSPECT_CLEAN $p_clean"
echo "PROSPECT_HOLD $p_hold"

# --- Prospect month buckets ---
if [ -d "$pdir" ]; then
  for ym in $(ls "$pdir" 2>/dev/null | grep -oE '^[0-9]{4}-[0-9]{2}' | sort -u); do
    m_pwc=0; m_clean=0; m_hold=0
    for f in "$pdir"/"$ym"-*.md; do
      [ -e "$f" ] || continue
      v=$(grep -m1 '^overall_verdict:' "$f" 2>/dev/null | sed 's/^overall_verdict: *//')
      [ -z "$v" ] && continue
      case "$v" in
        PROCEED-WITH-CHANGES) m_pwc=$((m_pwc+1)) ;;
        PROCEED)              m_clean=$((m_clean+1)) ;;
        *)                    m_hold=$((m_hold+1)) ;;
      esac
    done
    echo "PROSPECT_MONTH $ym $m_pwc $m_clean $m_hold"
  done
fi

# --- Retrospect outcome distribution + per-fix-verdict presence ---
rdir="$KF/logs/retrospect"
r_total=0; r_closed=0; r_partial=0; r_mixed=0; r_unres=0; r_vfiles=0
if [ -d "$rdir" ]; then
  for f in "$rdir"/*.md; do
    [ -e "$f" ] || continue
    o=$(grep -m1 '^overall_outcome:' "$f" 2>/dev/null | sed 's/^overall_outcome: *//')
    if [ -n "$o" ]; then
      r_total=$((r_total+1))
      case "$o" in
        closed)     r_closed=$((r_closed+1)) ;;
        partial)    r_partial=$((r_partial+1)) ;;
        mixed)      r_mixed=$((r_mixed+1)) ;;
        unresolved) r_unres=$((r_unres+1)) ;;
      esac
    fi
    if grep -qE '✅|KEEP|REVERT|REVISE' "$f" 2>/dev/null; then
      r_vfiles=$((r_vfiles+1))
    fi
  done
fi
echo "RETRO_TOTAL $r_total"
echo "RETRO_CLOSED $r_closed"
echo "RETRO_PARTIAL $r_partial"
echo "RETRO_MIXED $r_mixed"
echo "RETRO_UNRESOLVED $r_unres"
echo "RETRO_VERDICT_FILES $r_vfiles"

# --- Retrospect month buckets (closed / total) ---
if [ -d "$rdir" ]; then
  for ym in $(ls "$rdir" 2>/dev/null | grep -oE '^[0-9]{4}-[0-9]{2}' | sort -u); do
    m_c=0; m_t=0
    for f in "$rdir"/"$ym"-*.md; do
      [ -e "$f" ] || continue
      o=$(grep -m1 '^overall_outcome:' "$f" 2>/dev/null | sed 's/^overall_outcome: *//')
      [ -z "$o" ] && continue
      m_t=$((m_t+1))
      [ "$o" = "closed" ] && m_c=$((m_c+1))
    done
    echo "RETRO_MONTH $ym $m_c $m_t"
  done
fi

# --- Canonical pattern count (cross-cutting library) ---
pat="$KF/rules/retrospect-patterns.md"
if [ -f "$pat" ]; then
  pc=$(grep -cE '^## [a-z0-9]+(-[a-z0-9]+)+$' "$pat" 2>/dev/null || echo 0)
else
  pc=0
fi
echo "PATTERN_COUNT $pc"

# --- Corpus: per-content-dir .md counts (exclude README.md) ---
corpus_total=0
for d in approaches references rules guides decisions projects; do
  if [ -d "$KF/$d" ]; then
    n=$(find "$KF/$d" -name '*.md' ! -name 'README.md' 2>/dev/null | wc -l | tr -d ' ')
  else
    n=0
  fi
  echo "CORPUS_$d $n"
  corpus_total=$((corpus_total+n))
done
echo "CORPUS_TOTAL $corpus_total"

# --- Cost surface: skill-discovery description bytes over the INSTALLED plugin ---
skills_dir="$DIR/../skills"
sd_bytes=0; sk_count=0
if [ -d "$skills_dir" ]; then
  for sf in "$skills_dir"/*/SKILL.md; do
    [ -e "$sf" ] || continue
    b=$(awk '/^description:/{flag=1; print; next} flag && /^[a-z_-]+:/{flag=0} flag {print}' "$sf" | wc -c | tr -d ' ')
    sd_bytes=$((sd_bytes+b)); sk_count=$((sk_count+1))
  done
fi
echo "SKILL_DISCOVERY_BYTES $sd_bytes"
echo "SKILL_COUNT $sk_count"

# --- Audit-pass count (knowledge-audit-log entries) ---
alog="$KF/logs/knowledge-audit-log.md"
if [ -f "$alog" ]; then
  ap=$(grep -cE '^## ' "$alog" 2>/dev/null || echo 0)
else
  ap=0
fi
echo "AUDIT_PASSES $ap"
