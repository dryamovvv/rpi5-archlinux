#!/bin/bash

if [[ -n "${_LIB_CORE_MODULES_LOADED:-}" ]]; then
    return
fi
readonly _LIB_CORE_MODULES_LOADED=1

modules::load() {
    local module_name=""
    local module_path=""
    local register_function=""

    for module_name in "${BUILD_MODULES[@]}"; do
        module_path="$BUILD_MODULE_DIR/${module_name}.sh"
        register_function="${module_name}::register"

        [[ -f "$module_path" ]] || log::die "Build module not found: $module_name"
        # shellcheck disable=SC1090
        source "$module_path"
        declare -F "$register_function" >/dev/null ||
            log::die "Build module '$module_name' does not define $register_function"
        "$register_function"
    done
}
