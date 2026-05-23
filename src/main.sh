#!/bin/bash
#
# Entrypoint for building Arch Linux ARM images for Raspberry Pi 5.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
if [[ "$(basename "$SCRIPT_DIR")" == "bin" && "$(basename "$(dirname "$SCRIPT_DIR")")" == "dist" ]]; then
    BUILD_PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
else
    BUILD_PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi
readonly BUILD_PROJECT_ROOT
BUILD_LIB_DIR="$SCRIPT_DIR/lib"
readonly BUILD_LIB_DIR
BUILD_CORE_DIR="$BUILD_LIB_DIR/core"
readonly BUILD_CORE_DIR
# Used by src/lib/core/modules.sh after this entrypoint sources it.
BUILD_MODULE_DIR="$BUILD_LIB_DIR/modules"
# shellcheck disable=SC2034
readonly BUILD_MODULE_DIR
BUILD_DEFAULT_CONFIG="$BUILD_PROJECT_ROOT/build.conf"
readonly BUILD_DEFAULT_CONFIG
# Used by build.conf and src/lib/bootstrap.sh after this entrypoint sources them.
BUILD_PACMAN_CONF="$BUILD_PROJECT_ROOT/src/conf/pacman/pacman-arm.conf"
# shellcheck disable=SC2034
readonly BUILD_PACMAN_CONF

# shellcheck disable=SC1091
source "$BUILD_LIB_DIR/log.sh"
# shellcheck disable=SC1091
source "$BUILD_LIB_DIR/disk.sh"
# shellcheck disable=SC1091
source "$BUILD_LIB_DIR/bootstrap.sh"
# shellcheck disable=SC1091
source "$BUILD_LIB_DIR/qemu.sh"
# shellcheck disable=SC1091
source "$BUILD_CORE_DIR/config.sh"
# shellcheck disable=SC1091
source "$BUILD_CORE_DIR/deps.sh"
# shellcheck disable=SC1091
source "$BUILD_CORE_DIR/assets.sh"
# shellcheck disable=SC1091
source "$BUILD_CORE_DIR/steps.sh"
# shellcheck disable=SC1091
source "$BUILD_CORE_DIR/modules.sh"
# shellcheck disable=SC1091
source "$BUILD_CORE_DIR/runner.sh"

MAIN_CONFIG_PATH="$BUILD_DEFAULT_CONFIG"
MAIN_CONFIG_EXPLICIT=0
MAIN_USAGE_ERROR=0

main::usage() {
    cat <<'EOF'
Usage:
  rpi5-archlinux-image [options] build
  rpi5-archlinux-image [options] build-qemu
  rpi5-archlinux-image [options] qemu-run
  rpi5-archlinux-image [options] list-steps
  rpi5-archlinux-image [options] validate
  rpi5-archlinux-image [options] clean
  rpi5-archlinux-image help

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
                MAIN_CONFIG_EXPLICIT=1
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
            help|build|build-qemu|qemu-run|list-steps|validate|clean)
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
    local build_target="${1:-rpi5}"

    steps::reset
    if ((MAIN_CONFIG_EXPLICIT)); then
        config::load "$MAIN_CONFIG_PATH"
    else
        config::load_default "$MAIN_CONFIG_PATH"
    fi
    if [[ "$build_target" == "qemu" ]]; then
        config::select_qemu
    fi
    config::validate
    modules::load
}

main::require_root() {
    if [[ $EUID -ne 0 ]]; then
        command -v sudo >/dev/null 2>&1 || log::die "Root privileges are required and sudo is not installed"
        log::warn "Root privileges are required for this command. Re-running with sudo..."
        exec sudo "$0" "$@"
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
        build-qemu)
            main::load_build_context qemu
            main::build "$@"
            ;;
        qemu-run)
            main::load_build_context qemu
            qemu::run
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
