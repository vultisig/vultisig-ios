#!/bin/bash
# Standalone macOS regression checks; the main unit-test target is iOS-only.
set -euo pipefail
repo_root="$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/vultisig-hidden-tabs.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -parse-as-library \
    "$repo_root/VultisigApp/VultisigApp/Core/Platform/macOS/Native/MacHiddenTabBar.swift" \
    "$repo_root/scripts/tests/MacHiddenTabBarTests.swift" \
    -o "$test_dir/tests"
"$test_dir/tests"
