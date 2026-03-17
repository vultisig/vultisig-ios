# Vultisig iOS - Claude Guidelines

## Security Tier

HIGH — Wallet app with TSS key management. Crypto/JNI changes require maintainer review.

## Critical Boundaries

- `VultisigApp/Services/Tss/` — TSS keygen/keysign bindings. Do not modify without explicit review.
- `VultisigApp/Model/` — SwiftData models. Schema changes affect migrations.
- `VultisigApp.xcodeproj/project.pbxproj` — Use `/add-xcode-files` skill, never edit directly.

## Project Overview

Vultisig is a multi-chain cryptocurrency wallet for iOS and macOS built with SwiftUI. Supports 40+ blockchains (THORChain, Maya, EVM, Cosmos, Solana, UTXO, etc.) with vault-based key management, DeFi integrations, and cross-device TSS signing.

## Directory Structure

```text
VultisigApp/
├── DesignSystem/       # Theme, colors, fonts (Theme.colors.*, Theme.fonts.*)
├── Services/           # API clients, blockchain services, networking (HTTPClient, TargetType)
├── Views/Components/   # Reusable UI (PrimaryButton, CommonTextField, Screen, Toolbar, Sheet)
├── Features/           # Feature-based modules
├── View Models/        # ObservableObject state containers
├── Navigation/         # Routing (NavigationRouter, *Route enums, *Router)
├── Model/              # SwiftData @Model classes (Vault, Coin, etc.)
├── Stores/             # Shared data stores
└── Extensions/         # Swift type extensions
```

## Mandatory Rules

1. **Design System** — Always use `Theme.colors.*` and `Theme.fonts.*`. Never hardcode colors/fonts. Use price fonts (`priceTitle1`, `priceBodyL`, `priceBodyS`) for numbers and balances.
2. **SwiftData** — Never access `@Model` classes off MainActor. Use value types across actor boundaries.
3. **Networking** — Use `TargetType` protocol for all API endpoints. Use `HTTPClient` with async/await.
4. **Localization** — Never hardcode user-facing strings. Use `"key".localized`. Add to ALL 7 `Localizable.strings` (en, de, es, hr, it, pt, zh-Hans) in `VultisigApp/Localizables/`. camelCase keys, alphabetical order. Run `sort_localizable.py` after.
5. **Buttons** — Always use `PrimaryButton`. Never create custom button styles.
6. **Deprecated APIs** — Use `.foregroundStyle()` not `.foregroundColor()`.
7. **Concurrency** — Use async/await. Never use callbacks/completion handlers.
8. **Screens** — Use `Screen` component for full-screen views. Suffix with `Screen`.
9. **SwiftLint** — Never introduce new warnings. Run `swiftlint lint --config VultisigApp/.swiftlint.yml VultisigApp/` after changes.
10. **Cross-Platform** — Use `crossPlatformToolbar`, `crossPlatformSheet`, `#if os(macOS)`. No platform-specific view files.
11. **Architecture** — Business logic in ViewModels/Services, never in views. No UIKit unless necessary.

## Skills Reference

Domain knowledge loads on-demand via skills:

| Skill | Content |
|-------|---------|
| `swift-patterns` | State management, navigation, code style, naming conventions, common patterns, testing, build commands |
| `networking-guide` | TargetType, HTTPClient, HTTPTask, services, error handling, real examples |
| `ui-components` | Colors, fonts, gradients, PrimaryButton, CommonTextField, Screen, Toolbar, Sheet, cells, banners, loaders, view modifiers, localization details |
| `swiftdata-guide` | All 14 @Model classes, Storage API, three-phase architecture, batch upsert, Swift 6 Sendable |
| `blockchain-guide` | Chain services, BlockChainSpecific, TSS keygen/keysign, vault key management, 40+ chains |
| `ui-testing` | XCUITest architecture, AccessibilityID enum, page objects, test helpers, test execution |
| `/lint` | SwiftLint commands, config summary, common warnings, fix guidance |
| `/build-check` | SwiftLint + xcodebuild full quality check |
| `/add-xcode-files` | Add new .swift files to project.pbxproj |
| `/batch` | Overnight task runner — PRDs, parallel worktree agents, PRs with CodeRabbit integration |
| `/batch-review` | Morning dashboard — PR statuses, CodeRabbit feedback, next actions |
| `/batch-retry` | Retry failed batch tasks — cleanup, re-execute with failure context |
| `/batch-fix-reviews` | Auto-fix CodeRabbit review comments, push fixes, re-request review |
| `/localize` | Complete i18n workflow — add keys to all 7 locale files, translate, sort |
| `/ship` | Commit + create PR in one step, with checks and Co-Authored-By |
| `/orchestrate` | God-mode orchestrator — end-to-end feature delivery or exhaustive PR review |
| `/create-issue` | Create GitHub issues with bug/feature templates and size guide |
| `/check-platforms` | Search Android, Windows, backend repos for feature implementations |
| `/reference-codebases` | Port features from sibling repos with pattern mapping |
| `/figma` | Implement UI from Figma designs via MCP with mandatory property mapping |

## Knowledge Base

For deeper context, see [vultisig-knowledge](https://github.com/vultisig/vultisig-knowledge). Read only when needed:

| Situation | Read |
|-----------|------|
| First time in this repo | [repos/vultisig-ios.md](https://github.com/vultisig/vultisig-knowledge/blob/main/repos/vultisig-ios.md) |
| Touching crypto/TSS code | [architecture/mpc-tss-explained.md](https://github.com/vultisig/vultisig-knowledge/blob/main/architecture/mpc-tss-explained.md) |
| Signing flow details | [architecture/signing-flow.md](https://github.com/vultisig/vultisig-knowledge/blob/main/architecture/signing-flow.md) |
| Cross-repo gotchas | [coding/gotchas.md](https://github.com/vultisig/vultisig-knowledge/blob/main/coding/gotchas.md) (see iOS section) |
| Cross-platform changes | [repos/index.md](https://github.com/vultisig/vultisig-knowledge/blob/main/repos/index.md) (dependency graph) |
