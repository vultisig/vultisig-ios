#!/bin/bash
# Auto-run SwiftLint on edited Swift files

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [[ "$FILE_PATH" == *.swift ]]; then
  cd "$CLAUDE_PROJECT_DIR" || exit 0
  if ! swiftlint lint --config VultisigApp/.swiftlint.yml --quiet "$FILE_PATH" >&2; then
    echo "SwiftLint violations detected in $FILE_PATH" >&2
    exit 2
  fi
fi

exit 0
