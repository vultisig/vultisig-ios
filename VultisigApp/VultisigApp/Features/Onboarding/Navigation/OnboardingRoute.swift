//
//  OnboardingRoute.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 15/12/2025.
//

enum OnboardingRoute: Hashable {
    case importSeedphrase(keyImportInput: KeyImportInput?)
    case keyImportOnboarding
    case chainsSetup(mnemonic: String)
    case devicesSelection(tssType: TssType, keyImportInput: KeyImportInput?)
    case vaultSetupInformation(tssType: TssType, keyImportInput: KeyImportInput?, setupType: KeyImportSetupType)
    case vaultSetup(tssType: TssType, keyImportInput: KeyImportInput?, setupType: KeyImportSetupType? = nil)

    case importVaultShare
    case joinKeygen(vault: Vault, selectedVault: Vault?)
    case newWalletName(tssType: TssType, selectedTab: SetupVaultState, vault: Vault)
}
