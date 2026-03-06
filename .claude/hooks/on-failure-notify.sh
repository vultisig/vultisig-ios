#!/bin/bash
# PostToolUseFailure hook: notify on build/lint failures with context

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
ERROR=$(echo "$INPUT" | jq -r '.error // empty' | head -5)

if [ "$TOOL" = "Bash" ]; then
  CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
  if echo "$CMD" | grep -qE '(xcodebuild|swiftlint)'; then
    echo "Build/lint failure detected. Command: $CMD" >&2
    echo "Error: $ERROR" >&2
  fi
fi

exit 0
