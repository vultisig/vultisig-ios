#!/usr/bin/env bash
# Regenerate VultisigApp.xcodeproj from project.yml using XcodeGen.
# Run this after cloning, after pulling changes to project.yml, or whenever
# you add/remove source files.
#
# Usage:
#   ./scripts/bootstrap.sh              # regenerate the project
#   ./scripts/bootstrap.sh --install    # install xcodegen if missing, then regenerate
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
VULTISIG_APP_DIR="$( cd "$SCRIPT_DIR/.." &> /dev/null && pwd )"

REQUIRED_MAJOR=2
REQUIRED_MINOR=41

install_xcodegen() {
  echo "Installing xcodegen via Homebrew..."
  if ! command -v brew >/dev/null 2>&1; then
    echo "error: Homebrew is not installed. Install it from https://brew.sh or install xcodegen manually."
    exit 1
  fi
  brew install xcodegen
}

ensure_xcodegen() {
  if ! command -v xcodegen >/dev/null 2>&1; then
    if [[ "${1:-}" == "--install" ]]; then
      install_xcodegen
    else
      cat <<EOF
error: xcodegen is not installed.

Install it with one of:
  brew install xcodegen
  mint install yonaskolb/XcodeGen

Or rerun this script with --install to install it automatically via Homebrew.
EOF
      exit 1
    fi
  fi

  # Version check (best effort — xcodegen prints e.g. "Version: 2.41.0")
  local version
  version=$(xcodegen --version 2>/dev/null | sed -E 's/^Version: //' | head -n 1 || true)
  if [[ -z "$version" ]]; then
    echo "warning: could not determine xcodegen version; proceeding."
    return
  fi

  local major minor
  IFS='.' read -r major minor _ <<< "$version"
  if [[ "$major" -lt "$REQUIRED_MAJOR" ]] || { [[ "$major" -eq "$REQUIRED_MAJOR" ]] && [[ "$minor" -lt "$REQUIRED_MINOR" ]]; }; then
    echo "warning: xcodegen $version < required ${REQUIRED_MAJOR}.${REQUIRED_MINOR}; upgrade is recommended."
  fi
}

main() {
  ensure_xcodegen "${1:-}"
  cd "$VULTISIG_APP_DIR"
  echo "Generating VultisigApp.xcodeproj from project.yml..."
  xcodegen generate --spec project.yml
  echo "Done. Open VultisigApp.xcodeproj in Xcode."
}

main "$@"
