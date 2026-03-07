---
name: batch-retry
description: Retry failed batch tasks. Cleans up failed branches/PRs and re-runs specified tasks.
---

# Batch Retry — Re-run Failed Tasks

## Overview

Companion to `/batch-tasks`. Retries specific tasks that failed during a batch run. Cleans up the failed attempt (branch + PR if created) and re-executes with the same PRD.

## Usage

```
/batch-retry 2, 4          # retry tasks 2 and 4 by their batch index
/batch-retry #42            # retry by GitHub issue number
/batch-retry branch-name    # retry by branch name
```

## Workflow

### Step 1 — Identify Failed Tasks

Parse the user's input to determine which tasks to retry. Find the associated PRs/branches:

```bash
# Find PR by branch name
gh pr list --head "{branch-name}" --json number,title,url,headRefName,state

# Or find by issue reference
gh pr list --search "Closes #{issue-number}" --json number,title,url,headRefName,state
```

### Step 2 — Cleanup Failed Attempt

Confirm cleanup with the user before proceeding with any destructive operations.

For each task to retry:

#### a) Close the failed PR (if it exists)
```bash
gh pr close {number} --comment "Closing for retry via /batch-retry"
```

#### b) Delete the remote branch
```bash
git push origin --delete {branch-name}
```

#### c) Delete the local branch (if exists)
```bash
git branch -D {branch-name} 2>/dev/null || true
```

### Step 3 — Re-execute

For each task, follow the same execution flow as `/batch-tasks` Phase 3:

1. Spawn an Agent with:
   - `subagent_type: "general-purpose"`
   - `isolation: "worktree"`
   - `run_in_background: true`

2. Use the same agent prompt template from `/batch-tasks`, but add context about the previous failure:

```
## Previous Attempt
This task was previously attempted and failed. Here is context from the failed attempt:
- **Error**: {error summary from the failed run or PR body}
- **What was tried**: {brief description of what the previous attempt did}

Avoid the same mistakes. Pay extra attention to:
{specific guidance based on the failure reason}
```

### Step 4 — Report

Present results in the same format as `/batch-tasks` Phase 4:

```
## Retry Complete

| # | Task | Branch | PR | Build | Lint | Status |
|---|------|--------|----|-------|------|--------|
| 2 | {title} | `{branch}` | {PR URL} | pass/fail | pass/fail | pass/fail |
| 4 | ... | ... | ... | ... | ... | ... |
```

## Rules
- Always confirm cleanup before deleting branches/PRs
- Never force-push
- Include failure context in the retry prompt so the agent doesn't repeat the same mistake
- If a task fails twice, suggest that it may need manual intervention
- Spawn all retry agents in parallel (same as /batch-tasks)
