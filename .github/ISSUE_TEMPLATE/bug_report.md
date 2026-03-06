---
name: Bug Report
about: Report a bug for agent or human resolution
title: "[Fix] "
labels: bug
assignees: ''
---

<!-- Agent-ready issue template. Fill as much as you can — the more detail, the faster the fix. -->

---
type: "bugfix"
priority: ""              <!-- critical | high | medium | low -->
size: ""                  <!-- tiny (<1 file) | small (1-3 files) | medium (3-8 files) -->
platform: [ios]
files:
  read: []                <!-- Files the fixer should read for context -->
  write: []               <!-- Files that need to be modified -->
verify: ["xcodebuild -scheme Vultisig build"]
---

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
- [ ] `xcodebuild -scheme Vultisig build` succeeds
- [ ] <!-- Specific behavior check 1 -->
- [ ] <!-- Specific behavior check 2 -->
