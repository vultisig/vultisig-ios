#!/bin/bash
# PostToolUseFailure hook: notify on build/lint/script failures with context

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
ERROR=$(echo "$INPUT" | jq -r '.error // empty' | head -5)

if [ "$TOOL" = "Bash" ]; then
  CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
  if echo "$CMD" | grep -qE '(xcodebuild|swiftlint|python3|swift build|swift test|swift package)'; then
    echo "Build/lint/script failure detected. Command: $CMD" >&2
    echo "Error: $ERROR" >&2
  fi
fi

exit 0
