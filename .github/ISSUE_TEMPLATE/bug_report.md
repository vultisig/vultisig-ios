---
name: Bug Report
about: Report a bug for agent or human resolution
title: "[Fix] "
labels: bug
assignees: ''
---

<!-- Fill in the AGENT block: priority = critical|high|medium|low, size = tiny|small|medium -->
<!-- AGENT
type: "bugfix"
priority: ""
size: ""
platform: [ios, macos]
files:
  read: []
  write: []
verify: ["xcodebuild -scheme VultisigApp -destination 'platform=iOS Simulator,name=iPhone 16'"]
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
- [ ] `xcodebuild -scheme VultisigApp` succeeds
- [ ] <!-- Specific behavior check 1 -->
- [ ] <!-- Specific behavior check 2 -->
