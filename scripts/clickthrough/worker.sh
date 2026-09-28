#!/bin/bash
# Runs inside Terminal.app so children inherit Terminal's Accessibility grant.
d=/tmp/pidrv
echo "pidrv worker up $(date)" > "$d/worker.log"
while true; do
  if [ -f "$d/in.sh" ]; then
    mv "$d/in.sh" "$d/running.sh"
    bash "$d/running.sh" > "$d/out.txt" 2>&1
    echo $? > "$d/rc.txt"
    rm -f "$d/running.sh"
    touch "$d/done"
  fi
  sleep 0.1
done
