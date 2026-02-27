---
name: create-branch
description: Create a new git branch from conversation context. Use when starting work on an issue or feature.
---

# Create Branch

## Branch Naming

1. **GitHub issue in context** (URL or #123):
   - Format: `{issue-number}-{slugified-issue-title}`
   - Example: Issue #42 "Fix TRC20 token transfers" → `42-fix-trc20-token-transfers`

2. **No GitHub issue**:
   - Descriptive kebab-case, no prefixes (`feat/`, `fix/`, etc.)
   - Example: Adding dark mode → `add-dark-mode`

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
