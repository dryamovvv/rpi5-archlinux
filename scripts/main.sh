#!/bin/bash
#
# Entrypoint for building Arch Linux ARM images for Raspberry Pi 5.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
BUILD_PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly BUILD_PROJECT_ROOT
BUILD_LIB_DIR="$BUILD_PROJECT_ROOT/lib"
readonly BUILD_LIB_DIR
BUILD_CORE_DIR="$BUILD_LIB_DIR/core"
readonly BUILD_CORE_DIR
# Used by lib/core/modules.sh after this entrypoint sources it.
BUILD_MODULE_DIR="$BUILD_LIB_DIR/modules"
# shellcheck disable=SC2034
readonly BUILD_MODULE_DIR
BUILD_DEFAULT_CONFIG="$BUILD_PROJECT_ROOT/conf/build.conf"
readonly BUILD_DEFAULT_CONFIG
# Used by conf/build.conf and lib/bootstrap.sh after this entrypoint sources them.
BUILD_PACMAN_CONF="$BUILD_PROJECT_ROOT/conf/pacman-arm.conf"
# shellcheck disable=SC2034
readonly BUILD_PACMAN_CONF

# shellcheck disable=SC1091
source "$BUILD_LIB_DIR/log.sh"
# shellcheck disable=SC1091
source "$BUILD_LIB_DIR/disk.sh"
# shellcheck disable=SC1091
source "$BUILD_LIB_DIR/bootstrap.sh"
# shellcheck disable=SC1091
source "$BUILD_CORE_DIR/config.sh"
# shellcheck disable=SC1091
source "$BUILD_CORE_DIR/deps.sh"
# shellcheck disable=SC1091
source "$BUILD_CORE_DIR/steps.sh"
# shellcheck disable=SC1091
source "$BUILD_CORE_DIR/modules.sh"
# shellcheck disable=SC1091
source "$BUILD_CORE_DIR/runner.sh"

MAIN_CONFIG_PATH="$BUILD_DEFAULT_CONFIG"
MAIN_USAGE_ERROR=0

main::usage() {
    cat <<'EOF'
Usage:
  scripts/main.sh [options] build
  scripts/main.sh [options] list-steps
  scripts/main.sh [options] validate
  scripts/main.sh [options] clean
  scripts/main.sh help

Options:
  --config PATH   Use an alternate build config.
  --only STEP     Run only one registered build step.
  --skip STEP     Skip one registered build step. Can be repeated.
  --dry-run       Print selected build steps instead of running them.
  --help          Show this help.
EOF
}

main::parse_args() {
    MAIN_COMMAND=""
    MAIN_USAGE_ERROR=0

    while (($# > 0)); do
        case "$1" in
            --config)
                (($# >= 2)) || log::die "--config requires a path"
                MAIN_CONFIG_PATH="$2"
                shift 2
                ;;
            --only)
                (($# >= 2)) || log::die "--only requires a step name"
                runner::set_only "$2"
                shift 2
                ;;
            --skip)
                (($# >= 2)) || log::die "--skip requires a step name"
                runner::add_skip "$2"
                shift 2
                ;;
            --dry-run)
                runner::set_dry_run
                shift
                ;;
            --help|-h)
                MAIN_COMMAND="help"
                shift
                ;;
            help|build|list-steps|validate|clean)
                [[ -z "$MAIN_COMMAND" ]] || log::die "Only one command can be specified"
                MAIN_COMMAND="$1"
                shift
                ;;
            *)
                log::die "unknown command or option: $1"
                ;;
        esac
    done

    if [[ -z "$MAIN_COMMAND" ]]; then
        MAIN_COMMAND="help"
        MAIN_USAGE_ERROR=1
    fi
}

main::load_build_context() {
    steps::reset
    config::load "$MAIN_CONFIG_PATH"
    config::validate
    modules::load
}

main::require_root() {
    if [[ $EUID -ne 0 ]]; then
        log::warn "Root privileges are required. Re-running with sudo..."
        exec sudo -E "$0" "$@"
    fi
}

main::build() {
    if ((RUNNER_DRY_RUN == 0)); then
        main::require_root "$@"
        trap 'disk::cleanup "$BUILD_MOUNT_ROOT"' EXIT SIGINT SIGTERM
        deps::validate_build_commands
    fi

    runner::run
    if ((RUNNER_DRY_RUN == 0)); then
        log::success "Image build completed"
    fi
}

main::clean() {
    main::require_root "$@"
    disk::cleanup "$BUILD_MOUNT_ROOT"
}

main() {
    main::parse_args "$@"

    case "$MAIN_COMMAND" in
        help)
            main::usage
            if ((MAIN_USAGE_ERROR)); then
                exit 1
            fi
            ;;
        build)
            main::load_build_context
            main::build "$@"
            ;;
        list-steps)
            main::load_build_context
            runner::print_steps
            ;;
        validate)
            main::load_build_context
            runner::validate_filters
            deps::validate_build_commands
            log::success "Build configuration is valid"
            ;;
        clean)
            main::load_build_context
            main::clean "$@"
            ;;
        *)
            log::die "unknown command: $MAIN_COMMAND"
            ;;
    esac
}

main "$@"
