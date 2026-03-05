---
name: batch-review
description: Morning review of batch PRs. Shows status, CodeRabbit feedback, and lint/build results for all recent batch PRs.
---

# Batch Review — Morning PR Dashboard

## Overview

Companion to `/batch-tasks`. Gives a quick overview of all PRs from the last batch run so you can review efficiently without opening each one individually.

## Usage

```
/batch-review
```

Or with a filter:
```
/batch-review open        # only open PRs (default)
/batch-review all         # include closed/merged
```

## Workflow

### Step 1 — Find Batch PRs

List recent PRs authored by the bot:

```bash
gh pr list --author "@me" --state open --json number,title,url,headRefName,createdAt,isDraft,reviewDecision --limit 20
```

Filter to PRs that contain `Co-Authored-By: Claude` in the body:

```bash
gh pr view {number} --json body
```

### Step 2 — Gather Status for Each PR

For each batch PR, collect:

#### a) CI / Check Status
```bash
gh pr checks {number}
```

#### b) CodeRabbit Review
Fetch review comments from CodeRabbit:

```bash
gh api repos/{owner}/{repo}/pulls/{number}/reviews --jq '.[] | select(.user.login == "coderabbitai") | {state: .state, body: .body}'
```

Fetch inline review comments from CodeRabbit:

```bash
gh api repos/{owner}/{repo}/pulls/{number}/comments --jq '.[] | select(.user.login == "coderabbitai") | {path: .path, line: .line, body: .body}'
```

#### c) PR Summary
Extract the Summary section from the PR body.

### Step 3 — Present Dashboard

Display a summary table:

```
## Batch Review Dashboard

| # | PR | Title | Checks | CodeRabbit | Action Needed |
|---|-----|-------|--------|------------|---------------|
| 1 | #N [link] | {title} | pass/fail | approved/changes_requested/pending | {suggestion} |
| 2 | ... | ... | ... | ... | ... |
```

### Step 4 — Detailed View per PR

After the table, show details for each PR that needs attention:

```
### PR #{N}: {title}
**Status**: {checks status}
**CodeRabbit**: {review state}

#### CodeRabbit Summary
{extracted summary from CodeRabbit's review body}

#### Issues to Fix ({count})
{for each inline comment:}
- `{file}:{line}` — {issue description}

#### Suggested Action
- {e.g. "Run `/batch-fix-reviews #N` to auto-fix CodeRabbit issues"}
- {e.g. "Ready to merge — no issues found"}
- {e.g. "Build failing — check CI logs"}
```

### Step 5 — Offer Next Actions

Use AskUserQuestion with relevant options based on the dashboard:
- "Fix all CodeRabbit issues (`/batch-fix-reviews`)"
- "Retry failed tasks (`/batch-retry`)"
- "Looks good — I'll review and merge manually"

## Rules
- Never merge PRs — only present information
- Show CodeRabbit feedback prominently — it's the primary review mechanism
- Group PRs by status: needs attention first, then passing
- If no batch PRs are found, tell the user and suggest running `/batch-tasks`
