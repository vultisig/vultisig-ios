---
name: create-branch
description: Create a new git branch from conversation context. Use when starting work on an issue or feature.
---

# Create Branch

## Branch Naming

1. **GitHub issue in context** (URL or #123):
   - Format: `{type}/{issue-number}-{slugified-issue-title}`
   - Determine `{type}` from the issue labels or title:
     - `fix` — bugs, errors, corrections (labels: `bug`, `fix`)
     - `feat` — new features, enhancements (labels: `enhancement`, `feature`)
     - `refactor` — code improvements without behavior change
     - `chore` — maintenance, CI, docs, dependencies
     - Default to `fix` if unclear
   - Example: Issue #42 "Fix TRC20 token transfers" (label: `bug`) → `fix/42-fix-trc20-token-transfers`
   - Example: Issue #55 "Add dark mode support" (label: `enhancement`) → `feat/55-add-dark-mode-support`

2. **No GitHub issue**:
   - Format: `{type}/{kebab-case-description}`
   - Use the same type conventions as above
   - Example: Adding dark mode → `feat/add-dark-mode`
   - Example: Fix balance rounding → `fix/fix-balance-rounding`

## Workflow
```bash
git checkout main
git pull
git checkout -b <branch-name>
```

## Rules
- Lowercase with hyphens
- Max 50 characters for description
- Local only (no push)
