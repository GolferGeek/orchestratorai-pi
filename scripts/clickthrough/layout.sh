#!/bin/bash
# layout.sh — measure the three panes and every name in them, at a given window size.
set -u
D=/tmp/pidrv/d
W="${1:-1440}"; H="${2:-900}"
echo "### window ${W}x${H} -> $($D winsize "$W" "$H")"
echo "pane frames:"
for id in sidebar.inbox runs.search launch.start; do
  printf '  %-16s %s\n' "$id" "$($D frame $id)"
done
echo "sidebar names:"
for w in document-onboarding contract-review due-diligence deal-memo adversarial-brief \
         discovery-review deposition-prep cross-exam-simulation monte-carlo-trial-simulator \
         persistent-case-team compliance-audit sentinel legal-research kb-query; do
  printf '  %s\n' "$($D truncated sidebar.workflow.$w 13)"
done
echo "run names (inbox, every row):"
$D click sidebar.inbox >/dev/null; sleep 2
for id in $($D ids | awk -F'\t' '$2=="AXStaticText" && $1 ~ /^runs\.row\.[^.]+$/ {print $1}'); do
  printf '  %s\n' "$($D truncated "$id" 12)"
done
