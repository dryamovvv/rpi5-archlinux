#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

[[ -f "$repo_root/scripts/main.sh" ]] || fail "missing scripts/main.sh"
[[ -f "$repo_root/conf/build.conf" ]] || fail "missing build config"
[[ -d "$repo_root/lib/core" ]] || fail "missing core library directory"
[[ -d "$repo_root/lib/modules" ]] || fail "missing module directory"
[[ ! -f "$repo_root/main.sh" ]] || fail "legacy root main.sh should be removed"
[[ ! -e "$repo_root/main_n.sh" ]] || fail "main_n.sh should be removed"
[[ ! -e "$repo_root/disk_n.sh" ]] || fail "disk_n.sh should be removed"
[[ ! -e "$repo_root/tmp2" ]] || fail "tmp2 should be removed"
[[ -f "$repo_root/conf/pacman-arm.conf" ]] || fail "missing active pacman config"
[[ -f "$repo_root/conf/reference/config.txt" ]] || fail "missing reference config.txt"
[[ -f "$repo_root/.gitignore" ]] || fail "missing .gitignore"
grep -q '^arch_root\.img$' "$repo_root/.gitignore" || fail ".gitignore must exclude raw image artifacts"
grep -q '^arch_root\.img\.xz$' "$repo_root/.gitignore" || fail ".gitignore must exclude compressed image artifacts"
grep -q '^arch_root\.img\.xz\.sha256$' "$repo_root/.gitignore" || fail ".gitignore must exclude release checksum artifacts"

grep -q './scripts/main.sh' "$repo_root/README.md" || fail "README must reference ./scripts/main.sh"
grep -q 'list-steps' "$repo_root/README.md" || fail "README must mention list-steps"
grep -q 'conf/reference/' "$repo_root/README.md" || fail "README must mention conf/reference"
grep -q 'scripts/main.sh' "$repo_root/AGENTS.md" || fail "AGENTS must reference scripts/main.sh"
grep -q '.github/workflows' "$repo_root/README.md" || fail "README must mention GitHub Actions"
