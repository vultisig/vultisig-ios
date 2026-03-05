#!/bin/bash
# WorktreeCreate hook: ensure worktrees get proper setup
# Runs when a new worktree is created for an agent

WORKTREE_PATH=$(echo "$(cat)" | jq -r '.worktree_path // empty')

if [ -n "$WORKTREE_PATH" ] && [ -d "$WORKTREE_PATH" ]; then
  cd "$WORKTREE_PATH" || exit 0
  # Ensure the worktree has latest main
  git fetch origin main 2>/dev/null || true
fi

exit 0
