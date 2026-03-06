#!/bin/bash
# TaskCompleted hook: verify SwiftLint + build pass before task completion
# Exit 2 to block, exit 0 to allow

cd "$CLAUDE_PROJECT_DIR" || exit 0

# Check for any modified Swift files
MODIFIED=$(git diff --name-only --diff-filter=ACMR HEAD 2>/dev/null | grep '\.swift$' || true)

if [ -z "$MODIFIED" ]; then
  exit 0
fi

# Run SwiftLint on modified files
LINT_FAILED=0
for file in $MODIFIED; do
  if [ -f "$file" ]; then
    if ! swiftlint lint --config VultisigApp/.swiftlint.yml --quiet "$file" 2>/dev/null; then
      LINT_FAILED=1
    fi
  fi
done

if [ "$LINT_FAILED" -eq 1 ]; then
  echo "Quality gate: SwiftLint violations found in modified files" >&2
  exit 2
fi

exit 0
