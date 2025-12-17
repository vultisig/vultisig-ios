# Navigation Migration Progress

## Goal
Replace all `navigationDestination` calls with NavPath routing using VultisigRouter and NavigationRouter pattern.

## Pattern
For each flow:
1. Create `[Flow]Route.swift` - enum with Hashable routes
2. Create `[Flow]Router.swift` - struct with build() method
3. Create `[Flow]RouteBuilder.swift` - struct with @ViewBuilder methods
4. Update `VultisigRouter.swift` - add router property
5. Update `ContentView.swift` - register route type
6. Migrate files - replace `.navigationDestination` with `.onChange(of:)` pattern

---

## ✅ Completed Flows (6/10)

### 1. Keygen Flow - 9 files migrated ✓
**Created:**
- `VultisigApp/Views/Keygen/Navigation/KeygenRoute.swift`
- `VultisigApp/Views/Keygen/Navigation/KeygenRouter.swift`
- `VultisigApp/Views/Keygen/Navigation/KeygenRouteBuilder.swift`

**Routes:**
- `fastBackupOverview(tssType, vault, email)`
- `secureBackupOverview(vault)`
- `backupNow(tssType, backupType, isNewVault)`
- `keyImportOverview(vault, email, keyImportInput)`
- `peerDiscovery(tssType, vault, selectedTab, fastSignConfig, keyImportInput)`
- `fastVaultSetHint(tssType, vault, selectedTab, email, password, exist)`
- `fastVaultSetPassword(tssType, vault, selectedTab, email, exist)`
- `newWalletName(tssType, selectedTab, name)`

**Migrated Files:**
1. KeygenView.swift
2. FastVaultSetPasswordView.swift
3. FastVaultEmailView+iOS.swift
4. FastVaultEmailView+macOS.swift
5. FastVaultSetHintView+iOS.swift
6. FastVaultSetHintView+macOS.swift
7. SecureBackupVaultOverview.swift
8. FastBackupVaultOverview.swift
9. PeerDiscoveryView.swift (route updated)

---

### 2. Vault Management Flow - 8 files migrated ✓
**Created:**
- `VultisigApp/Views/Vault/Navigation/VaultRoute.swift`
- `VultisigApp/Views/Vault/Navigation/VaultRouter.swift`
- `VultisigApp/Views/Vault/Navigation/VaultRouteBuilder.swift`

**Routes:**
- `upgradeVault(vault, isFastVault)`
- `serverBackup(vault)`
- `backupPasswordOptions(tssType, backupType, isNewVault)`
- `backupContainer(tssType, vault, backupType, password, isNewVault)`
- `backupNow(tssType, vault, backupType, isNewVault)`
- `vaultDeletion(vault)`
- `settingsDefaultChains`
- `changePassword(vault)`

**Migrated Files:**
1. VaultSettingsScreen.swift
2. BackupSetupScreen.swift (VaultBackupNowScreen)
3. VaultBackupPasswordOptionsScreen.swift
4. VaultBackupContainerView.swift
5. VaultBackupNowScreen.swift (Backup folder)
6. BackupVaultNowView.swift
7. VaultDeletionConfirmView.swift
8. (1 more - needs verification)

---

### 3. Onboarding/Import Flow - 6 files migrated ✓
**Created:**
- `VultisigApp/Features/Onboarding/Navigation/OnboardingRoute.swift`
- `VultisigApp/Features/Onboarding/Navigation/OnboardingRouter.swift`
- `VultisigApp/Features/Onboarding/Navigation/OnboardingRouteBuilder.swift`

**Routes:**
- `vaultSetup(tssType, keyImportInput)`
- `importSeedphrase(keyImportInput)`
- `chainsSetup(mnemonic)` - Fixed to take String instead of KeyImportInput
- `keyImportNewVaultSetup(vault, keyImportInput, fastSignConfig)` - Fixed to include all params
- `keyImportOnboarding`
- `importVaultShare`
- `setupQRCode(tssType, vault)`
- `joinKeygen(vault, selectedVault)`
- `onboarding`
- `newWalletName(tssType, selectedTab, vault)`

**Migrated Files:**
1. KeyImportOnboardingScreen.swift
2. KeyImportOverviewScreen.swift
3. KeyImportChainsSetupScreen.swift
4. KeyImportNewVaultSetupScreen.swift
5. VaultSetupScreen.swift
6. ImportSeedphraseScreen.swift

---

### 4. Referral Flow - 2 files migrated ✓
**Created:**
- `VultisigApp/Views/Referral/Navigation/ReferralRoute.swift`
- `VultisigApp/Views/Referral/Navigation/ReferralRouter.swift`
- `VultisigApp/Views/Referral/Navigation/ReferralRouteBuilder.swift`

**Routes:**
- `referredCodeForm(referredViewModel, referralViewModel)`
- `vaultSelection(selectedVault)` - Uses wrapper for @Binding

**Migrated Files:**
1. ReferralMainScreen.swift (also replaced NavigationLink with Button)
2. ReferralTransactionFlowScreen.swift

---

### 5. FunctionCall Flow - Infrastructure created ✓
**Created:**
- `VultisigApp/Views/FunctionCall/FunctionCallRoute.swift`
- `VultisigApp/Views/FunctionCall/FunctionCallRouter.swift`
- (Reused existing) `VultisigApp/Views/FunctionCall/FunctionCallRouteBuilder.swift`

**Routes:**
- `details(defaultCoin, sendTx, vault)`
- `verify(tx, vault)`
- `pair(vault, tx, keysignPayload, fastVaultPassword)`
- `keysign(input, tx)`

**Migrated Files:**
- None yet - infrastructure only created

---

### 6. Send Flow - 4 files migrated ✓
**Created:**
- SendRouter, SendRoute, SendRouteBuilder already existed

**Routes:**
- `details(coin, hasPreselectedCoin, tx, vault)`
- `verify(tx, vault)`
- `pairing(vault, tx, keysignPayload, fastVaultPassword)`
- `keysign(input, tx)`
- `done(vault, hash, chain, tx)`

**Migrated Files:**
1. SendDetailsScreen.swift
2. SendVerifyScreen.swift
3. SendPairScreen.swift
4. SendKeysignScreen.swift

**Note:** CoinPickerView navigation kept as `.navigationDestination` (utility picker, not main flow)

---

## ✅ Completed Flows (7/10)

### 7. Settings Flow - 1 file migrated ✓
**Created:**
- `VultisigApp/Views/Settings/Navigation/SettingsRoute.swift`
- `VultisigApp/Views/Settings/Navigation/SettingsRouter.swift`
- `VultisigApp/Views/Settings/Navigation/SettingsRouteBuilder.swift`

**Routes:**
- `vaultSettings(vault)`
- `vultDiscountTiers(vault)`
- `registerVaults(vault)`
- `language`
- `currency`
- `addressBook`
- `faq`
- `checkForUpdates`
- `advancedSettings`
- `vaultDetailQRCode(vault)`
- `referralOnboarding(referredViewModel)` - Uses StateWrapper for @StateObject
- `referrals(referralViewModel, referredViewModel)` - Uses StateWrapper for @StateObject

**Migrated Files:**
1. SettingsMainScreen.swift

---

### 8. DeFi Flow - 1 file migrated ✓
**Updated:**
- `VultisigApp/Views/FunctionCall/FunctionCallRoute.swift` - Added `functionTransaction` route
- `VultisigApp/Views/FunctionCall/FunctionCallRouter.swift` - Added handler for `functionTransaction`
- `VultisigApp/Views/FunctionCall/FunctionCallRouteBuilder.swift` - Added `buildFunctionTransactionScreen`

**Routes:**
- `functionTransaction(vault, transactionType)` - Navigates to FunctionTransactionScreen for DeFi operations

**Migrated Files:**
1. DefiChainMainScreen.swift

---

### 9. Home/Wallet Flow - 4 files migrated ✓
**Extended Routes:**
- Added `KeygenRoute.joinKeysign(vault)` for joining keysign sessions
- Added `VaultRoute.swap(fromCoin, vault)` for token swaps

**Migrated Files:**
1. HomeScreen.swift - Migrated VaultMainRoute/VaultAction handling to centralized routes
2. ChainDetailScreen.swift
3. UpgradeVaultViewModifier.swift
4. MonthlyBackupWarningViewModifier.swift

**Note:** macOS-specific MacScannerView kept as navigationDestination (platform-specific, low priority)

---

## 🔄 In Progress / Remaining Flows (1/10)

### 10. Miscellaneous - ~8 files
**Files:**
- FunctionTransactionScreen.swift
- VultDiscountTiersScreen.swift
- AddressBookCell.swift
- AddressFieldAccessoryStack.swift
- ReshareView+iOS.swift
- CreateVaultView+iOS.swift
- ContentView+iOS.swift
- MacScannerView.swift (macOS)

---

## Infrastructure Updates

### VultisigRouter.swift
```swift
final class VultisigRouter: ObservableObject {
    @Published var navigationRouter: NavigationRouter
    let sendRouter: SendRouter                    // ✓ Pre-existing
    let keygenRouter: KeygenRouter                // ✓ Added
    let vaultRouter: VaultRouter                  // ✓ Added
    let onboardingRouter: OnboardingRouter        // ✓ Added
    let referralRouter: ReferralRouter            // ✓ Added
    let functionCallRouter: FunctionCallRouter    // ✓ Added
    let settingsRouter: SettingsRouter            // ✓ Added
}
```

### ContentView.swift
```swift
NavigationStack(path: $navigationRouter.navPath) {
    container
        .navigationDestination(for: SendRoute.self) { ... }         // ✓ Pre-existing
        .navigationDestination(for: KeygenRoute.self) { ... }       // ✓ Added
        .navigationDestination(for: VaultRoute.self) { ... }        // ✓ Added
        .navigationDestination(for: OnboardingRoute.self) { ... }   // ✓ Added
        .navigationDestination(for: ReferralRoute.self) { ... }     // ✓ Added
        .navigationDestination(for: FunctionCallRoute.self) { ... } // ✓ Added
        .navigationDestination(for: SettingsRoute.self) { ... }     // ✓ Added
}
```

---

## Key Issues & Solutions

### Issue 1: Binding Parameters
**Problem:** Routes can't pass `@Binding` parameters through NavigationPath.
**Solution:** Create wrapper views that own the state:
```swift
private struct ReferralVaultSelectionWrapper: View {
    @State private var selectedVault: Vault?
    var body: some View {
        ReferralVaultSelectionScreen(selectedVault: $selectedVault)
    }
}
```

### Issue 2: Route Parameter Mismatches
**Problem:** Initially created route with wrong parameter type (KeyImportInput vs String).
**Solution:** Read actual view signatures before creating routes.

### Issue 3: Updating Existing Route Signatures
**Problem:** KeygenRoute.peerDiscovery didn't have keyImportInput parameter.
**Solution:** Updated route definition, router, and all existing call sites.

---

## Statistics

- **Total Files Migrated:** 35 files
- **Routing Infrastructures Created:** 8 complete flows (+ 3 route extensions)
- **Routes Defined:** ~55 routes across all flows
- **Completion:** ~70% of identified files (35/~50)

---

## Next Steps

1. ✅ ~~Verify Send flow migration status~~ - COMPLETED (4 files)
2. ✅ ~~Migrate Settings flow~~ - COMPLETED (1 file)
3. ✅ ~~Migrate DeFi flow~~ - COMPLETED (1 file)
4. ✅ ~~Migrate Home/Wallet flow~~ - COMPLETED (4 files)
5. Migrate remaining miscellaneous files (~8 files)
6. Final verification: `grep -r "navigationDestination" --include="*.swift" --exclude="ContentView.swift"`
7. Build and test all navigation flows

---

Last Updated: 2025-12-16
