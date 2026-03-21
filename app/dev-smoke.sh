#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

PROFILE="${RERUN_PROFILE:-dev}"
export RERUN_PROFILE="$PROFILE"

status_before="$(./dev.sh status --json 2>/dev/null || true)"
already_running=0
if grep -q '"daemonRunning" : true' <<<"$status_before"; then
    already_running=1
fi

cleanup() {
    if [[ $already_running -eq 0 ]]; then
        ./dev.sh stop >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

if [[ $already_running -eq 0 ]]; then
    ./dev.sh start >/dev/null
fi

status_running="$(./dev.sh status --json)"
grep -q "\"profile\" : \"$PROFILE\"" <<<"$status_running"
grep -q '"daemonRunning" : true' <<<"$status_running"

pid="$(sed -n 's/.*"daemonPID" : \([0-9][0-9]*\).*/\1/p' <<<"$status_running" | head -1)"
[[ -n "$pid" ]]
ps -p "$pid" -o comm= >/dev/null

if [[ $already_running -eq 0 ]]; then
    ./dev.sh stop >/dev/null
    status_stopped="$(./dev.sh status --json 2>/dev/null || true)"
    grep -q '"daemonRunning" : false' <<<"$status_stopped"
fi

echo "dev smoke ok [$PROFILE]"
