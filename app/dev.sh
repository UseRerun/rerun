#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

PROFILE="${RERUN_PROFILE:-dev}"
export RERUN_PROFILE="$PROFILE"

args=("$@")
if [[ ${1-} == "start" ]]; then
    has_target=0
    for arg in "${args[@]}"; do
        if [[ "$arg" == "--target" || "$arg" == --target=* ]]; then
            has_target=1
            break
        fi
    done
    if [[ $has_target -eq 0 ]]; then
        args+=("--target" "local")
    fi
fi

swift run rerun "${args[@]}"
