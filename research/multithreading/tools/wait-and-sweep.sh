#!/bin/sh
# Wait for the machine to go quiet, then run the full sweep (unplugged).
# Quiet = fileproviderd < 20% CPU and total CPU across all processes < 250%
# for 3 samples in a row, sampled every 60 s.  (The 1-minute load average is
# not a usable idleness test on this machine: it sits near 4 while only about
# 1.5 of 10 cores are actually busy.)  Gives up after 60 samples or if the battery falls
# below 40%.
set -u
here=$(cd "$(dirname "$0")" && pwd)
L=$here/../logs
quiet=0
for i in $(seq 1 60); do
  fp=$(ps -Ao pcpu,comm | grep fileproviderd | awk '{s+=$1} END {print int(s+0)}')
  load=$(sysctl -n vm.loadavg | awk '{print $2}')
  cpu=$(ps -Ao pcpu | awk '{s+=$1} END {print int(s)}')
  pct=$(pmset -g batt | grep -o '[0-9]*%' | tr -d '%')
  printf "%s fileproviderd=%s load=%s cpu=%s%% batt=%s%%\n" "$(date +%H:%M:%S)" "$fp" "$load" "$cpu" "$pct" >> "$L/wait-and-sweep.log"
  if [ "${pct:-100}" -lt 40 ]; then echo "battery below 40%, not starting" >> "$L/wait-and-sweep.log"; exit 2; fi
  if [ "$fp" -lt 20 ] && [ "$cpu" -lt 250 ]; then
    quiet=$((quiet+1))
  else
    quiet=0
  fi
  if [ $quiet -ge 3 ]; then
    echo "quiet, starting sweep at $(date +%H:%M:%S)" >> "$L/wait-and-sweep.log"
    OUT=$L/pool-sweep-idle.jsonl "$here/pool-bench.sh" > "$L/pool-sweep-idle.progress" 2>&1
    echo "sweep finished at $(date +%H:%M:%S)" >> "$L/wait-and-sweep.log"
    exit 0
  fi
  sleep 60
done
echo "gave up waiting after 60 minutes" >> "$L/wait-and-sweep.log"
exit 1
