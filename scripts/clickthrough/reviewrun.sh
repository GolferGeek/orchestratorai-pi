#!/bin/bash
# reviewrun.sh <workflow-id> <run-id> [note]
# Records the final attorney review for an already-completed run, through the real UI.
set -u
WF="$1"; RID="$2"; NOTE="${3:-Click-through 2026-09-28: report reviewed.}"
DB=/Users/golfergeek/projects/orchestratorai/orchestratorai-pi/data/orchestrator.sqlite
D=/tmp/pidrv/d
TOKEN="ct-$(date +%s)-$$"
NOTE="$NOTE [$TOKEN]"
q(){ sqlite3 "$DB" "$1" 2>/dev/null; }
say(){ echo "[$(date +%H:%M:%S)] $*"; }

$D click sidebar.workflow.$WF >/dev/null; sleep 2
$D click runs.row.$RID        >/dev/null; sleep 3
if [ "$($D exists review.approve)" != "YES" ]; then say "FAIL review card not on screen for $RID"; exit 1; fi
say "final review card visible in UI"
$D click review.comment >/dev/null; sleep 1
FOC=$($D focused)
case "$FOC" in *review.comment*) ;; *) say "FAIL could not focus review.comment (focus=$FOC)"; exit 1;; esac
/tmp/pidrv/r osascript /tmp/pidrv/keys.scpt type "$NOTE" >/dev/null; sleep 1
VAL=$($D val review.comment)
case "$VAL" in *"$TOKEN"*) say "note typed into the field" ;; *) say "FAIL note did not reach the field ($VAL)"; exit 1;; esac
for a in 1 2 3 4 5; do
  $D ensure review.approve >/dev/null 2>&1
  $D press  review.approve >/dev/null 2>&1
  sleep 4
  if [ "$(q "select count(*) from checkpoints where run_id='$RID' and kind='final_review' and status='approved' and decision_comment like '%$TOKEN%';")" -gt 0 ]; then
    say "PASS review recorded by harness (token $TOKEN)"; exit 0
  fi
  say "retry approve (attempt $a)"
done
say "FAIL approve never registered"; exit 1
