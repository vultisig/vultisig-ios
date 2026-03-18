# Architecture Migration Plan

## Goal

Restructure from hybrid layer/feature organization to **feature-first with shared Core**, making the codebase scalable and navigable as it grows past 1,200+ files.

## Target Structure

```
VultisigApp/
├── App/                    # Entry point
├── Core/                   # Shared infrastructure (no UI)
├── Components/             # Reusable UI building blocks
├── Blockchain/             # Unified chain logic
├── Model/                  # Core SwiftData models only
├── Features/               # Self-contained feature modules
├── Platform/               # iOS/macOS specific code
└── Resources/              # Assets, preview content
```

---

## Phase 1 — Dead Code Removal

**Risk**: Low — only deleting code with zero references.
**Impact**: Medium — reduces noise before restructuring, fewer files to move.

Audit confirmed **14 unused files** and **1 empty directory**. Every item below was verified via project-wide grep and build verification to have zero external references.

### Unused Components (Views/Components/)

- [ ] 1.1 Delete `Views/Components/BackupGuideAnimationView.swift` — unused view + enum
- [ ] 1.2 Delete `Views/Components/BackupNowDisclaimer.swift` — unused disclaimer view
- [ ] 1.3 Delete `Views/Components/KeygenStatusText.swift` — unused status text view
- [ ] 1.4 Delete `Views/Components/KeysignDiscoveryDisclaimer.swift` — unused disclaimer view
- [ ] 1.5 Delete `Views/Components/LookingForDevicesLoader.swift` — unused loader view
- [ ] 1.6 Delete `Views/Components/NetworkPrompts.swift` — unused view (`NetworkPromptType` enum is still used elsewhere)
- [ ] 1.7 Delete `Views/Components/SetupVaultSecureText.swift` — unused text view
- [ ] 1.8 Delete `Views/Components/TokenSelectorDropdown.swift` — unused dropdown view
- [ ] 1.9 Delete `Views/Components/UpgradeFromGG20HomeBanner.swift` — unused banner view
- [ ] 1.10 Delete `Views/Components/WifiInstruction.swift` — unused instruction view
- [ ] 1.11 Delete `Views/Components/Cells/ChainCarouselButton.swift` — unused cell component

### Duplicate / Stale Layout Files (Views/Components/Layout/)

- [ ] 1.12 Delete `Views/Components/Layout/ContainterView.swift` — duplicate of `ContainerView.swift` (typo in filename, defines same `ContainerView<Content>` struct)
- [ ] 1.13 Delete `Views/Components/Layout/BoxView.swift` — defines unused `ContainterView<Content>` (typo in struct name, zero references)

### Unused Views

- [ ] 1.14 Delete `Views/Vault/BackupSetupScreen.swift` — unused `VaultBackupNowScreen` view

### Empty Directories

- [ ] 1.15 Delete empty `Models/` directory (all models live in `Model/`)

### Verification

- [ ] 1.16 Update `project.pbxproj` (remove deleted file references)
- [ ] 1.17 Verify build succeeds on both iOS and macOS targets
- [ ] 1.18 Run SwiftLint — no new warnings

> **Note**: `Extensions/Combine/CombineLatest.swift` was initially flagged but is actually used by `Views/Forms/Form.swift` via the `.combineLatest()` Array extension. Kept.

---

## Phase 2 — Extract Components & Create Shell

**Risk**: Low
**Impact**: High — establishes the new structure and decouples reusable UI from feature views.

### Tasks

- [ ] 2.1 Create new top-level directories: `App/`, `Core/`, `Components/`, `Blockchain/`, `Platform/`, `Resources/`
- [ ] 2.2 Move `VultisigApp.swift` and `ContentView.swift` into `App/`
- [ ] 2.3 Move `iOS/AppDelegate.swift` and `macOS/MacAppDelegate.swift` into `App/`
- [ ] 2.4 Move `Views/Components/` contents into `Components/`, preserving subdirectory structure:
  - `Buttons/`, `Cells/`, `TextFields/`, `Banners/`, `Loaders/`, `Sheet/`, `Toolbar/`, `Screen/`, `Animations/`, `Background/`, `Icons/`, `ImageView/`, `Layout/`, `List/`, `Navigation Header/`, `Navigation Items/`, `Picker/`, `ScrollView/`, `SegmentedControls/`, `TabBar/`, `Text/`, `TextEditor/`, `Tooltip/`, `ViewModifiers/`, `Forms/`, `Swap/`, `banxa/`, `ActionBanner/`
- [ ] 2.5 Update all import paths / file references in `project.pbxproj`
- [ ] 2.6 Verify build succeeds on both iOS and macOS targets
- [ ] 2.7 Run SwiftLint — no new warnings

---

## Phase 3 — Unify Blockchain ✅

**Risk**: Medium (touches chain services and signing logic)
**Impact**: High — collocates each chain's signing, API, and models.
**Status**: Completed — 163 files moved via `git mv`, `project.pbxproj` updated, build passes, no new SwiftLint warnings.

### Tasks

- [x] 3.1 Create `Blockchain/Common/` and move shared files (7 files including `CoinFactory+QBTC.swift`)
- [x] 3.2 Move `Tss/` into `Blockchain/Tss/` (6 files, preserved as-is)
- [x] 3.3 Move `States/Keygen/` and `States/Keysign/` into `Blockchain/States/` (15 files)
- [x] 3.4 Unify **EVM** chain (6 files)
- [x] 3.5 Unify **Cosmos** chain (23 files)
- [x] 3.6 Unify **UTXO** chain (9 files, including `UTXOTransactionMempoolPreviousOutput.swift` from Model root)
- [x] 3.7 Unify **Solana** (8 files)
- [x] 3.8 Unify **THORChain** (41 files)
- [x] 3.9 Unify **Maya** (14 files)
- [x] 3.10 Unify remaining chains: Sui (5), Ton (3), Tron (4), Ripple (2), Polkadot (2), Cardano (2)
- [x] 3.11 Move swap protocol services into `Blockchain/Swaps/` (16 files)
- [x] 3.12 Delete now-empty `Chains/`, `Tss/`, `States/Keygen/`, `States/Keysign/`, and all emptied service/model subdirectories
- [x] 3.13 Update `project.pbxproj`
- [x] 3.14 Verify build succeeds (iOS)
- [x] 3.15 Run SwiftLint — no new warnings

---

## Phase 4 — Migrate Features (one at a time) ✅

**Risk**: Low per feature (incremental)
**Impact**: High cumulative — moves from layer-based to feature-based.
**Status**: Completed — 243 files moved via `git mv`, `project.pbxproj` updated via `xcodeproj` gem.

For each feature: move its views from `Views/`, view models from `View Models/`, and any feature-specific services from `Services/` into `Features/<Name>/`.

### 4A — Send

- [x] 4A.1 Move `Views/Send/` → `Features/Send/Views/` (13 files)
- [x] 4A.2 Move Send view models → `Features/Send/ViewModels/` (7 files)
- [x] 4A.3 No dedicated Send services to move
- [x] 4A.4 Build + lint check

### 4B — Swap

- [x] 4B.1 Move `Views/Swap/` → `Features/Swap/Views/` (9 files)
- [x] 4B.2 Move `View Models/Swap/` + loose Swap VMs → `Features/Swap/ViewModels/` (4 files)
- [x] 4B.3 Build + lint check

### 4C — Keygen

- [x] 4C.1 Move `Views/Keygen/` → `Features/Keygen/Views/` (13 files)
- [x] 4C.2 Move Keygen view models → `Features/Keygen/ViewModels/` (4 files)
- [x] 4C.3 No `Services/Keygen/` exists
- [x] 4C.4 Build + lint check

### 4D — Keysign

- [x] 4D.1 Move `Views/Keysign/` → `Features/Keysign/Views/` (17 files)
- [x] 4D.2 Move Keysign view models → `Features/Keysign/ViewModels/` (5 files)
- [x] 4D.3 Move `Services/Keysign/` → `Features/Keysign/Services/` (14 files)
- [x] 4D.4 Build + lint check

### 4E — Settings

- [x] 4E.1 Move `Views/Settings/` → `Features/Settings/Views/` (17 files)
- [x] 4E.2 Move Settings view models → `Features/Settings/ViewModels/` (2 files)
- [x] 4E.3 Move `Model/Settings/` → `Features/Settings/Models/` (1 file)
- [x] 4E.4 Build + lint check

### 4F — Vault (main wallet screens)

- [x] 4F.1 Move `Views/Vault/` → `Features/Wallet/Views/` (11 files)
- [x] 4F.2 Move Vault view models + `VaultPairDetailViewModel/` → `Features/Wallet/ViewModels/` (5 files)
- [x] 4F.3 Build + lint check

### 4G — Referral

- [x] 4G.1 Move `Views/Referral/` → `Features/Referral/Views/` (13 files)
- [x] 4G.2 Move `View Models/Referral/` → `Features/Referral/ViewModels/` (7 files)
- [x] 4G.3 Build + lint check

### 4H — Address Book

- [x] 4H.1 Move `Views/Address Book/` → `Features/AddressBook/Views/` (7 files)
- [x] 4H.2 Move `View Models/AddressBook/` → `Features/AddressBook/ViewModels/` (1 file)
- [x] 4H.3 Move `Model/AddressBook/` → `Features/AddressBook/Models/` (1 file)
- [x] 4H.4 Build + lint check

### 4I — Agent

- [x] 4I.1 Move `Views/Agent/` → `Features/Agent/Views/` (5 files)
- [x] 4I.2 Move `View Models/Agent/` → `Features/Agent/ViewModels/` (5 files)
- [x] 4I.3 Move `Services/Agent/` → `Features/Agent/Services/` (6 files)
- [x] 4I.4 Build + lint check

### 4J — FunctionCall

- [x] 4J.1 Move `Views/FunctionCall/` → `Features/FunctionCall/Views/` (6 files)
- [x] 4J.2 Move `Model/FunctionCall/` → `Features/FunctionCall/Models/` (20 files)
- [x] 4J.3 Move FunctionCall view models → `Features/FunctionCall/ViewModels/` (2 files)
- [x] 4J.4 Build + lint check

### 4K — Reshare

- [x] 4K.1 Move `Views/Reshare/` → `Features/Reshare/Views/` (3 files)
- [x] 4K.2 Build + lint check

### 4L — Remaining Views cleanup

- [x] 4L.1 Move `Views/Notifications/` → `Features/Notifications/Views/` (3 files)
- [x] 4L.2 Move `Views/Onboarding/` → `Features/Onboarding/Views/` (2 files, merged with existing)
- [x] 4L.3 Move `Views/Update Check/` → `Features/UpdateCheck/Views/` (3 files)
- [x] 4L.4 Move `Views/UpgradeFromGG20/` → `Features/UpgradeFromGG20/Views/` (3 files)
- [x] 4L.5 Move `Views/New Wallet/` → `Features/Onboarding/Views/` (1 file)
- [x] 4L.6 Move `Views/CoinPicker/` → `Features/Wallet/Views/` (1 file)
- [x] 4L.7 Move `Views/MoonPay/` → `Features/MoonPay/Views/` (1 file)
- [x] 4L.8 Move `Views/Utils/`, `Views/PreferenceKeys/`, `Views/Transitions/`, `Views/Forms/`, loose files → `Components/` (15 files); `ThorchainPoolListView.swift` → `Features/Defi/`
- [x] 4L.9 Deleted now-empty `Views/` group (removed 2 stale Transactions references)
- [ ] 4L.10 `View Models/` still has 18 orphaned files — deferred to Phase 6
- [x] 4L.11 Build + lint check (0 new warnings)

---

## Phase 5 — Extract Core from Services ✅

**Risk**: Low
**Impact**: Medium — cleans up the Services grab bag.
**Status**: Completed — 190 files moved via `git mv`, `project.pbxproj` updated via `xcodeproj` gem.

### Tasks

- [x] 5.1 Move `Services/Network/` → `Core/Networking/` (5 files)
- [x] 5.2 Move `Services/Storage/` → `Core/Storage/` (1 file)
- [x] 5.3 Move `Services/Keychain/` → `Core/Storage/Keychain/` (3 files)
- [x] 5.4 Move `Services/Biometry/` → `Core/Security/Biometry/` (2 files)
- [x] 5.5 Move `Services/Security/` → `Core/Security/` (7 files)
- [x] 5.6 Move `Services/Notification/` → `Core/Notifications/` (9 files)
- [x] 5.7 Move `Services/Fee/` → `Core/Services/Fee/` (2 files)
- [x] 5.8 Move `Services/Rates/` → `Core/Services/Rates/` (4 files)
- [x] 5.9 Move `Services/Protobuf/` → `Core/Protobuf/` (4 files)
- [x] 5.10 Move `Services/AppMigration/` → `Core/Migration/` (2 files)
- [x] 5.11 Move `Services/TransactionHistory/` → `Features/TransactionHistory/Services/` (2 files)
- [x] 5.12 Move `Services/TransactionStatus/` → `Core/Services/TransactionStatus/` (8 files)
- [x] 5.13 Move `Services/VultiServer/` → `Core/Services/VultiServer/` (3 files)
- [x] 5.14 Move `Services/FastVault/` → `Core/Services/FastVault/` (2 files)
- [x] 5.15 Move `Services/Actions/` → `Core/Services/Actions/` (5 files)
- [x] 5.16 Move remaining single-file services (14 files) → `Core/Services/`
- [x] 5.17 Deleted now-empty `Services/` group
- [x] 5.18 Move `DesignSystem/` → `Core/DesignSystem/` (4 files)
- [x] 5.19 Move `Extensions/` → `Core/Extensions/` (26 files)
- [x] 5.20 Move `Utils/` → `Core/Utils/` (33 files)
- [x] 5.21 Move `Stores/` → `Core/Stores/` (4 files)
- [x] 5.22 Move `Navigation/` → `Core/Navigation/` (3 files)
- [x] 5.23 Move `Localizables/` → `Core/Localizables/` (7 locale dirs)
- [x] 5.24 Update `project.pbxproj`
- [x] 5.25 Build + lint check (0 new warnings)

---

## Phase 6 — Cleanup ✅

**Risk**: Low
**Impact**: Medium — final structural polish.
**Status**: Completed — 49 files moved, `States/` and `View Models/` directories eliminated.

### Tasks

- [x] 6.1 Move remaining `States/` files → `Core/States/` (5 files) + `ReferralTextFieldAction.swift` → `Features/Referral/`
- [x] 6.2 Move 18 orphaned View Models: 7 → `Core/ViewModels/`, 9 → `Features/Wallet/ViewModels/`, 1 → `Features/Home/ViewModels/`, 1 → `Features/UpdateCheck/ViewModels/`
- [x] 6.3 Slim down `Model/` — moved 25 feature-specific models:
  - 2 → `Features/TransactionHistory/Models/`
  - 2 → `Features/Referral/Models/`
  - 2 → `Features/Defi/Models/`
  - 7 → `Features/Wallet/Models/`
  - 1 → `Features/AddressBook/Models/`
  - 2 → `Features/Keysign/Models/`
  - 4 → `Features/Keygen/Models/`
  - 5 → `Core/Models/`
  - Remaining in `Model/`: core entities (`Vault`, `Coin`, `Chain`, `KeyShare`, `CoinMeta`, `PendingTransaction`, `VaultSettings`, `DerivationPath`, `DeviceInfo`)
- [x] 6.4 Update `project.pbxproj`
- [x] 6.5 Build verification (iOS) — passes
- [x] 6.6 SwiftLint — 0 new warnings

---

## Phase 7 — Unify Platform Extensions

**Risk**: Medium (touches every `+iOS`/`+macOS` file pair)
**Impact**: High — eliminates file duplication and simplifies maintenance.

Merge `iOS/` and `macOS/` platform-specific view extensions back into their main files using `#if os(iOS)` / `#if os(macOS)` conditionals. This removes the separate platform directories entirely.

### Tasks

- [ ] 7.1 Audit all files in `iOS/` and `macOS/` — list each pair and its main counterpart
- [ ] 7.2 For each pair, merge the platform-specific code into the main file using `#if os()` blocks
- [ ] 7.3 Delete the now-empty `iOS/` and `macOS/` directories
- [ ] 7.4 Update `project.pbxproj`
- [ ] 7.5 Full build verification (iOS + macOS)
- [ ] 7.6 Full SwiftLint pass

---

## Rules for Every Phase

1. **One PR per phase** (or per sub-phase for Phase 3) — keeps reviews manageable.
2. **No logic changes** — only file moves and import path updates. If a file needs refactoring, that's a separate PR.
3. **Build must pass** after every task group. Never merge a broken build.
4. **SwiftLint must pass** — no new warnings.
5. **Update `project.pbxproj`** via `/add-xcode-files` skill — never edit manually.
6. **Do not touch `Tss/`** internal structure — only move the directory as a unit.
