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
  say "FAIL start button never became enabled (last=$EN)"; exit 1
fi

BEFORE=$(q "select count(*) from runs;")
$D press launch.start >>"$LOG" 2>&1
say "Start pressed"

# Wait for the new run row to exist, then track it.
RID=""
for i in $(seq 1 60); do
  sleep 3
  RID=$(q "select id from runs where workflow='$WF' order by created_at desc limit 1;")
  ST=$(q "select status from runs where id='$RID';")
  CT=$(q "select created_at from runs where id='$RID';")
  # only accept a run created in the last few minutes
  if [ -n "$RID" ] && [ "$(q "select count(*) from runs;")" -gt "$BEFORE" ]; then break; fi
done
if [ -z "$RID" ]; then say "FAIL no run row appeared"; exit 1; fi
say "run id: $RID"

# stop button should be visible while running
if [ "$($D exists launch.stop)" = "YES" ]; then say "launch.stop visible while running"; fi

GATES=0
SAWLIVE=0
DEADLINE=$(( $(date +%s) + MAXMIN*60 ))
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  ST=$(q "select status from runs where id='$RID';")
  PG=$(q "select count(*) from checkpoints where run_id='$RID' and kind='gate' and status='pending';")
  PF=$(q "select count(*) from checkpoints where run_id='$RID' and kind='final_review' and status='pending';")

  if [ "${PG:-0}" -gt 0 ]; then
    # Confirm the gate card is really on screen before deciding.
    if [ "$($D exists gate.approve)" = "YES" ]; then
      GT=$(q "select title from checkpoints where run_id='$RID' and kind='gate' and status='pending' limit 1;")
      say "GATE visible in UI: $GT"
      $T gate.comment "$NOTE" >>"$LOG" 2>&1; sleep 1
      OK=0
      for a in 1 2 3 4 5; do
        $D ensure gate.approve >>"$LOG" 2>&1
        $D press gate.approve  >>"$LOG" 2>&1
        sleep 5
        if [ "$(q "select count(*) from checkpoints where run_id='$RID' and kind='gate' and decision_comment like '%$TOKEN%';")" -gt 0 ]; then OK=1; break; fi
        say "retry gate approve (attempt $a did not register)"
      done
      if [ "$OK" -ne 1 ]; then say "FAIL $WF gate click never registered"; exit 1; fi
      GATES=$((GATES+1))
      say "gate approved via UI (#$GATES)"
      sleep 8
      continue
    else
      say "WARN gate pending in store but gate card not on screen yet"
    fi
  fi

  if [ "${PF:-0}" -gt 0 ]; then
    if [ "$($D exists review.approve)" = "YES" ]; then
      say "final review card visible in UI"
      $T review.comment "$NOTE" >>"$LOG" 2>&1; sleep 1
      FS=pending
      for a in 1 2 3 4 5; do
        $D ensure review.approve >>"$LOG" 2>&1
        $D press review.approve  >>"$LOG" 2>&1
        sleep 5
        FS=$(q "select status from checkpoints where run_id='$RID' and kind='final_review' and decision_comment like '%$TOKEN%' limit 1;")
        [ "$FS" = "approved" ] && break
        say "retry final approve (attempt $a did not register)"
      done
      say "final review recorded by harness: ${FS:-none} ; gates=$GATES ; run status=$ST ; token=$TOKEN"
      if [ "$FS" = "approved" ]; then say "PASS $WF"; exit 0; fi
      say "FAIL $WF final review not approved"; exit 1
    fi
  fi

  # A concurrent human click can decide the final review before we reach it. Say so
  # rather than spinning to the timeout, and do not claim it as a harness pass.
  if [ "$ST" = "completed" ] && [ "${PF:-0}" -eq 0 ]; then
    DEC=$(q "select count(*) from checkpoints where run_id='$RID' and kind='final_review' and status<>'pending';")
    MINE=$(q "select count(*) from checkpoints where run_id='$RID' and kind='final_review' and decision_comment like '%$TOKEN%';")
    if [ "${DEC:-0}" -gt 0 ] && [ "${MINE:-0}" -eq 0 ]; then
      say "INCONCLUSIVE $WF run completed but its final review was decided outside this harness (concurrent user)"
      exit 2
    fi
  fi

  case "$ST" in
    failed|stopped)
      say "FAIL $WF run status=$ST error=$(q "select substr(error,1,200) from runs where id='$RID';")"
      exit 1;;
  esac

  if [ "$SAWLIVE" -eq 0 ] && [ "$(q "select count(*) from run_progress where run_id='$RID';" 2>/dev/null || echo 0)" -gt 0 ]; then
    SAWLIVE=1; say "live text rows present in store"
  fi
  sleep 15
done
say "FAIL $WF timed out after $MAXMIN min (status=$(q "select status from runs where id='$RID';"))"
exit 1
