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
    case devicesSelection(mnemonic: String, chainSettings: [ChainImportSetting])
    case keyImportNewVaultSetup(vault: Vault, keyImportInput: KeyImportInput?, fastSignConfig: FastSignConfig?, setupType: KeyImportSetupType)

    case importVaultShare
    case setupQRCode(tssType: TssType, vault: Vault?)
    case joinKeygen(vault: Vault, selectedVault: Vault?)
    case newWalletName(tssType: TssType, selectedTab: SetupVaultState, vault: Vault)
}
