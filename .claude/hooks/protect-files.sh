#!/bin/bash
# Block direct edits to protected files (pbxproj, swiftlint config, secrets)

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

case "$FILE_PATH" in
  *.pbxproj)
    echo "Use /add-xcode-files skill instead of editing pbxproj directly" >&2
    exit 2
    ;;
  *.swiftlint.yml)
    echo "SwiftLint config is protected" >&2
    exit 2
    ;;
  *.env|*.env.*|*credentials*|*secret*)
    echo "Secrets file is protected" >&2
    exit 2
    ;;
esac

exit 0
