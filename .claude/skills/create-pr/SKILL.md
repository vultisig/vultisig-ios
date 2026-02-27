---
name: create-pr
description: Create a GitHub PR with optional issue linking. Use after committing and pushing changes.
disable-model-invocation: true
---

# Create Pull Request

## Usage
`/create-pr` or `/create-pr #42` (with GitHub issue)

## Workflow

### 1. Gather Context
```bash
git log --oneline main..HEAD
git diff --stat main..HEAD
git branch --show-current
```

### 2. Extract Issue Reference (if provided)
- From argument: `#42` or issue URL
- From branch name: extract issue number pattern `^\d+-`
- If no issue found, create PR without issue link

### 3. Run Checks
```bash
swiftlint lint --config VultisigApp/.swiftlint.yml VultisigApp/
```

### 4. Push Current Branch
```bash
git push -u origin $(git branch --show-current)
```

### 5. Create PR
```bash
gh pr create --title "short description" --body "$(cat <<'EOF'
## Summary
- Brief description of changes

## Issue
Closes #42

## Test Plan
- [ ] Manual testing steps
- [ ] SwiftLint passes
- [ ] xcodebuild build succeeds

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

### 6. Return PR URL
Print the PR URL so the user can review it.

## Rules
- Keep title under 70 characters
- Always include Summary section
- Include issue link in body if available
- Include test plan
- Push before creating PR
- Never force-push to main
