#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

source "$repo_root/lib/log.sh"
source "$repo_root/lib/core/steps.sh"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

steps::reset
steps::add "first_step" "first::run" "first description"
steps::add "second_step" "second::run" "second description"

[[ "${BUILD_STEPS[0]}" == "first_step" ]] || fail "registry must preserve first step order"
[[ "${BUILD_STEPS[1]}" == "second_step" ]] || fail "registry must preserve second step order"
[[ "${BUILD_STEP_FUNCTIONS[first_step]}" == "first::run" ]] || fail "registry must store step function"
[[ "${BUILD_STEP_DESCRIPTIONS[second_step]}" == "second description" ]] || fail "registry must store step description"

if (steps::add "first_step" "other::run" "duplicate") >/tmp/rpi5-steps-duplicate.out 2>&1; then
    fail "registry must reject duplicate step names"
fi
grep -q "Duplicate step" /tmp/rpi5-steps-duplicate.out || fail "duplicate step must explain failure"
