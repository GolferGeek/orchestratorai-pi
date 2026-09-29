#!/bin/bash
# screens.sh — walks every screen and asserts its controls are really on screen.
set -u
D=/tmp/pidrv/d
say(){ echo "[$(date +%H:%M:%S)] $*"; }
chk(){ # chk <label> <identifier>
  local v; v=$($D exists "$2")
  say "$( [ "$v" = YES ] && echo PASS || echo FAIL ) $1 ($2 = $v)"
}
say "--- sidebar / left nav ---"
for w in document-onboarding contract-review due-diligence deal-memo adversarial-brief \
         discovery-review deposition-prep cross-exam-simulation monte-carlo-trial-simulator \
         persistent-case-team compliance-audit sentinel legal-research kb-query; do
  chk "catalog row $w" sidebar.workflow.$w
done
chk "inbox row" sidebar.inbox
chk "show-coming-soon toggle" sidebar.show_coming_soon

say "--- inbox screen ---"
$D click sidebar.inbox >/dev/null; sleep 2
chk "inbox runs search" runs.search
say "inbox rows: $($D ids | grep -c '^runs\.row\.[^.]*	')"

say "--- runs column (contract-review) ---"
$D click sidebar.workflow.contract-review >/dev/null; sleep 2
chk "search field" runs.search
chk "new run button" runs.new_run
chk "clear approved" runs.clear_approved
say "rows: $($D ids | grep -c '^runs\.row\.[^.]*	')"
say "per-row delete buttons: $($D ids | grep -c 'runs\.row\..*\.delete')"

say "--- launch / task card ---"
$D press runs.new_run >/dev/null; sleep 2
chk "choose file" launch.choose_file
chk "sample button" launch.sample.contract-review-sample-0
chk "model field" context.model
chk "start button" launch.start
say "start enabled: $($D enabled launch.start)"
say "context fields: $($D ids | grep -c 'context\.field\.')"

say "--- a completed run: report, evaluations, human review ---"
$D click runs.row.05878a92-c90c-485f-be6b-f3ab6c784750 >/dev/null; sleep 3
chk "save markdown" report.save
chk "evaluations card" evaluations.card
chk "reopen review" review.reopen
say "step outputs / resume rows: $($D ids | grep -c 'resume\.step\.')"

say "--- an orphaned run: resume card ---"
# Find one rather than hardcoding an id: the run this was written against has since
# been resumed and approved, and a stale id made the check report a false failure.
ORPH=$(sqlite3 /Users/golfergeek/projects/orchestratorai/orchestratorai-pi/data/orchestrator.sqlite \
  "select workflow||' '||id from runs where status in ('stopped','failed')
     and workflow in ('document-onboarding','contract-review','due-diligence','deal-memo','adversarial-brief',
                      'discovery-review','deposition-prep','cross-exam-simulation','monte-carlo-trial-simulator',
                      'persistent-case-team','compliance-audit','sentinel','legal-research','kb-query')
   order by created_at desc limit 1;")
if [ -n "$ORPH" ]; then
  set -- $ORPH
  $D click sidebar.workflow.$1 >/dev/null; sleep 2
  $D click runs.row.$2 >/dev/null; sleep 3
  chk "resume card" resume.card
  chk "resume button" run.resume
else
  say "SKIP no stopped or failed run to show the resume card"
fi

say "--- trust card ---"
say "trust.approve present (absent = project already trusted): $($D exists trust.approve)"
say "DONE screens"
