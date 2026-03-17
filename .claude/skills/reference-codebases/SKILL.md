---
name: reference-codebases
description: Use sibling repos (Android, Windows, backend) as reference when porting features to match behavior in Swift/SwiftUI style.
---

# Reference Codebases

Use this skill when the user says "port from Android/Windows", "reference codebases", or references a sibling repo's implementation.

## Strategy

1. **Find sibling repos**: Go up one level from the project root (`../`) to find repositories.
2. **Sync before reading**: Run `git -C ../<repo> pull --ff-only` to get latest changes.
3. **Explore**: List the parent folder, then use absolute paths to read/search files in the target repo.
4. **Port**: Match behavior 1:1, but write in Swift/SwiftUI style following our rules.

## Known Sibling Repositories

| Repo | Language | Key Paths |
|------|----------|-----------|
| `vultisig-android` | Kotlin | `app/src/main/java/com/vultisig/wallet/` — UI, data, viewmodels |
| `vultisig-windows` | TypeScript | `core/`, `clients/` — business logic, UI components |
| `vultiserver` | Go | `api/`, `service/`, `handler/` — backend endpoints |
| `commondata` | Protobuf | Shared message definitions |

## Kotlin/TypeScript to Swift

| Native | Swift |
|--------|-------|
| `T?` / nullable | Optional `T?` |
| Sealed class / discriminated union | `enum` with associated values |
| Data class / `type` | `struct` (Codable if for API) |
| Coroutines / async-await / Promise | `async`/`await` |
| `ByteArray` / `Uint8Array` | `Data` |
| StateFlow / Zustand | `@Published` property |
| Hilt injection | Initializer injection |
| Composable / React Component | SwiftUI `View` |
| Room / Zustand persist | SwiftData `@Model` |
| `stringResource()` / `t()` | `"key".localized` |

## Core Principle

**Same behavior, our style.** Match inputs, outputs, edge cases, and errors exactly. Use our MVVM pattern, Theme tokens, HTTPClient, and localization conventions.
