# vultisig-ios — Agent Reference

## Overview

iOS/macOS wallet app with SwiftUI, SwiftData, and DKLS23 TSS implementation. 40+ blockchains, vault-based key management, DeFi integrations.

## Quick Start

```bash
git clone https://github.com/vultisig/vultisig-ios.git
cd vultisig-ios
open VultisigApp.xcodeproj
# Build: Cmd+B or xcodebuild -scheme VultisigApp -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Before You Change Code

1. Run SwiftLint: `swiftlint lint --config VultisigApp/.swiftlint.yml VultisigApp/`
2. If touching TSS/crypto: extra caution — changes affect signing across all platforms
3. If touching `project.pbxproj`: use `/add-xcode-files` skill, never edit directly
4. If adding/removing strings: update ALL 7 locale `Localizable.strings` files, run `sort_localizable.py`
5. If deleting a screen: remove route, ViewModel, strings, drawables — full cleanup

## Patterns

- MVVM with ObservableObject ViewModels
- SwiftData `@Model` classes (always on MainActor)
- async/await for all concurrency (no completion handlers)
- Theme.colors.* and Theme.fonts.* for all styling (never hardcode)
- `PrimaryButton` for all buttons (never custom styles)
- `Screen` component for full-screen views
- `TargetType` + `HTTPClient` for networking
- `.foregroundStyle()` not `.foregroundColor()`

## Security Notes

- Never log key material or vault shares
- TSS bindings — do not modify without review
- Always test keygen and keysign flows after refactoring
- Use `.localized` for all user-facing strings

## Knowledge Base

For deeper context beyond this file, see [vultisig-knowledge](https://github.com/vultisig/vultisig-knowledge).

Key docs for this repo:
- [repos/vultisig-ios.md](https://github.com/vultisig/vultisig-knowledge/blob/main/repos/vultisig-ios.md)
- [architecture/mpc-tss-explained.md](https://github.com/vultisig/vultisig-knowledge/blob/main/architecture/mpc-tss-explained.md)
- [architecture/signing-flow.md](https://github.com/vultisig/vultisig-knowledge/blob/main/architecture/signing-flow.md)
- [coding/gotchas.md](https://github.com/vultisig/vultisig-knowledge/blob/main/coding/gotchas.md) (see iOS section)
