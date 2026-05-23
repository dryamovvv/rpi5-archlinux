#!/bin/bash

if [[ -n "${_LIB_CORE_RUNNER_LOADED:-}" ]]; then
    return
fi
readonly _LIB_CORE_RUNNER_LOADED=1

RUNNER_ONLY_STEP=""
RUNNER_SKIP_STEPS=()
RUNNER_DRY_RUN=0

runner::set_only() {
    RUNNER_ONLY_STEP="$1"
}

runner::add_skip() {
    RUNNER_SKIP_STEPS+=("$1")
}

runner::set_dry_run() {
    RUNNER_DRY_RUN=1
}

runner::step_is_skipped() {
    local step_name="$1"
    local skipped_step=""

    for skipped_step in "${RUNNER_SKIP_STEPS[@]}"; do
        [[ "$step_name" == "$skipped_step" ]] && return 0
    done

    return 1
}

runner::step_is_selected() {
    local step_name="$1"

    if [[ -n "$RUNNER_ONLY_STEP" && "$step_name" != "$RUNNER_ONLY_STEP" ]]; then
        return 1
    fi

    if runner::step_is_skipped "$step_name"; then
        return 1
    fi

    return 0
}

runner::validate_filters() {
    local skipped_step=""

    if [[ -n "$RUNNER_ONLY_STEP" ]]; then
        steps::exists "$RUNNER_ONLY_STEP" ||
            log::die "Unknown --only step: $RUNNER_ONLY_STEP"
    fi

    for skipped_step in "${RUNNER_SKIP_STEPS[@]}"; do
        steps::exists "$skipped_step" ||
            log::die "Unknown --skip step: $skipped_step"
    done
}

runner::print_steps() {
    local step_name=""

    runner::validate_filters

    for step_name in "${BUILD_STEPS[@]}"; do
        if runner::step_is_selected "$step_name"; then
            printf '%-24s %s\n' "$step_name" "${BUILD_STEP_DESCRIPTIONS[$step_name]}"
        fi
    done
}

runner::run() {
    local step_name=""
    local step_function=""

    runner::validate_filters

    for step_name in "${BUILD_STEPS[@]}"; do
        if ! runner::step_is_selected "$step_name"; then
            continue
        fi

        step_function="${BUILD_STEP_FUNCTIONS[$step_name]}"

        if ((RUNNER_DRY_RUN)); then
            printf '%s\t%s\n' "$step_name" "$step_function"
            continue
        fi

        log::info "Running step: $step_name"
        "$step_function"
        log::success "Step completed: $step_name"
    done
}
