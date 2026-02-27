#!/bin/bash
# Block dangerous git commands (force push, hard reset, clean, branch delete)

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if echo "$CMD" | grep -qE 'git (push.*(--force|--force-with-lease|-f|-F)|reset --hard|clean -[a-z]*f|branch.*(--delete|-D))'; then
  echo "Dangerous git command blocked. Ask the user first." >&2
  exit 2
fi

exit 0
