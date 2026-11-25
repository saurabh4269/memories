#!/usr/bin/env bash
# Runs ON THE VM. Every 2 s for <secs>: ML container anon (RSS-ish) and total memory in MiB, oom_kill count, restarts.
D=${1:-120}; end=$(( $(date +%s) + D ))
while [ "$(date +%s)" -lt "$end" ]; do
  P=$(kubectl -n immich get pod -l app=immich-machine-learning -o jsonpath='{.items[0].metadata.name}')
  m=$(kubectl -n immich exec "$P" -- sh -c 'a=$(awk "/^anon /{print int(\$2/1048576)}" /sys/fs/cgroup/memory.stat); c=$(( $(cat /sys/fs/cgroup/memory.current)/1048576 )); k=$(awk "/^oom_kill /{print \$2}" /sys/fs/cgroup/memory.events); echo anon=$a total=$c oom_kill=$k' 2>/dev/null)
  st=$(kubectl -n immich get pod "$P" -o jsonpath='restarts={.status.containerStatuses[0].restartCount} last={.status.containerStatuses[0].lastState.terminated.reason}')
  echo "$(date +%T) ${m:-anon=n/a} $st"; sleep 2
done
