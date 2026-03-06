---
name: fix-pr-comments
description: Fetch CodeRabbit review comments from a single PR and auto-fix the issues. Defaults to current branch if no PR/branch is specified.
---

# Fix PR Comments — Single PR CodeRabbit Fix

## Overview

Fetches CodeRabbit review comments for a single PR, triages them, applies fixes, and pushes. Defaults to the current branch's PR if no argument is provided.

## Usage

```
/fix-pr-comments              # fix current branch's PR
/fix-pr-comments #123         # fix PR #123
/fix-pr-comments feat/my-feat # fix PR for branch feat/my-feat
```

## Workflow

### Step 1 — Identify the PR

If a PR number is provided, use it directly.

If a branch name is provided, find its PR:
```bash
gh pr list --head "{branch}" --state open --json number,title,url,headRefName --limit 1
```

If **no argument** is provided, detect from the current git branch:
```bash
BRANCH=$(git branch --show-current)
gh pr list --head "$BRANCH" --state open --json number,title,url,headRefName --limit 1
```

If no open PR is found, inform the user and stop.

### Step 2 — Extract CodeRabbit Feedback

#### a) Review-level summary
```bash
gh api repos/{owner}/{repo}/pulls/{number}/reviews \
  --jq '.[] | select(.user.login == "coderabbitai[bot]") | {state: .state, body: .body}'
```

#### b) Inline code comments
```bash
gh api repos/{owner}/{repo}/pulls/{number}/comments \
  --jq '.[] | select(.user.login == "coderabbitai[bot]") | {path: .path, line: .line, original_line: .original_line, diff_hunk: .diff_hunk, body: .body}'
```

#### c) General PR comments
```bash
gh api repos/{owner}/{repo}/issues/{number}/comments \
  --jq '.[] | select(.user.login == "coderabbitai[bot]") | .body'
```

If no CodeRabbit comments are found, inform the user and stop.

### Step 3 — Triage Feedback

Categorize each CodeRabbit comment:

| Category | Action |
|---|---|
| **Code issue** (bug, logic error, missing check) | Fix in code |
| **Style issue** (naming, formatting, convention) | Fix in code |
| **CLAUDE.md violation** (hardcoded color, missing localization, etc.) | Fix in code — load relevant skill |
| **Suggestion** (nice-to-have, alternative approach) | Include only if low-effort and clearly better |
| **Question** (CodeRabbit asking for clarification) | Add a code comment or improve naming to clarify |
| **False positive** (CodeRabbit is wrong) | Skip — note why it was skipped |

Present a summary to the user:

```
## CodeRabbit Feedback — PR #{N}: {title}

### Will Fix ({count})
{for each:}
- `{file}:{line}` — {description} [{category}]

### Will Skip ({count})
{for each:}
- `{file}:{line}` — {description} — Reason: {why skipping}
```

### Step 4 — Approval

Ask the user to approve the fix plan before proceeding. Use AskUserQuestion with options:
- "Approve all fixes — start execution"
- "I want to adjust"

### Step 5 — Execute Fixes

1. Make sure you're on the PR branch: `git checkout {branch} && git pull`
2. Read each file that needs fixing
3. For each fix, apply the change and create a **separate commit**:
   - Apply the fix for one CodeRabbit issue (or a group of closely related issues in the same file)
   - For CLAUDE.md violations, load the relevant skill and follow the rule strictly
   - Stage only the relevant files and commit with a descriptive message
4. After all fixes are committed, run SwiftLint: `swiftlint lint --config VultisigApp/.swiftlint.yml VultisigApp/`
5. Fix any new SwiftLint warnings (as an additional commit)
6. Self-review: `git diff origin/{branch}..HEAD` — verify each fix addresses the CodeRabbit comment

### Step 5b — Reply to Comments

For each CodeRabbit inline comment, reply with a brief explanation of what was done (or why it was skipped):

```bash
# Reply to inline PR review comments
gh api -X POST repos/{owner}/{repo}/pulls/{number}/comments/{comment_id}/replies \
  -f body="Fixed. {brief explanation of the change}"

# For skipped comments
gh api -X POST repos/{owner}/{repo}/pulls/{number}/comments/{comment_id}/replies \
  -f body="Skipped — {reason why it was skipped}"
```

Note: Outside-diff comments embedded in the review body don't have individual comment IDs. Address them in the summary comment instead.

### Step 5c — Push and Re-request Review

1. Push: `git push origin {branch}`
2. Post a summary comment to re-request review:

```bash
gh pr comment {number} --body "Addressed CodeRabbit feedback. Fixes applied:
{list of fixes}

Skipped (with reasoning):
{list of skipped items, or 'None'}

@coderabbitai review"
```

### Step 6 — Report

```
## Fix Complete — PR #{N}: {title}

- Fixes applied: {count}
- Fixes skipped: {count}
- Pushed: yes/no
- Re-review requested: yes/no

### Next Steps
- CodeRabbit will re-review automatically
- Run `/fix-pr-comments` again if CodeRabbit finds more issues
```

## Rules
- Never merge PRs — only fix and push
- Never force-push
- Always re-request CodeRabbit review after pushing fixes
- Skip false positives gracefully — don't fix things that aren't actually wrong
- Always run SwiftLint after applying fixes
- Create a **separate commit for each fix** (or group of closely related fixes in the same file) — don't bundle all fixes into one commit
- Always **reply to each inline CodeRabbit comment** with a brief explanation of the fix or skip reason
- If an issue seems wrong or risky, ask the user before fixing
