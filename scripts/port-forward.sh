#!/usr/bin/env bash
#
# port-forward.sh — Foreground port-forward to Dev (8080) and Prod (8081).
#
# Auto-reconnects when the underlying pod rotates (every deploy / rollback).
# Ctrl-C stops both forwards cleanly. Output from each forward is prefixed
# with [dev]/[prod] so the two streams are distinguishable.
#
set -uo pipefail

# Suppress bash's job-control "Terminated:" notices when we kill descendants.
set +m

# Recursively collect all descendant PIDs of $1 (deepest first).
descendants() {
  local pid=$1
  for child in $(pgrep -P "$pid" 2>/dev/null); do
    descendants "$child"
  done
  echo "$pid"
}

cleanup() {
  trap - INT TERM EXIT
  # Collect every descendant first, then SIGKILL them all in one go. SIGTERM
  # would let the `forward` while-loops print one more "connection lost" line
  # between kubectl dying and the loop being killed.
  local pids
  pids=$(for c in $(pgrep -P $$ 2>/dev/null); do descendants "$c"; done)
  # Redirect stderr to swallow bash's "Killed: 9" notices for processes the
  # parent shell was still waiting on.
  { [ -n "$pids" ] && kill -KILL $pids 2>/dev/null || true; wait; } 2>/dev/null
  echo
  echo "port-forward stopped."
  exit 0
}
trap cleanup INT TERM EXIT

forward() {
  local label="$1" port="$2" ns="$3"
  while true; do
    kubectl port-forward "svc/pipeline-controls-demo" "${port}:80" -n "$ns" 2>&1 \
      | sed "s/^/[$label] /"
    echo "[$label] connection lost — reconnecting in 2s…"
    sleep 2
  done
}

forward dev  8080 web-dev  &
forward prod 8081 web-prod &

sleep 1
echo
echo "Dev:  http://127.0.0.1:8080"
echo "Prod: http://127.0.0.1:8081"
echo "Ctrl-C to stop."
echo

wait
