//
//  OnboardingRouteBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 15/12/2025.
//

import SwiftUI

struct OnboardingRouteBuilder {

    @ViewBuilder
    func buildVaultSetupScreen(tssType: TssType, keyImportInput: KeyImportInput?) -> some View {
        VaultSetupScreen(tssType: tssType, keyImportInput: keyImportInput)
    }

    @ViewBuilder
    func buildImportSeedphraseScreen() -> some View {
        ImportSeedphraseScreen()
    }

    @ViewBuilder
    func buildChainsSetupScreen(mnemonic: String) -> some View {
        KeyImportChainsSetupScreen(mnemonic: mnemonic)
    }

    @ViewBuilder
    func buildKeyImportNewVaultSetupScreen(
        vault: Vault,
        keyImportInput: KeyImportInput?,
        fastSignConfig: FastSignConfig
    ) -> some View {
        KeyImportNewVaultSetupScreen(
            vault: vault,
            keyImportInput: keyImportInput,
            fastSignConfig: fastSignConfig
        )
    }

    @ViewBuilder
    func buildKeyImportOnboardingScreen() -> some View {
        KeyImportOnboardingScreen()
    }

    @ViewBuilder
    func buildImportVaultShareScreen() -> some View {
        ImportVaultShareScreen()
    }

    @ViewBuilder
    func buildSetupQRCodeScreen(tssType: TssType, vault: Vault?) -> some View {
        SetupQRCodeView(tssType: tssType, vault: vault)
    }

    @ViewBuilder
    func buildJoinKeygenScreen(vault: Vault, selectedVault: Vault?) -> some View {
        JoinKeygenView(vault: vault, selectedVault: selectedVault)
    }

    @ViewBuilder
    func buildOnboardingScreen() -> some View {
        OnboardingView()
    }

    @ViewBuilder
    func buildNewWalletNameScreen(
        tssType: TssType,
        selectedTab: SetupVaultState,
        vault: Vault
    ) -> some View {
        if selectedTab.isFastVault {
            FastVaultEmailView(
                tssType: tssType,
                vault: vault,
                selectedTab: selectedTab
            )
        } else {
            PeerDiscoveryView(
                tssType: tssType,
                vault: vault,
                selectedTab: selectedTab,
                fastSignConfig: nil
            )
        }
    }
}
