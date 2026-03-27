---
name: approve-pr
description: Approve a GitHub PR and add it to the merge queue.
disable-model-invocation: true
---

# Approve PR + Add to Merge Queue

## Usage

```
/approve-pr              # approve current branch's PR
/approve-pr 123          # approve PR #123
/approve-pr feat/my-feat # approve PR for branch feat/my-feat
```

## Workflow

### Step 1 — Identify the PR

If a PR number is provided, use it directly.

If a branch name is provided:
```bash
gh pr list --head "{branch}" --state open --json number,title,url,headRefName --limit 1
```

If no argument is provided, detect from the current branch:
```bash
BRANCH=$(git branch --show-current)
gh pr list --head "$BRANCH" --state open --json number,title,url,headRefName --limit 1
```

If no open PR is found, inform the user and stop.

### Step 2 — Approve the PR

```bash
gh pr review {number} --approve --body "LGTM"
```

If this fails (e.g. you are the PR author and cannot self-approve), inform the user and stop — do not proceed to merge queue.

### Step 3 — Add to Merge Queue

First, fetch the PR's GraphQL node ID:
```bash
gh api repos/{owner}/{repo}/pulls/{number} --jq '.node_id'
```

Then add to the merge queue via GraphQL:
```bash
gh api graphql -f query='
  mutation($prId: ID!) {
    addPullRequestToMergeQueue(input: { pullRequestId: $prId }) {
      mergeQueue {
        id
        nextEntryEstimatedTimeToMerge
      }
    }
  }
' -f prId="{node_id}"
```

If the merge queue mutation fails (e.g. merge queue not enabled on the repo, or branch protection not satisfied), fall back to enabling auto-merge instead:
```bash
gh api graphql -f query='
  mutation($prId: ID!) {
    enablePullRequestAutoMerge(input: { pullRequestId: $prId, mergeMethod: SQUASH }) {
      pullRequest { autoMergeRequest { mergeMethod } }
    }
  }
' -f prId="{node_id}"
```

Report which path was taken and whether it succeeded.

### Step 4 — Report

```
## Approved + Queued — PR #{N}: {title}

- Approved: ✅
- Merge queue: ✅ added  (or ⚠️ fell back to auto-merge, or ❌ failed — reason)
- URL: {pr_url}
```

## Rules

- Never use `gh pr merge` — use the GraphQL API for merge queue / auto-merge
- Do not approve if already approved (check review state first with `gh pr reviews`)
- Do not approve your own PRs — stop and inform the user
- Always report the final state clearly
