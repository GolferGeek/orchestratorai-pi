#!/bin/bash
# Sourced by runwf.sh and reviewrun.sh. Holds the one loop that watches a run and
# answers whatever it is waiting on — an attorney gate, or the final review —
# with real clicks, until the final review is approved or the run ends badly.
#
# It lives here because the first click-through lost four hours to the two halves
# drifting apart: reviewrun.sh only knew how to answer a final review, so when
# deal-memo stopped at a mid-flow gate the harness reported "review card not on
# screen" and moved on. The run stayed live, and one live run disables Start, so
# every workflow queued behind it failed with "start button never became enabled".
#
#   decide_loop <run-id> <note> <max-minutes>
#     0  final review approved by this harness
#     1  failed, stopped, or timed out
#     2  inconclusive — someone else decided it
#
# `say`, `q`, `$D` and `$T` come from the caller.

decide_loop() {
  local RID="$1" NOTE="$2" MAXMIN="$3"
  local GATES=0 SAWLIVE=0 ST PG PF GT OK FS DEC MINE a
  local DEADLINE=$(( $(date +%s) + MAXMIN*60 ))

  while [ "$(date +%s)" -lt "$DEADLINE" ]; do
    ST=$(q "select status from runs where id='$RID';")
    PG=$(q "select count(*) from checkpoints where run_id='$RID' and kind='gate' and status='pending';")
    PF=$(q "select count(*) from checkpoints where run_id='$RID' and kind='final_review' and status='pending';")

    if [ "${PG:-0}" -gt 0 ]; then
      # Confirm the gate card is really on screen before deciding.
      if [ "$($D exists gate.approve)" = "YES" ]; then
        GT=$(q "select title from checkpoints where run_id='$RID' and kind='gate' and status='pending' limit 1;")
        say "GATE visible in UI: $GT"
        $T gate.comment "$NOTE" >>"${LOG:-/dev/null}" 2>&1; sleep 1
        OK=0
        for a in 1 2 3 4 5; do
          $D ensure gate.approve >>"${LOG:-/dev/null}" 2>&1
          $D press gate.approve  >>"${LOG:-/dev/null}" 2>&1
          sleep 5
          if [ "$(q "select count(*) from checkpoints where run_id='$RID' and kind='gate' and decision_comment like '%$TOKEN%';")" -gt 0 ]; then OK=1; break; fi
          say "retry gate approve (attempt $a did not register)"
        done
        if [ "$OK" -ne 1 ]; then say "FAIL gate click never registered"; return 1; fi
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
        $T review.comment "$NOTE" >>"${LOG:-/dev/null}" 2>&1; sleep 1
        FS=pending
        for a in 1 2 3 4 5; do
          $D ensure review.approve >>"${LOG:-/dev/null}" 2>&1
          $D press  review.approve >>"${LOG:-/dev/null}" 2>&1
          sleep 5
          FS=$(q "select status from checkpoints where run_id='$RID' and kind='final_review' and decision_comment like '%$TOKEN%' limit 1;")
          [ "$FS" = "approved" ] && break
          say "retry final approve (attempt $a did not register)"
        done
        say "final review recorded by harness: ${FS:-none} ; gates=$GATES ; run status=$ST ; token=$TOKEN"
        [ "$FS" = "approved" ] && { say "PASS (gates answered: $GATES)"; return 0; }
        say "FAIL final review not approved"; return 1
      else
        say "WARN final review pending in store but the card is not on screen yet"
      fi
    fi

    # A concurrent human click can decide the final review before we reach it. Say so
    # rather than spinning to the timeout, and do not claim it as a harness pass.
    if [ "$ST" = "completed" ] && [ "${PF:-0}" -eq 0 ]; then
      DEC=$(q "select count(*) from checkpoints where run_id='$RID' and kind='final_review' and status<>'pending';")
      MINE=$(q "select count(*) from checkpoints where run_id='$RID' and kind='final_review' and decision_comment like '%$TOKEN%';")
      if [ "${DEC:-0}" -gt 0 ] && [ "${MINE:-0}" -eq 0 ]; then
        say "INCONCLUSIVE run completed but its final review was decided outside this harness (concurrent user)"
        return 2
      fi
    fi

    case "$ST" in
      failed|stopped)
        say "FAIL run status=$ST error=$(q "select substr(error,1,200) from runs where id='$RID';")"
        return 1;;
    esac

    if [ "$SAWLIVE" -eq 0 ] && [ "$(q "select count(*) from run_progress where run_id='$RID';" 2>/dev/null || echo 0)" -gt 0 ]; then
      SAWLIVE=1; say "live text rows present in store"
    fi
    sleep 15
  done
  say "FAIL timed out after $MAXMIN min (status=$(q "select status from runs where id='$RID';"))"
  return 1
}
