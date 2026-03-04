---
name: batch-fix-reviews
description: Fetch CodeRabbit review comments from batch PRs and auto-fix the issues. Pushes fixes and re-requests review.
---

# Batch Fix Reviews — Auto-fix CodeRabbit Feedback

## Overview

Companion to `/batch`. After CodeRabbit reviews the batch PRs, this skill fetches the review comments, spawns agents to fix the issues, and pushes the fixes. Designed to iterate until CodeRabbit approves.

## Usage

```
/batch-fix-reviews              # fix all open batch PRs with CodeRabbit comments
/batch-fix-reviews #123         # fix a specific PR
/batch-fix-reviews #123 #456    # fix specific PRs
```

## Workflow

### Step 1 — Find PRs to Fix

If no specific PRs are provided, find all open PRs with pending CodeRabbit reviews:

```bash
gh pr list --author "@me" --state open --json number,title,url,headRefName --limit 20
```

For each PR, check if CodeRabbit has requested changes:

```bash
gh api repos/{owner}/{repo}/pulls/{number}/reviews --jq '.[] | select(.user.login == "coderabbitai") | {state: .state, body: .body}'
```

Only process PRs where CodeRabbit's latest review state is `CHANGES_REQUESTED` or has unresolved comments.

### Step 2 — Extract CodeRabbit Feedback

For each PR to fix, gather all CodeRabbit comments:

#### a) Review-level summary
```bash
gh api repos/{owner}/{repo}/pulls/{number}/reviews \
  --jq '.[] | select(.user.login == "coderabbitai") | .body'
```

#### b) Inline code comments
```bash
gh api repos/{owner}/{repo}/pulls/{number}/comments \
  --jq '.[] | select(.user.login == "coderabbitai") | {path: .path, line: .line, original_line: .original_line, diff_hunk: .diff_hunk, body: .body}'
```

#### c) General PR comments (CodeRabbit sometimes posts summary comments)
```bash
gh api repos/{owner}/{repo}/issues/{number}/comments \
  --jq '.[] | select(.user.login == "coderabbitai") | .body'
```

### Step 3 — Triage Feedback

Categorize each CodeRabbit comment:

| Category | Action |
|---|---|
| **Code issue** (bug, logic error, missing check) | Fix in code |
| **Style issue** (naming, formatting, convention) | Fix in code |
| **CLAUDE.md violation** (hardcoded color, missing localization, etc.) | Fix in code — load relevant skill |
| **Suggestion** (nice-to-have, alternative approach) | Include only if low-effort and clearly better |
| **Question** (CodeRabbit asking for clarification) | Add a code comment or improve naming to clarify |
| **False positive** (CodeRabbit is wrong) | Skip — note in the commit message why it was skipped |

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

Ask the user to approve the fix plan. Use AskUserQuestion with options:
- "Approve all fixes — start execution"
- "I want to adjust"

### Step 5 — Execute Fixes

For each PR, spawn an Agent with:
- `subagent_type: "general-purpose"`
- `isolation: "worktree"`
- `run_in_background: true`

All agents MUST be spawned in a **single message** so they run in parallel.

#### Agent Prompt Template

```
You are fixing CodeRabbit review feedback on a PR for the Vultisig iOS app.

## PR
- PR #{number}: {title}
- Branch: `{branch-name}`

## Skills to Load
{same skills from the original batch task}

## CodeRabbit Issues to Fix

{for each issue to fix:}
### Issue {n}
- **File**: `{file-path}`
- **Line**: {line-number}
- **Comment**: {CodeRabbit's comment text}
- **Diff context**:
```
{diff_hunk from the comment}
```
- **Category**: {code issue | style issue | CLAUDE.md violation | suggestion | question}

## Issues to Skip (do NOT fix these)
{for each skipped issue:}
- `{file}:{line}` — {reason for skipping}

## Workflow

1. Load the skills listed above using the Skill tool
2. Checkout the PR branch: `git fetch origin {branch-name} && git checkout {branch-name} && git pull`
3. Read each file that needs fixing
4. Apply fixes for each CodeRabbit issue listed above
5. For CLAUDE.md violations, follow the relevant rule strictly
6. Run SwiftLint: `swiftlint lint --config VultisigApp/.swiftlint.yml VultisigApp/`
7. Fix any new SwiftLint warnings
8. Run build check: `xcodebuild build -scheme VultisigApp -destination 'platform=iOS Simulator,name=iPhone 16' -skipMacroValidation -skipPackagePluginValidation 2>&1 | tail -20`
9. Self-review: `git diff HEAD` — verify each fix addresses the CodeRabbit comment
10. Commit with a message like: "fix: address CodeRabbit review feedback\n\n- {list each fix}"
11. Push: `git push origin {branch-name}`
12. Re-request review from CodeRabbit by posting a comment:

gh pr comment {number} --body "Addressed CodeRabbit feedback. Fixes applied:
{list of fixes}

Skipped (with reasoning):
{list of skipped items, or 'None'}

@coderabbitai review"
```

### Step 6 — Report

After all agents complete, present results:

```
## Fix Reviews Complete

| PR | Fixes Applied | Fixes Skipped | Pushed | Re-review Requested |
|----|--------------|---------------|--------|---------------------|
| #{N} | {count} | {count} | yes/no | yes/no |
| ... | ... | ... | ... | ... |

### Next Steps
- CodeRabbit will re-review automatically
- Run `/batch-review` to check updated status
- Run `/batch-fix-reviews` again if CodeRabbit finds more issues
```

## Rules
- Never merge PRs — only fix and push
- Never force-push
- Always re-request CodeRabbit review after pushing fixes
- Skip false positives gracefully — don't fix things that aren't actually wrong
- Always run SwiftLint and build check after applying fixes
- Commit fixes as a new commit (don't amend) so the review history is preserved
- If the same issue keeps coming back after 2 fix attempts, flag it for manual review
