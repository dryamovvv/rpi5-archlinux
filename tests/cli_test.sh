#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

help_output="$("$repo_root/scripts/main.sh" help)"
[[ "$help_output" == *"Usage:"* ]] || fail "help must print usage"
[[ "$help_output" == *"build"* ]] || fail "help must mention build command"
[[ "$help_output" == *"list-steps"* ]] || fail "help must mention list-steps command"

if "$repo_root/scripts/main.sh" >/tmp/rpi5-cli-no-args.out 2>&1; then
    fail "no-arg invocation must fail"
fi
grep -q "Usage:" /tmp/rpi5-cli-no-args.out || fail "no-arg invocation must print usage"

steps_output="$("$repo_root/scripts/main.sh" list-steps)"
[[ "$steps_output" == *"prepare_image"* ]] || fail "list-steps must include prepare_image"
[[ "$steps_output" == *"install_base"* ]] || fail "list-steps must include install_base"
[[ "$steps_output" == *"configure_services"* ]] || fail "list-steps must include configure_services"

only_steps_output="$("$repo_root/scripts/main.sh" --only install_base list-steps)"
[[ "$only_steps_output" == *"install_base"* ]] || fail "list-steps --only must include selected step"
[[ "$only_steps_output" != *"prepare_image"* ]] || fail "list-steps --only must exclude other steps"

skip_steps_output="$("$repo_root/scripts/main.sh" --skip install_base list-steps)"
[[ "$skip_steps_output" != *"install_base"* ]] || fail "list-steps --skip must exclude skipped step"
[[ "$skip_steps_output" == *"prepare_image"* ]] || fail "list-steps --skip must keep other steps"

"$repo_root/scripts/main.sh" validate >/dev/null

dry_run_output="$("$repo_root/scripts/main.sh" --dry-run build)"
[[ "$dry_run_output" == *$'prepare_image\tdisk_image::prepare'* ]] ||
    fail "dry-run build must print selected step functions"

only_output="$("$repo_root/scripts/main.sh" --dry-run --only install_base build)"
[[ "$only_output" == $'install_base\tbase_system::install' ]] ||
    fail "--only must select a single step"

skip_output="$("$repo_root/scripts/main.sh" --dry-run --skip install_base build)"
[[ "$skip_output" != *$'install_base\tbase_system::install'* ]] ||
    fail "--skip must remove a selected step"

if "$repo_root/scripts/main.sh" --only missing_step list-steps >/tmp/rpi5-cli-filter.out 2>&1; then
    fail "unknown --only step must fail"
fi
grep -q "Unknown --only step" /tmp/rpi5-cli-filter.out || fail "unknown --only must explain failure"

if "$repo_root/scripts/main.sh" unknown-command >/tmp/rpi5-cli-unknown.out 2>&1; then
    fail "unknown command must fail"
fi
grep -q "unknown command" /tmp/rpi5-cli-unknown.out || fail "unknown command must explain failure"
