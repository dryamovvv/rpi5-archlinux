#!/bin/bash

if [[ -n "${_LIB_CORE_STEPS_LOADED:-}" ]]; then
    return
fi
readonly _LIB_CORE_STEPS_LOADED=1

declare -ag BUILD_STEPS=()
declare -Ag BUILD_STEP_FUNCTIONS=()
declare -Ag BUILD_STEP_DESCRIPTIONS=()

steps::reset() {
    BUILD_STEPS=()
    BUILD_STEP_FUNCTIONS=()
    BUILD_STEP_DESCRIPTIONS=()
}

steps::exists() {
    local step_name="$1"

    [[ -n "${BUILD_STEP_FUNCTIONS[$step_name]:-}" ]]
}

steps::add() {
    local step_name="$1"
    local step_function="$2"
    local step_description="$3"

    log::assert_not_empty "$step_name" "step name"
    log::assert_not_empty "$step_function" "step function"
    log::assert_not_empty "$step_description" "step description"

    if steps::exists "$step_name"; then
        log::die "Duplicate step: $step_name"
    fi

    BUILD_STEPS+=("$step_name")
    BUILD_STEP_FUNCTIONS["$step_name"]="$step_function"
    BUILD_STEP_DESCRIPTIONS["$step_name"]="$step_description"
}

steps::print() {
    local step_name=""

    for step_name in "${BUILD_STEPS[@]}"; do
        printf '%-24s %s\n' "$step_name" "${BUILD_STEP_DESCRIPTIONS[$step_name]}"
    done
}
