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

## Phase 3 — Unify Blockchain

**Risk**: Medium (touches chain services and signing logic)
**Impact**: High — collocates each chain's signing, API, and models.

### Tasks

- [ ] 3.1 Create `Blockchain/Common/` and move shared files:
  - `Chains/CoinFactory.swift`, `CoinFactory+Cardano.swift`
  - `Chains/common.swift`, `Chains/publickey.swift`, `Chains/erc20.swift`
  - `Chains/SignedTransactionResult.swift`
- [ ] 3.2 Move `Tss/` into `Blockchain/Tss/` (preserve as-is, critical boundary)
- [ ] 3.3 Move `States/Keygen/` and `States/Keysign/` into `Blockchain/States/`
- [ ] 3.4 Unify **EVM** chain:
  - `Chains/EVM/` → `Blockchain/EVM/Signing/`
  - `Services/Evm/` → `Blockchain/EVM/Service/`
- [ ] 3.5 Unify **Cosmos** chain:
  - `Chains/Cosmos/` → `Blockchain/Cosmos/Signing/`
  - `Services/Cosmos/` → `Blockchain/Cosmos/Service/`
  - `Model/Cosmos/` → `Blockchain/Cosmos/Models/`
- [ ] 3.6 Unify **UTXO** chain:
  - `Chains/UTXOChainsHelper.swift` → `Blockchain/UTXO/Signing/`
  - `Services/UTXO/` → `Blockchain/UTXO/Service/`
  - `Model/UTXO/` → `Blockchain/UTXO/Models/`
- [ ] 3.7 Unify **Solana**:
  - `Chains/Solana.swift`, `Chains/SolanaSwaps.swift` → `Blockchain/Solana/Signing/`
  - `Services/Solana/` → `Blockchain/Solana/Service/`
  - `Model/Solana/` → `Blockchain/Solana/Models/`
- [ ] 3.8 Unify **THORChain**:
  - `Chains/thorchain.swift`, `Chains/THORChainSwaps.swift` → `Blockchain/THORChain/Signing/`
  - `Services/THORChainAPI/` → `Blockchain/THORChain/API/`
  - `Services/Thorchain/` → `Blockchain/THORChain/Service/`
- [ ] 3.9 Unify **Maya**:
  - `Chains/maya.swift` → `Blockchain/Maya/Signing/`
  - `Services/MayaChainAPI/` → `Blockchain/Maya/API/`
- [ ] 3.10 Unify remaining chains (one subdirectory each):
  - **Sui**: `Chains/Sui.swift` + `Services/Sui/` + `Model/Sui/`
  - **Ton**: `Chains/Ton.swift` + `Services/Ton/` + `Model/Ton/`
  - **Tron**: `Chains/Tron.swift` + `Services/Tron/`
  - **Ripple**: `Chains/Ripple.swift` + `Services/Ripple/`
  - **Polkadot**: `Chains/Polkadot.swift` + `Services/Polkadot/`
  - **Cardano**: `Chains/Cardano.swift` + `Services/Cardano/`
- [ ] 3.11 Move swap protocol services into relevant chain or `Blockchain/Swaps/`:
  - `Services/1inch/` → `Blockchain/Swaps/OneInch/`
  - `Services/KyberSwap/` → `Blockchain/Swaps/KyberSwap/`
  - `Services/LiFi/` → `Blockchain/Swaps/LiFi/`
  - `Services/SwapService/` → `Blockchain/Swaps/Common/`
  - `Chains/OneInchSwaps.swift` → `Blockchain/Swaps/OneInch/`
- [ ] 3.12 Delete now-empty `Chains/` and `States/Keygen/`, `States/Keysign/` directories
- [ ] 3.13 Update `project.pbxproj`
- [ ] 3.14 Verify build succeeds on both targets
- [ ] 3.15 Run SwiftLint — no new warnings

---

## Phase 4 — Migrate Features (one at a time)

**Risk**: Low per feature (incremental)
**Impact**: High cumulative — moves from layer-based to feature-based.

For each feature: move its views from `Views/`, view models from `View Models/`, and any feature-specific services from `Services/` into `Features/<Name>/`.

### 4A — Send

- [ ] 4A.1 Move `Views/Send/` → `Features/Send/Views/`
- [ ] 4A.2 Move `View Models/SendCryptoViewModel.swift`, `SendCryptoVerifyViewModel.swift`, `SendCryptoVerifyLogic.swift` → `Features/Send/ViewModels/`
- [ ] 4A.3 Move related services if any → `Features/Send/Services/`
- [ ] 4A.4 Build + lint check

### 4B — Swap

- [ ] 4B.1 Move `Views/Swap/` → `Features/Swap/Views/`
- [ ] 4B.2 Move `View Models/Swap/` → `Features/Swap/ViewModels/`
- [ ] 4B.3 Build + lint check

### 4C — Keygen

- [ ] 4C.1 Move `Views/Keygen/` → `Features/Keygen/Views/`
- [ ] 4C.2 Move `View Models/KeygenViewModel.swift`, `KeygenVerifyViewModel.swift` → `Features/Keygen/ViewModels/`
- [ ] 4C.3 Move `Services/Keygen/` if it exists → `Features/Keygen/Services/`
- [ ] 4C.4 Build + lint check

### 4D — Keysign

- [ ] 4D.1 Move `Views/Keysign/` → `Features/Keysign/Views/`
- [ ] 4D.2 Move `View Models/KeysignViewModel.swift` → `Features/Keysign/ViewModels/`
- [ ] 4D.3 Move `Services/Keysign/` → `Features/Keysign/Services/`
- [ ] 4D.4 Build + lint check

### 4E — Settings

- [ ] 4E.1 Move `Views/Settings/` → `Features/Settings/Views/`
- [ ] 4E.2 Move `View Models/SettingsViewModel.swift` and related → `Features/Settings/ViewModels/`
- [ ] 4E.3 Move `Model/Settings/` → `Features/Settings/Models/`
- [ ] 4E.4 Build + lint check

### 4F — Vault (main wallet screens)

- [ ] 4F.1 Move `Views/Vault/` into `Features/Wallet/Views/`
- [ ] 4F.2 Move `View Models/VaultDetailViewModel.swift`, `View Models/Vault/` → `Features/Wallet/ViewModels/`
- [ ] 4F.3 Build + lint check

### 4G — Referral

- [ ] 4G.1 Move `Views/Referral/` → `Features/Referral/Views/`
- [ ] 4G.2 Move `View Models/Referral/` → `Features/Referral/ViewModels/`
- [ ] 4G.3 Build + lint check

### 4H — Address Book

- [ ] 4H.1 Move `Views/Address Book/` → `Features/AddressBook/Views/`
- [ ] 4H.2 Move `View Models/AddressBook/` → `Features/AddressBook/ViewModels/`
- [ ] 4H.3 Move `Model/AddressBook/` → `Features/AddressBook/Models/`
- [ ] 4H.4 Build + lint check

### 4I — Agent

- [ ] 4I.1 Move `Views/Agent/` → `Features/Agent/Views/`
- [ ] 4I.2 Move `View Models/Agent/` → `Features/Agent/ViewModels/`
- [ ] 4I.3 Move `Services/Agent/` → `Features/Agent/Services/`
- [ ] 4I.4 Build + lint check

### 4J — FunctionCall

- [ ] 4J.1 Move `Views/FunctionCall/` → `Features/FunctionCall/Views/`
- [ ] 4J.2 Move `Model/FunctionCall/` → `Features/FunctionCall/Models/`
- [ ] 4J.3 Build + lint check

### 4K — Reshare

- [ ] 4K.1 Move `Views/Reshare/` → `Features/Reshare/Views/`
- [ ] 4K.2 Build + lint check

### 4L — Remaining Views cleanup

- [ ] 4L.1 Move `Views/Notifications/` → `Features/Notifications/Views/`
- [ ] 4L.2 Move `Views/Onboarding/` → `Features/Onboarding/Views/` (merge with existing `Features/Onboarding/`)
- [ ] 4L.3 Move `Views/Update Check/` → `Features/UpdateCheck/Views/`
- [ ] 4L.4 Move `Views/UpgradeFromGG20/` → `Features/UpgradeFromGG20/Views/`
- [ ] 4L.5 Move `Views/New Wallet/` → `Features/Onboarding/Views/`
- [ ] 4L.6 Move `Views/CoinPicker/` → `Features/Wallet/Views/`
- [ ] 4L.7 Move `Views/MoonPay/` → `Features/MoonPay/Views/`
- [ ] 4L.8 Move `Views/Utils/`, `Views/PreferenceKeys/`, `Views/Transitions/`, `Views/Forms/` → `Components/`
- [ ] 4L.9 Delete now-empty `Views/` directory
- [ ] 4L.10 Delete now-empty `View Models/` directory
- [ ] 4L.11 Build + lint check

---

## Phase 5 — Extract Core from Services

**Risk**: Low
**Impact**: Medium — cleans up the Services grab bag.

### Tasks

- [ ] 5.1 Move `Services/Network/` → `Core/Networking/`
- [ ] 5.2 Move `Services/Storage/` → `Core/Storage/`
- [ ] 5.3 Move `Services/Keychain/` → `Core/Storage/Keychain/`
- [ ] 5.4 Move `Services/Biometry/` → `Core/Security/Biometry/`
- [ ] 5.5 Move `Services/Security/` → `Core/Security/`
- [ ] 5.6 Move `Services/Notification/` → `Core/Notifications/`
- [ ] 5.7 Move `Services/Fee/` → `Core/Services/Fee/`
- [ ] 5.8 Move `Services/Rates/` → `Core/Services/Rates/`
- [ ] 5.9 Move `Services/Protobuf/` → `Core/Protobuf/`
- [ ] 5.10 Move `Services/AppMigration/` → `Core/Migration/`
- [ ] 5.11 Move `Services/TransactionHistory/` → `Features/TransactionHistory/Services/`
- [ ] 5.12 Move `Services/TransactionStatus/` → `Core/Services/TransactionStatus/`
- [ ] 5.13 Move `Services/VultiServer/` → `Core/Services/VultiServer/`
- [ ] 5.14 Move `Services/FastVault/` → `Core/Services/FastVault/`
- [ ] 5.15 Move `Services/Actions/` → `Core/Services/Actions/`
- [ ] 5.16 Move remaining single-file services (`AddressService`, `CoinService`, `BalanceService`, `BlockChainService`, `CryptoPriceService`, `PendingTransactionManager`, `FeatureFlagService`, `PayloadService`, `MemoDecodingService`, `FourByteRepository`) → `Core/Services/`
- [ ] 5.17 Delete now-empty `Services/` directory
- [ ] 5.18 Move `DesignSystem/` → `Core/DesignSystem/`
- [ ] 5.19 Move `Extensions/` → `Core/Extensions/`
- [ ] 5.20 Move `Utils/` → `Core/Utils/`
- [ ] 5.21 Move `Stores/` → `Core/Stores/`
- [ ] 5.22 Move `Navigation/` → `Core/Navigation/`
- [ ] 5.23 Move `Localizables/` → `Core/Localizables/`
- [ ] 5.24 Update `project.pbxproj`
- [ ] 5.25 Build + lint check

---

## Phase 6 — Platform & Cleanup

**Risk**: Low
**Impact**: Medium — final polish.

### Tasks

- [ ] 6.1 Move `iOS/` → `Platform/iOS/`
- [ ] 6.2 Move `macOS/` → `Platform/macOS/`
- [ ] 6.3 Move remaining `States/` files (UI states like `SetupVaultState`, `NetworkPromptType`, etc.) → appropriate features or `Core/States/`
- [ ] 6.4 Move `Assets.xcassets/` → `Resources/Assets.xcassets/`
- [ ] 6.5 Move `Preview Content/` → `Resources/Preview Content/`
- [ ] 6.6 Clean up any orphaned `View Models/` that weren't caught in Phase 4 (e.g., `AppViewModel`, `GlobalStateViewModel`, `HomeViewModel`, `DeeplinkViewModel`) → move to relevant features or `Core/`
- [ ] 6.7 Slim down `Model/` — move feature-specific models that were missed:
  - `Model/TransactionHistoryItem.swift` → `Features/TransactionHistory/Models/`
  - `Model/ReferralCode.swift` → `Features/Referral/Models/`
  - `Model/StakingDetails.swift`, `DefiPositions.swift` → `Features/DeFi/Models/`
  - Keep only core entities: `Vault`, `Coin`, `Chain`, `KeyShare`, `CoinMeta`, `PendingTransaction`, `VaultSettings`
- [ ] 6.8 Final `project.pbxproj` update
- [ ] 6.9 Full build verification (iOS + macOS)
- [ ] 6.10 Full SwiftLint pass
- [ ] 6.11 Update `CLAUDE.md` directory structure documentation
- [ ] 6.12 Delete this migration plan file

---

## Rules for Every Phase

1. **One PR per phase** (or per sub-phase for Phase 3) — keeps reviews manageable.
2. **No logic changes** — only file moves and import path updates. If a file needs refactoring, that's a separate PR.
3. **Build must pass** after every task group. Never merge a broken build.
4. **SwiftLint must pass** — no new warnings.
5. **Update `project.pbxproj`** via `/add-xcode-files` skill — never edit manually.
6. **Do not touch `Tss/`** internal structure — only move the directory as a unit.
