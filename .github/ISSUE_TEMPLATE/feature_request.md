---
name: Feature Request
about: Request a new feature for agent or human implementation
title: "[Add] "
labels: enhancement
assignees: ''
---

<!-- Agent-ready issue template. Fill as much as you can — the more detail, the faster the implementation. -->

---
type: "feature"
priority: ""              <!-- critical | high | medium | low -->
size: ""                  <!-- tiny (<1 file) | small (1-3 files) | medium (3-8 files) -->
platform: [ios]
files:
  read: []                <!-- Files for context -->
  write: []               <!-- Files to create or modify -->
verify: ["xcodebuild -scheme Vultisig build"]
---

# [Add] <what to build> [<screen/area>]

## Problem
<!-- 2-3 sentences. What's missing or suboptimal? -->


## Solution
<!-- 1 paragraph. WHAT to do and WHY this approach. -->


## Scope

### Must Do
- [ ] <!-- Specific deliverable 1 -->
- [ ] <!-- Specific deliverable 2 -->
- [ ] <!-- Specific deliverable 3 -->

### Must NOT Do
- Don't change existing behavior
- Don't add extra dependencies without approval

### Out of Scope
- <!-- Related but separate work — future issue -->

## Acceptance Criteria
- [ ] `xcodebuild -scheme Vultisig build` succeeds
- [ ] <!-- Specific behavior check 1 -->
- [ ] <!-- Specific behavior check 2 -->
