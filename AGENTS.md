# vultisig-ios — Agent Reference

## Overview

iOS/macOS wallet app with SwiftUI, SwiftData, and DKLS23 TSS implementation. Swift, MVVM, async/await, 40+ blockchain support.

## Quick Start

```bash
git clone https://github.com/vultisig/vultisig-ios.git
cd vultisig-ios
open VultisigApp/VultisigApp.xcodeproj
# Build: Cmd+B | Run: Cmd+R
# CLI: xcodebuild -project VultisigApp/VultisigApp.xcodeproj -scheme VultisigApp -sdk iphonesimulator build
# Lint: swiftlint lint --config VultisigApp/.swiftlint.yml VultisigApp/
```

## Before You Change Code

1. Run `swiftlint lint --config VultisigApp/.swiftlint.yml VultisigApp/` to establish baseline
2. If touching `Services/Tss/`: extra caution — changes affect signing across all platforms
3. If touching `Model/`: SwiftData schema changes affect migrations
4. If touching `project.pbxproj`: use `/add-xcode-files` skill, never edit directly
5. If adding/removing strings: update ALL 7 locale files (use `/localize` skill)
6. If adding new .swift files: use `/add-xcode-files` to update project.pbxproj
7. If deleting a screen: remove route, ViewModel, strings — full cleanup

## Patterns

- MVVM with Service injection
- SwiftUI + SwiftData for UI and persistence (`@Model` always on MainActor)
- async/await for all concurrency (no completion handlers)
- `"key".localized` for all user-facing strings
- `Theme.colors.*` and `Theme.fonts.*` for all styling (never hardcode)
- `PrimaryButton` for all buttons (never custom button styles)
- `Screen` component for full-screen views, suffix with `Screen`
- `TargetType` protocol + `HTTPClient` for networking
- `.foregroundStyle()` not `.foregroundColor()`
- `Logger` (OSLog) for logging, never `print()`
- `crossPlatformToolbar`, `crossPlatformSheet`, `#if os(macOS)` for cross-platform

## Security Notes

- Never log key material or vault shares
- TSS bindings — do not modify without review
- Never commit `.env`, credentials, or secrets
- Always test keygen and keysign flows after refactoring

## Knowledge Base

For deeper context, see [vultisig-knowledge](https://github.com/vultisig/vultisig-knowledge).

| Situation | Read |
|-----------|------|
| First time in this repo | [repos/vultisig-ios.md](https://github.com/vultisig/vultisig-knowledge/blob/main/repos/vultisig-ios.md) |
| Touching crypto/TSS code | [architecture/mpc-tss-explained.md](https://github.com/vultisig/vultisig-knowledge/blob/main/architecture/mpc-tss-explained.md) |
| Signing flow details | [architecture/signing-flow.md](https://github.com/vultisig/vultisig-knowledge/blob/main/architecture/signing-flow.md) |
| Cross-repo gotchas | [coding/gotchas.md](https://github.com/vultisig/vultisig-knowledge/blob/main/coding/gotchas.md) (see iOS section) |
| Cross-platform changes | [repos/index.md](https://github.com/vultisig/vultisig-knowledge/blob/main/repos/index.md) (dependency graph) |
