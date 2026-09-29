#!/bin/bash
# mkrows.sh — one markdown row per workflow, built from the store, not from memory.
DB=/Users/golfergeek/projects/orchestratorai/orchestratorai-pi/data/orchestrator.sqlite
SINCE="${1:-2026-09-28T21:25}"
q(){ sqlite3 "$DB" "$1" 2>/dev/null; }
for WF in document-onboarding contract-review due-diligence deal-memo adversarial-brief \
          discovery-review deposition-prep cross-exam-simulation monte-carlo-trial-simulator \
          persistent-case-team compliance-audit sentinel legal-research kb-query; do
  RID=$(q "select id from runs where workflow='$WF' and (created_at>'$SINCE' or id='0af2e5a2-9795-444c-8f43-5dd8e445e239') order by created_at desc limit 1;")
  if [ -z "$RID" ]; then echo "| \`$WF\` | NOT RUN | — |"; continue; fi
  ST=$(q "select status from runs where id='$RID';")
  GT=$(q "select count(*) from checkpoints where run_id='$RID' and kind='gate';")
  GA=$(q "select count(*) from checkpoints where run_id='$RID' and kind='gate' and decision_comment like '%[ct-%';")
  FT=$(q "select status from checkpoints where run_id='$RID' and kind='final_review' limit 1;")
  FM=$(q "select count(*) from checkpoints where run_id='$RID' and kind='final_review' and decision_comment like '%[ct-%';")
  TOK=$(q "select replace(replace(substr(decision_comment,instr(decision_comment,'[ct-')),'[',''),']','') from checkpoints where run_id='$RID' and decision_comment like '%[ct-%' order by decided_at desc limit 1;")
  ERR=$(q "select substr(replace(error,'|',';'),1,110) from runs where id='$RID';")
  if [ "$ST" = completed ] && [ "$FT" = approved ] && [ "${FM:-0}" -gt 0 ]; then V=pass
  elif [ "$ST" = completed ] && [ "$FT" = approved ]; then V=inconclusive
  else V=fail; fi
  TOKNOTE=""; [ "${FM:-0}" -gt 0 ] && TOKNOTE=" (token \`$TOK\`)"
  echo "| \`$WF\` | $V | run \`${RID:0:8}\` status \`$ST\`; gates $GA/$GT answered by the harness; final review \`${FT:-none}\`$TOKNOTE${ERR:+; error: $ERR} |"
done
