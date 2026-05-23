#!/bin/bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

[[ -f "$repo_root/Dockerfile" ]] || fail "missing Dockerfile"
[[ -f "$repo_root/.github/workflows/ci.yml" ]] || fail "missing ci workflow"
[[ -f "$repo_root/.github/workflows/release.yml" ]] || fail "missing release workflow"

grep -q 'docker build -t rpi5-archlinux-builder \.' "$repo_root/.github/workflows/ci.yml" \
    || fail "ci workflow must build the builder image"
grep -q 'tags:' "$repo_root/.github/workflows/release.yml" \
    || fail "release workflow must trigger on tags"
grep -q '"v\*"' "$repo_root/.github/workflows/release.yml" \
    || fail "release workflow must target v* tags"
grep -q 'gh release create' "$repo_root/.github/workflows/release.yml" \
    || fail "release workflow must publish a GitHub release"
