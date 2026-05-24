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
grep -q 'workflow_dispatch:' "$repo_root/.github/workflows/release.yml" \
    || fail "release workflow must support manual runs"
grep -q 'gh release create' "$repo_root/.github/workflows/release.yml" \
    || fail "release workflow must publish a GitHub release"
grep -q 'runs-on: ubuntu-24.04-arm' "$repo_root/.github/workflows/release.yml" \
    || fail "release workflow must use the native arm64 runner"
grep -q 'sudo apt-get install -y' "$repo_root/.github/workflows/release.yml" \
    || fail "release workflow must install build dependencies on the runner"
grep -q 'Package builder' "$repo_root/.github/workflows/ci.yml" \
    || fail "ci workflow must package the builder"
grep -q 'Package builder' "$repo_root/.github/workflows/release.yml" \
    || fail "release workflow must package the builder before build"
grep -q './scripts/package.sh' "$repo_root/.github/workflows/ci.yml" \
    || fail "ci workflow must run scripts/package.sh"
grep -q './scripts/package.sh' "$repo_root/.github/workflows/release.yml" \
    || fail "release workflow must run scripts/package.sh"
grep -q 'cp build.conf.example build.conf' "$repo_root/.github/workflows/ci.yml" \
    || fail "ci workflow must create build.conf from example before package"
grep -q 'cp build.conf.example build.conf' "$repo_root/.github/workflows/release.yml" \
    || fail "release workflow must create build.conf from example before package"
grep -q 'Validate packaged builder' "$repo_root/.github/workflows/ci.yml" \
    || fail "ci workflow must validate the packaged builder"
grep -q './dist/bin/rpi5-archlinux-image build' "$repo_root/.github/workflows/release.yml" \
    || fail "release workflow must run the packaged builder directly on the runner"
if grep -q 'sudo ./dist/bin/rpi5-archlinux-image build' "$repo_root/.github/workflows/release.yml"; then
    fail "release workflow must rely on builder auto-sudo instead of explicit sudo"
fi
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
grep -q 'systemd_firstboot' "$repo_root/src/lib/modules/services.sh" \
    || fail "main script must use systemd-firstboot"
grep -Fq "archlinux-rpi5-aarch64-\${GITHUB_REF_NAME}.img.xz" "$repo_root/.github/workflows/release.yml" \
    || fail "release workflow must publish tagged compressed image"
grep -q 'dist/images/archlinux-rpi5-aarch64.img' "$repo_root/.github/workflows/release.yml" \
    || fail "release workflow must read the image from dist/images"
