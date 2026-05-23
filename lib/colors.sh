#!/bin/bash
# lib/colors.sh

# Защита от повторного импорта
if [[ -n "${_LIB_COLORS_LOADED:-}" ]]; then
    return
fi
readonly _LIB_COLORS_LOADED=1

# Цвета (используем префикс C_ для краткости внутри модулей)
readonly C_RESET='\033[0m'
readonly C_RED='\033[0;31m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[0;33m'
readonly C_BLUE='\033[0;34m'
readonly C_GRAY='\033[0;90m'
readonly C_BOLD='\033[1m'

export C_RESET C_RED C_GREEN C_YELLOW C_BLUE C_GRAY C_BOLD
