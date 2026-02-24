//
//  OnboardingRouteBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 15/12/2025.
//

import SwiftUI

struct OnboardingRouteBuilder {

    @ViewBuilder
    func buildVaultSetupScreen(tssType: TssType, keyImportInput: KeyImportInput?, setupType: KeyImportSetupType?) -> some View {
        VaultSetupScreen(tssType: tssType, keyImportInput: keyImportInput, setupType: setupType)
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
    func buildOnboardingDevicesSelectionScreen(tssType: TssType, keyImportInput: KeyImportInput?) -> some View {
        OnboardingDevicesSelectionScreen(tssType: tssType, keyImportInput: keyImportInput)
    }

    @ViewBuilder
    func buildOnboardingVaultSetupInformationScreen(
        tssType: TssType,
        keyImportInput: KeyImportInput?,
        setupType: KeyImportSetupType
    ) -> some View {
        OnboardingYourVaultSetupScreen(
            tssType: tssType,
            keyImportInput: keyImportInput,
            setupType: setupType
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
    func buildJoinKeygenScreen(vault: Vault, selectedVault: Vault?) -> some View {
        JoinKeygenView(vault: vault, selectedVault: selectedVault)
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
            PeerDiscoveryScreen(
                tssType: tssType,
                vault: vault,
                selectedTab: selectedTab,
                fastSignConfig: nil
            )
        }
    }
}
