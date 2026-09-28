#!/bin/bash
# runwf.sh <workflow-id> [gate-note] [max-minutes]
# Drives one workflow through the real UI: select -> new run -> demo sample -> Start,
# then answers every attorney gate and the final review with real clicks.
# The store is only used to decide *when* to look; every decision is a UI click.
set -u
WF="$1"
NOTE="${2:-Verified in the 2026-09-28 click-through.}"
# A person may be using the app at the same time. Tag every decision this run records
# with a unique token and only count a decision whose stored note carries it, so a
# concurrent human click can never be mistaken for the harness's.
TOKEN="ct-$(date +%s)-$$"
NOTE="$NOTE [$TOKEN]"
MAXMIN="${3:-60}"
REPO=/Users/golfergeek/projects/orchestratorai/orchestratorai-pi
DB=$REPO/data/orchestrator.sqlite
D=/tmp/pidrv/d
T=/tmp/pidrv/t
LOG=/tmp/pidrv/wf-$WF.log

say() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }
q()   { sqlite3 "$DB" "$1" 2>/dev/null; }

. /tmp/pidrv/decideloop.sh

: > "$LOG"
say "=== $WF ==="

$D click sidebar.workflow.$WF >>"$LOG" 2>&1; sleep 2
$D press runs.new_run         >>"$LOG" 2>&1; sleep 2

# Demo sample, when the workflow declares one.
if [ "$($D exists launch.sample.$WF-sample-0)" = "YES" ]; then
  $D press launch.sample.$WF-sample-0 >>"$LOG" 2>&1; sleep 2
  say "sample: launch.sample.$WF-sample-0 selected"
else
  say "sample: none (typed fields only)"
fi

# Start is disabled while any run is still live (one Pi process at a time), so wait
# for the previous run to be fully wound down rather than failing on a race.
EN=""
for i in $(seq 1 40); do
  EN=$($D enabled launch.start)
  [ "$EN" = "ENABLED" ] && break
  sleep 5
done
if [ "$EN" != "ENABLED" ]; then
  # Name the run that is holding the app, so this reads as a diagnosis instead of a symptom.
  say "FAIL start button never became enabled (last=$EN); live runs: $(q "select id||' '||workflow||' '||status from runs where status in ('queued','running');" | tr '\n' ',')"
  exit 1
fi

BEFORE=$(q "select count(*) from runs;")
$D press launch.start >>"$LOG" 2>&1
say "Start pressed"

# Wait for the new run row to exist, then track it.
RID=""
for i in $(seq 1 60); do
  sleep 3
  RID=$(q "select id from runs where workflow='$WF' order by created_at desc limit 1;")
  # only accept a run created after we pressed Start
  if [ -n "$RID" ] && [ "$(q "select count(*) from runs;")" -gt "$BEFORE" ]; then break; fi
done
if [ -z "$RID" ]; then say "FAIL no run row appeared"; exit 1; fi
say "run id: $RID"

# stop button should be visible while running
if [ "$($D exists launch.stop)" = "YES" ]; then say "launch.stop visible while running"; fi

decide_loop "$RID" "$NOTE" "$MAXMIN"
RC=$?
case "$RC" in
  0) say "PASS $WF";;
  2) say "INCONCLUSIVE $WF";;
  *) say "FAIL $WF";;
esac
exit $RC
