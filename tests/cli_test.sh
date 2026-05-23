#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

builder="$repo_root/dist/bin/rpi5-archlinux-image"
config_example="$repo_root/build.conf.example"
config_file="$repo_root/build.conf"
config_backup="$repo_root/build.conf.cli-test-backup"

cleanup() {
    if [[ -f "$config_backup" ]]; then
        mv "$config_backup" "$config_file"
    fi
    rm -f "$config_file"
}
trap cleanup EXIT

if [[ -f "$config_file" ]]; then
    mv "$config_file" "$config_backup"
fi

if "$repo_root/scripts/package.sh" >/tmp/rpi5-package-missing-config.out 2>&1; then
    fail "package must fail when build.conf is missing"
fi
grep -q "build.conf" /tmp/rpi5-package-missing-config.out ||
    fail "missing build.conf failure must explain the problem"

cp "$config_example" "$config_file"
"$repo_root/scripts/package.sh" >/dev/null

help_output="$("$builder" help)"
[[ "$help_output" == *"Usage:"* ]] || fail "help must print usage"
[[ "$help_output" == *"build"* ]] || fail "help must mention build command"
[[ "$help_output" == *"build-qemu"* ]] || fail "help must mention build-qemu command"
[[ "$help_output" == *"qemu-run"* ]] || fail "help must mention qemu-run command"
[[ "$help_output" == *"list-steps"* ]] || fail "help must mention list-steps command"

if "$builder" >/tmp/rpi5-cli-no-args.out 2>&1; then
    fail "no-arg invocation must fail"
fi
grep -q "Usage:" /tmp/rpi5-cli-no-args.out || fail "no-arg invocation must print usage"

steps_output="$("$builder" list-steps)"
[[ "$steps_output" == *"prepare_image"* ]] || fail "list-steps must include prepare_image"
[[ "$steps_output" == *"install_base"* ]] || fail "list-steps must include install_base"
[[ "$steps_output" == *"configure_services"* ]] || fail "list-steps must include configure_services"

only_steps_output="$("$builder" --only install_base list-steps)"
[[ "$only_steps_output" == *"install_base"* ]] || fail "list-steps --only must include selected step"
[[ "$only_steps_output" != *"prepare_image"* ]] || fail "list-steps --only must exclude other steps"

skip_steps_output="$("$builder" --skip install_base list-steps)"
[[ "$skip_steps_output" != *"install_base"* ]] || fail "list-steps --skip must exclude skipped step"
[[ "$skip_steps_output" == *"prepare_image"* ]] || fail "list-steps --skip must keep other steps"

"$builder" validate >/dev/null

custom_config="$(mktemp)"
sed 's/BUILD_IMAGE_SIZE="4g"/BUILD_IMAGE_SIZE="5g"/' "$config_file" >"$custom_config"
"$builder" --config "$custom_config" validate >/dev/null
rm -f "$custom_config"

dry_run_output="$("$builder" --dry-run build)"
[[ "$dry_run_output" == *$'prepare_image\tdisk_image::prepare'* ]] ||
    fail "dry-run build must print selected step functions"

qemu_dry_run_output="$("$builder" --dry-run build-qemu)"
[[ "$qemu_dry_run_output" == *$'export_qemu_boot\tqemu_boot_config::export_boot_artifacts'* ]] ||
    fail "dry-run build-qemu must include qemu boot export step"
[[ "$qemu_dry_run_output" == *$'finalize_qemu_artifacts\tqemu_boot_config::finalize_artifact_permissions'* ]] ||
    fail "dry-run build-qemu must include qemu artifact permission finalization"
[[ "$qemu_dry_run_output" != *$'configure_boot\tboot_config::configure'* ]] ||
    fail "dry-run build-qemu must not use Raspberry Pi boot configuration"

qemu_run_dry_output="$("$builder" --dry-run qemu-run)"
[[ "$qemu_run_dry_output" == *"qemu-system-aarch64"* ]] ||
    fail "dry-run qemu-run must print qemu-system-aarch64 command"

only_output="$("$builder" --dry-run --only install_base build)"
[[ "$only_output" == $'install_base\tbase_system::install' ]] ||
    fail "--only must select a single step"

skip_output="$("$builder" --dry-run --skip install_base build)"
[[ "$skip_output" != *$'install_base\tbase_system::install'* ]] ||
    fail "--skip must remove a selected step"

if "$builder" --only missing_step list-steps >/tmp/rpi5-cli-filter.out 2>&1; then
    fail "unknown --only step must fail"
fi
grep -q "Unknown --only step" /tmp/rpi5-cli-filter.out || fail "unknown --only must explain failure"

if "$builder" unknown-command >/tmp/rpi5-cli-unknown.out 2>&1; then
    fail "unknown command must fail"
fi
grep -q "unknown command" /tmp/rpi5-cli-unknown.out || fail "unknown command must explain failure"
