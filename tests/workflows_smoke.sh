#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

[[ -f "$repo_root/.github/workflows/ci.yml" ]] || fail "missing ci workflow"
[[ -f "$repo_root/.github/workflows/release.yml" ]] || fail "missing release workflow"

if grep -q 'docker-build\|docker build\|rpi5-archlinux-builder' "$repo_root/.github/workflows/ci.yml"; then
    fail "ci workflow must not build a custom builder image"
fi
grep -q 'tags:' "$repo_root/.github/workflows/release.yml" \
    || fail "release workflow must trigger on tags"
grep -q '"v\*"' "$repo_root/.github/workflows/release.yml" \
    || fail "release workflow must target v* tags"
grep -q 'gh release create' "$repo_root/.github/workflows/release.yml" \
    || fail "release workflow must publish a GitHub release"
grep -q 'runs-on: ubuntu-24.04-arm' "$repo_root/.github/workflows/release.yml" \
    || fail "release workflow must use the native arm64 runner"
grep -q 'sudo apt-get install -y' "$repo_root/.github/workflows/release.yml" \
    || fail "release workflow must install build dependencies on the runner"
grep -q 'sudo ./scripts/main.sh' "$repo_root/.github/workflows/release.yml" \
    || fail "release workflow must run the build script directly on the runner"
grep -q 'mtools' "$repo_root/.github/workflows/release.yml" \
    || fail "release workflow must install mtools for boot partition validation"
grep -q 'Validate boot partition' "$repo_root/.github/workflows/release.yml" \
    || fail "release workflow must validate boot partition contents"
grep -q 'kernel8.img' "$repo_root/.github/workflows/release.yml" \
    || fail "release workflow must validate the boot kernel"
grep -q 'cmdline.txt' "$repo_root/.github/workflows/release.yml" \
    || fail "release workflow must validate cmdline.txt"
if grep -q 'docker build\|docker run\|rpi5-archlinux-builder' "$repo_root/.github/workflows/release.yml"; then
    fail "release workflow must not use a custom builder container"
fi
if grep -q 'tonistiigi/binfmt' "$repo_root/.github/workflows/release.yml"; then
    fail "release workflow must not register binfmt on a native arm64 runner"
fi
grep -q 'systemd_firstboot' "$repo_root/scripts/main.sh" \
    || fail "main script must use systemd-firstboot"
grep -q 'arch_root.img.xz' "$repo_root/.github/workflows/release.yml" \
    || fail "release workflow must publish compressed image"
