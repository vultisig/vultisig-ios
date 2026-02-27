#!/bin/bash
# Auto-run SwiftLint on edited Swift files

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [[ "$FILE_PATH" == *.swift ]]; then
  cd "$CLAUDE_PROJECT_DIR" || exit 0
  swiftlint lint --config VultisigApp/.swiftlint.yml --quiet "$FILE_PATH" >&2
fi

exit 0
