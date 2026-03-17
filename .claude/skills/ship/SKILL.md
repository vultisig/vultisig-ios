---
name: ship
description: Commit changes and create a GitHub PR in one step. Use after completing a task.
disable-model-invocation: true
---

# Ship Changes (Commit + PR)

## Usage
`/ship` or `/ship #42` (with GitHub issue)

## Workflow

### 1. Review Changes
```bash
git status
git diff --staged
git diff
git log --oneline main..HEAD
git branch --show-current
```

### 2. Stage Files
Stage specific files (never `git add .` or `git add -A`):
```bash
git add <specific-files>
```

### 3. Create Commit
```bash
git commit -m "$(cat <<'EOF'
feat: add TRC20 token transfer support

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

### 4. Run Checks
```bash
swiftlint lint --config VultisigApp/.swiftlint.yml VultisigApp/
```

### 5. Push Current Branch
```bash
git push -u origin $(git branch --show-current)
```

### 6. Create PR
Extract issue reference if provided (`#42` or issue URL), or from branch name pattern.
```bash
gh pr create --title "short description" --body "$(cat <<'EOF'
## Summary
- Brief description of changes

## Issue
Closes #42

## Test Plan
- [ ] Manual testing steps
- [ ] SwiftLint passes
- [ ] Build succeeds (xcodebuild)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

### 7. Return PR URL
Print the PR URL so the user can review it.

## Rules
- Use conventional commit format: `type: description`
- Keep commit subject under 72 characters
- Add body for complex changes
- Always include `Co-Authored-By` trailer in both commit and PR
- Never commit `.env`, credentials, or secrets
- Never use `--no-verify` unless explicitly asked
- Never force-push to main
- Include issue link in PR body if available
- Include test plan in PR body
