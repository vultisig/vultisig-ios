---
name: create-issue
description: Create a GitHub issue for vultisig-ios using bug/feature templates.
---

# Create Issue

## Usage
`/create-issue` — infer everything from conversation context.

## Templates

### Bug Report — label: `bug`, title prefix: `[Fix]`

```markdown
<!-- AGENT
type: "bugfix"
priority: "critical|high|medium|low"
size: "tiny|small|medium"
platform: [iOS, macOS]
files:
  read: []
  write: []
verify: ["swiftlint lint"]
-->

# [Fix] <what's broken> [<screen/area>]

## Problem
<!-- 2-3 sentences. What's broken? Who's affected? -->

## Expected Behavior
<!-- What should happen instead? -->

## Steps to Reproduce
1.
2.
3.

## Solution
<!-- 1 paragraph. WHAT to do and WHY this approach. Leave blank if unsure. -->

## Scope

### Must Do
- [ ] <!-- Specific fix 1 -->
- [ ] <!-- Specific fix 2 -->

### Must NOT Do
- Don't change unrelated code
- Don't refactor surrounding logic

## Acceptance Criteria
- [ ] SwiftLint passes
- [ ] Build succeeds
- [ ] <!-- Specific behavior check 1 -->
- [ ] <!-- Specific behavior check 2 -->
```

### Feature Request — label: `enhancement`, title prefix: `[Add]`

```markdown
<!-- AGENT
type: "feature"
priority: "critical|high|medium|low"
size: "tiny|small|medium"
platform: [iOS, macOS]
files:
  read: []
  write: []
verify: ["swiftlint lint"]
-->

# [Add] <what to build> [<screen/area>]

## Problem
<!-- 2-3 sentences. What's missing or suboptimal? -->

## Solution
<!-- 1 paragraph. WHAT to do and WHY this approach. -->

## Scope

### Must Do
- [ ] <!-- Specific deliverable 1 -->
- [ ] <!-- Specific deliverable 2 -->

### Must NOT Do
- Don't change existing behavior
- Don't add extra dependencies without approval

### Out of Scope
- <!-- Related but separate work — future issue -->

## Acceptance Criteria
- [ ] SwiftLint passes
- [ ] Build succeeds
- [ ] <!-- Specific behavior check 1 -->
- [ ] <!-- Specific behavior check 2 -->
```

## Size Guide

| Size | Files | Lines | Example |
|------|-------|-------|---------|
| `tiny` | 1 | <50 | Fix typo, update constant |
| `small` | 1-3 | 50-200 | Fix a bug, add a function |
| `medium` | 3-8 | 200-500 | New feature with tests |
| `large` | 8+ | 500+ | **SPLIT THIS** |

## Key Repo Rules
- Never edit `project.pbxproj` directly — use `/add-xcode-files`
- Never modify `Blockchain/Tss/` without explicit review
- Use `"key".localized` for all user-facing strings
- Update ALL 7 locale files for string changes

## Workflow

```bash
gh issue create \
  --repo vultisig/vultisig-ios \
  --title "[Fix|Add] Short description [Area]" \
  --label "bug|enhancement" \
  --body "$(cat <<'EOF'
<full body from template above>
EOF
)"
```

Print the issue URL when done.
