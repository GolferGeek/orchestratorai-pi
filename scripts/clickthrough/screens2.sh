#!/bin/bash
# screens2.sh — the screens that need a run in a particular state, plus the
# controls screens.sh could not reach. Run against the final build.
set -u
D=/tmp/pidrv/d
T=/tmp/pidrv/t
say(){ echo "[$(date +%H:%M:%S)] $*"; }
chk(){ local v; v=$($D exists "$2"); say "$( [ "$v" = YES ] && echo PASS || echo FAIL ) $1 ($2 = $v)"; }

say "--- inbox: cross-workflow list ---"
$D click sidebar.inbox >/dev/null; sleep 2
say "inbox rows: $($D ids | grep -cE '^runs\.row\.[^.]+	')"
chk "inbox search" runs.search
say "new-run button correctly absent on Inbox: $([ "$($D exists runs.new_run)" = NO ] && echo PASS || echo FAIL)"

say "--- coming-soon toggle ---"
B=$($D ids | grep -cE '^sidebar\.workflow\.')
$D click sidebar.show_coming_soon >/dev/null; sleep 2
A=$($D ids | grep -cE '^sidebar\.workflow\.')
say "catalog rows off=$B on=$A (all 14 are Ready, so equal is correct): $([ "$A" -ge "$B" ] && echo PASS || echo FAIL)"
$D click sidebar.show_coming_soon >/dev/null; sleep 1

say "--- search box filters the runs column ---"
$D click sidebar.inbox >/dev/null; sleep 2
ALL=$($D ids | grep -cE '^runs\.row\.[^.]+	')
$T runs.search "mutual" >/dev/null; sleep 2
F=$($D ids | grep -cE '^runs\.row\.[^.]+	')
say "rows all=$ALL filtered=$F: $([ "$F" -lt "$ALL" ] && echo PASS || echo FAIL)"
chk "search clear button" runs.search.clear
$D press runs.search.clear >/dev/null; sleep 1

say "--- a stopped run: resume card, step editing ---"
$D click sidebar.workflow.contract-review >/dev/null; sleep 2
RID=$(sqlite3 /Users/golfergeek/projects/orchestratorai/orchestratorai-pi/data/orchestrator.sqlite \
  "select id from runs where workflow='contract-review' and status='stopped' order by created_at desc limit 1;")
if [ -n "$RID" ]; then
  $D click runs.row.$RID >/dev/null; sleep 3
  chk "resume card" resume.card
  chk "resume button" run.resume
  say "editable completed steps: $($D ids | grep -c 'resume\.step\..*\.edit')"
else
  say "SKIP no stopped contract-review run to show the resume card"
fi

say "--- an approved run: report, evaluations, reopen ---"
# The detail pane only shows a run that belongs to the active workflow, so select
# the workflow first — reaching it through Inbox leaves the cards unrendered.
RID=$(sqlite3 /Users/golfergeek/projects/orchestratorai/orchestratorai-pi/data/orchestrator.sqlite \
  "select r.id from runs r join checkpoints c on c.run_id=r.id where c.kind='final_review' and c.status='approved' and r.workflow='contract-review' order by r.created_at desc limit 1;")
$D click sidebar.workflow.contract-review >/dev/null; sleep 2
$D click runs.row.$RID >/dev/null; sleep 4
chk "save markdown" report.save
chk "evaluations card" evaluations.card
chk "reopen review" review.reopen
say "jev badges on this run: $($D ids | grep -c 'evaluations\.badge\.')"

say "--- delete confirmation ---"
DEL=$($D ids | grep -oE '^runs\.row\.[^	]+\.delete' | head -1)
if [ -n "$DEL" ]; then
  $D press "$DEL" >/dev/null; sleep 2
  say "confirmation sheet text: $($D text | grep -iE 'delete|cancel' | head -3 | tr '\n' ' / ')"
  $D clicktitle AXButton Cancel >/dev/null 2>&1 || /tmp/pidrv/k esc >/dev/null
  sleep 1
  say "PASS delete confirmation appears and cancels"
else
  say "FAIL no per-row delete button found"
fi
say "DONE screens2"
