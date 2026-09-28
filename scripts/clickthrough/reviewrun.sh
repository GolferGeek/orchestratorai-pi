#!/bin/bash
# reviewrun.sh <workflow-id> <run-id> [note]
# Finishes an already-started run through the real UI: resumes it if nothing is
# driving it any more, then answers whatever it is waiting on — mid-flow gates
# and the final review — with real clicks.
set -u
WF="$1"; RID="$2"; NOTE="${3:-Click-through 2026-09-28: report reviewed.}"
DB=/Users/golfergeek/projects/orchestratorai/orchestratorai-pi/data/orchestrator.sqlite
D=/tmp/pidrv/d
T=/tmp/pidrv/t
LOG=/tmp/pidrv/review-$WF.log
MAXMIN="${4:-60}"
TOKEN="ct-$(date +%s)-$$"
NOTE="$NOTE [$TOKEN]"
q(){ sqlite3 "$DB" "$1" 2>/dev/null; }
say(){ echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

. /tmp/pidrv/decideloop.sh

: > "$LOG"
$D click sidebar.workflow.$WF >/dev/null; sleep 2
$D click runs.row.$RID        >/dev/null; sleep 3

ST=$(q "select status from runs where id='$RID';")
say "run $RID status=$ST"

# A run the app orphaned (its Pi died, the app was quit) can only move again via Resume.
case "$ST" in
  stopped|failed)
    if [ "$($D exists run.resume)" = "YES" ]; then
      say "resuming orphaned run through the UI"
      $D press run.resume >/dev/null 2>&1
      # Pi has to start, load the project and rebuild the remainder of the flow before
      # the run leaves 'stopped'. Wait for that, or the decide loop reads the run's
      # pre-resume status and calls the resume a failure.
      for i in $(seq 1 40); do
        sleep 5
        ST=$(q "select status from runs where id='$RID';")
        case "$ST" in queued|running) break;; esac
      done
      case "$ST" in
        queued|running) say "resume took: status=$ST";;
        *) say "FAIL resume pressed but the run is still $ST after 200s"; exit 1;;
      esac
    else
      say "FAIL run is $ST and no Resume button is on screen"; exit 1
    fi;;
esac

decide_loop "$RID" "$NOTE" "$MAXMIN"
RC=$?
case "$RC" in
  0) say "PASS $WF (resumed run $RID)";;
  2) say "INCONCLUSIVE $WF";;
  *) say "FAIL $WF";;
esac
exit $RC
