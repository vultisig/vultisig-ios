---
name: check-platforms
description: Search and analyze feature implementations in sibling Android, Windows, and backend repositories. Use when porting features or validating cross-platform parity.
---

# Check Platforms (Cross-Platform Reference)

## Overview

Searches sibling repositories for existing feature implementations:
- **vultisig-android** (Kotlin/Jetpack Compose)
- **vultisig-windows** (TypeScript/React)
- **vultiserver** (Go backend)

Returns a structured mapping of patterns to Swift/SwiftUI equivalents.

## Invocation

```
/check-platforms [feature-name] [keywords...]
```

Examples:
```
/check-platforms "token swap" swap dex TON
/check-platforms "keysign flow" keysign MPC vault
/check-platforms "wallet balance" balance fetch query
```

## Workflow

### Phase 1: Repository Sync

```bash
WORKSPACE_ROOT="$(cd .. && pwd)"
git -C "$WORKSPACE_ROOT/vultisig-android" pull --ff-only 2>/dev/null || echo "Android: skipped"
git -C "$WORKSPACE_ROOT/vultisig-windows" pull --ff-only 2>/dev/null || echo "Windows: skipped"
git -C "$WORKSPACE_ROOT/vultiserver" pull --ff-only 2>/dev/null || echo "Backend: skipped"
```

Verify repos exist:
```bash
test -d ../vultisig-android && echo "Android found" || echo "Android not found"
test -d ../vultisig-windows && echo "Windows found" || echo "Windows not found"
test -d ../vultiserver && echo "Backend found" || echo "Backend not found"
```

### Phase 2: Code Search

Search actual code for keywords:

```bash
# Android production code
rg -nEi "KEYWORD1|KEYWORD2" ../vultisig-android/app/src/main/java/ || echo "No Android matches"

# Windows production code
rg -nEi "KEYWORD1|KEYWORD2" ../vultisig-windows/core/ ../vultisig-windows/clients/ || echo "No Windows matches"

# Backend Go code
rg -nEi "KEYWORD1|KEYWORD2" ../vultiserver/ --type go || echo "No Backend matches"
```

### Phase 3: Evidence Review

For each match found, read 1-3 relevant files to confirm:
- Feature is implemented (not just comments/tests)
- Code is on main branch
- Implementation is in production paths

### Phase 4: Map Implementation Patterns

**Android (Kotlin) → iOS (Swift)**

| Kotlin | Swift |
|--------|-------|
| ViewModel (Hilt) | ViewModel (ObservableObject) |
| Composable | SwiftUI View |
| Repository | Service |
| StateFlow | @Published |
| Sealed class | Enum with associated values |
| data class | struct |
| Coroutines | async/await |
| Room | SwiftData |

**Windows (TypeScript) → iOS (Swift)**

| TypeScript | Swift |
|------------|-------|
| React Component | SwiftUI View |
| Zustand store | ViewModel (@Published) |
| useQuery/useMutation | async/await in ViewModel |
| type definition | struct |
| Discriminated union | Enum |

**Backend (Go) → iOS (Swift)**

| Go | Swift |
|----|-------|
| Handler | TargetType endpoint |
| Service | Service class |
| struct | Codable struct |

### Phase 5: Output Format

```markdown
# Platform Implementation Analysis: [Feature Name]

## Android Status
**Implemented: [YES/NO/PARTIAL]**
- Confidence: [high/medium/low]
- Files: [list with line numbers]
- Key types: [important classes/interfaces]

## Windows Status
**Implemented: [YES/NO/PARTIAL]**
- Confidence: [high/medium/low]
- Files: [list with line numbers]
- Key types: [important types/components]

## Backend Status
**Implemented: [YES/NO/PARTIAL]**
- Confidence: [high/medium/low]
- Endpoints: [list of routes]
- Key types: [important structs]

## iOS Implementation Notes
- Suggested ViewModel: [name]
- Suggested Service: [name]
- Suggested View: [name]
- Key patterns to follow: [references to existing iOS code]
```

## Confidence Rules

- **High**: Code exists in production path, is wired and complete
- **Medium**: Code exists but wiring unclear or partial
- **Low**: Only comments/mentions, tests only, or wrong context

## Notes

- Only reference `main` branch code — not feature branches
- Prefer production paths over test/docs
- Map patterns explicitly to Swift/SwiftUI equivalents
