---
name: resolve-pr-comments
description: Address CodeRabbit or other AI reviewer comments on a PR to make it merge-ready.
disable-model-invocation: true
---

# Resolve PR Review Comments

## Usage
Provide the PR link or number.

## Workflow

### 1. Fetch Review Comments
Use GitHub MCP `pull_request_read` with method `get_review_comments`. Focus on `IsResolved: false`.

### 2. Evaluate Critically
AI reviewers can be wrong. Before implementing:
- **Verify the claim** — does the code actually have the issue?
- **Question severity** — "critical" labels are often overstated
- **Check if code works** — suggestion may be based on misunderstanding
- **Ask the user** for questionable or significant changes

### 3. Address Valid Comments
Implement fixes. Skip invalid suggestions.

### 4. Run Checks
```bash
swiftlint lint --config VultisigApp/.swiftlint.yml VultisigApp/
```

### 5. Push and Resolve
```bash
git add -A && git commit -m "address review comments" && git push
```

Then use `gh api` to resolve PR review threads.

## Goal
- All threads resolved, all checks pass, PR merge-ready
