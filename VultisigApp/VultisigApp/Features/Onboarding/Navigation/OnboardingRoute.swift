//
//  OnboardingRoute.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 15/12/2025.
//

enum OnboardingRoute: Hashable {
    case vaultSetup(tssType: TssType, keyImportInput: KeyImportInput?)
    case importSeedphrase(keyImportInput: KeyImportInput?)
    case chainsSetup(mnemonic: String)
    case keyImportNewVaultSetup(vault: Vault, keyImportInput: KeyImportInput?, fastSignConfig: FastSignConfig)
    case keyImportOnboarding
    case importVaultShare
    case setupQRCode(tssType: TssType, vault: Vault?)
    case joinKeygen(vault: Vault, selectedVault: Vault?)
    case onboarding
    case newWalletName(tssType: TssType, selectedTab: SetupVaultState, vault: Vault)
}
