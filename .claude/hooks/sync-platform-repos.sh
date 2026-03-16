#!/bin/bash
# Sync sibling repos (vultisig-android, vultisig-windows, vultiserver)
# Non-blocking: runs in background, reports updates
# Invoked at SessionStart

WORKSPACE_ROOT="$(dirname "$(dirname "$CLAUDE_PROJECT_DIR")")"
SIBLING_REPOS=(
  "vultisig-android"
  "vultisig-windows"
  "vultiserver"
)

sync_repo() {
  local repo_path="$WORKSPACE_ROOT/$1"
  local repo_name="$1"

  if [ ! -d "$repo_path/.git" ]; then
    return 0
  fi

  if git -C "$repo_path" status --porcelain 2>/dev/null | grep -q .; then
    echo "[sync] $repo_name has local changes, skipping" >&2
    return 0
  fi

  if git -C "$repo_path" pull --ff-only --quiet 2>/dev/null; then
    local latest=$(git -C "$repo_path" rev-parse --short HEAD 2>/dev/null)
    echo "[sync] $repo_name updated to $latest" >&2
  else
    echo "[sync] $repo_name already up-to-date" >&2
  fi
}

for repo in "${SIBLING_REPOS[@]}"; do
  sync_repo "$repo" &
done

wait
exit 0
