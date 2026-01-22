//
//  OnboardingRouter.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 15/12/2025.
//

import SwiftUI

struct OnboardingRouter {
    private let viewBuilder = OnboardingRouteBuilder()

    @ViewBuilder
    func build(_ route: OnboardingRoute) -> some View {
        switch route {
        case .vaultSetup(let tssType, let keyImportInput):
            viewBuilder.buildVaultSetupScreen(tssType: tssType, keyImportInput: keyImportInput)
        case .importSeedphrase:
            viewBuilder.buildImportSeedphraseScreen()
        case .chainsSetup(let mnemonic):
            viewBuilder.buildChainsSetupScreen(mnemonic: mnemonic)
        case .keyImportNewVaultSetup(let vault, let keyImportInput, let fastSignConfig):
            viewBuilder.buildKeyImportNewVaultSetupScreen(
                vault: vault,
                keyImportInput: keyImportInput,
                fastSignConfig: fastSignConfig
            )
        case .keyImportOnboarding:
            viewBuilder.buildKeyImportOnboardingScreen()
        case .importVaultShare:
            viewBuilder.buildImportVaultShareScreen()
        case .setupQRCode(let tssType, let vault):
            viewBuilder.buildSetupQRCodeScreen(tssType: tssType, vault: vault)
        case .joinKeygen(let vault, let selectedVault):
            viewBuilder.buildJoinKeygenScreen(vault: vault, selectedVault: selectedVault)
        case .onboarding:
            viewBuilder.buildOnboardingScreen()
        case .newWalletName(let tssType, let selectedTab, let vault):
            viewBuilder.buildNewWalletNameScreen(
                tssType: tssType,
                selectedTab: selectedTab,
                vault: vault
            )
        }
    }
}
