#!/bin/bash
# Auto-sort Localizable.strings after edits

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [[ "$FILE_PATH" == *Localizable.strings ]]; then
  cd "$CLAUDE_PROJECT_DIR" || exit 0
  python3 VultisigApp/scripts/sort_localizable.py >&2
fi

exit 0
