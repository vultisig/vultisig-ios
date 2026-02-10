//
//  OnboardingRoute.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 15/12/2025.
//

enum OnboardingRoute: Hashable {
    case onboarding
    case vaultSetup(tssType: TssType, keyImportInput: KeyImportInput?, setupType: KeyImportSetupType? = nil)

    case importSeedphrase(keyImportInput: KeyImportInput?)
    case keyImportOnboarding
    case chainsSetup(mnemonic: String)
    case devicesSelection(tssType: TssType, keyImportInput: KeyImportInput?)
    case keyImportNewVaultSetup(vault: Vault, keyImportInput: KeyImportInput?, fastSignConfig: FastSignConfig?, setupType: KeyImportSetupType)

    case importVaultShare
    case joinKeygen(vault: Vault, selectedVault: Vault?)
    case newWalletName(tssType: TssType, selectedTab: SetupVaultState, vault: Vault)
}
