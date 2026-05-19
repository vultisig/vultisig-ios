//
//  KeygenRouteBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 15/12/2025.
//

import SwiftUI

struct KeygenRouteBuilder {

    @ViewBuilder
    func buildBackupNowScreen(
        tssType: TssType,
        backupType: VaultBackupType,
        isNewVault: Bool
    ) -> some View {
        VaultBackupScreen(
            tssType: tssType,
            backupType: backupType,
            isNewVault: isNewVault
        )
    }

    @ViewBuilder
    func buildKeyImportOverviewScreen(
        tssType: TssType,
        vault: Vault,
        email: String?,
        keyImportInput: KeyImportInput?,
        setupType: KeyImportSetupType
    ) -> some View {
        OnboardingOverviewScreen(
            tssType: tssType,
            vault: vault,
            email: email,
            keyImportInput: keyImportInput,
            setupType: setupType
        )
    }

    @ViewBuilder
    func buildPeerDiscoveryScreen(
        tssType: TssType,
        vault: Vault,
        selectedTab: SetupVaultState,
        fastSignConfig: FastSignConfig?,
        keyImportInput: KeyImportInput?,
        setupType: KeyImportSetupType?,
        singleKeygenType: SingleKeygenType?
    ) -> some View {
        PeerDiscoveryScreen(
            tssType: tssType,
            vault: vault,
            selectedTab: selectedTab,
            fastSignConfig: fastSignConfig,
            keyImportInput: keyImportInput,
            setupType: setupType,
            singleKeygenType: singleKeygenType
        )
    }

    @ViewBuilder
    func buildFastVaultPasswordScreen(
        tssType: TssType,
        vault: Vault,
        selectedTab: SetupVaultState,
        isExistingVault: Bool,
        singleKeygenType: SingleKeygenType?
    ) -> some View {
        FastVaultPasswordScreen(
            tssType: tssType,
            vault: vault,
            selectedTab: selectedTab,
            isExistingVault: isExistingVault,
            singleKeygenType: singleKeygenType
        )
    }

    @ViewBuilder
    func buildJoinKeysignScreen(vault: Vault) -> some View {
        JoinKeysignView(vault: vault)
    }

    @ViewBuilder
    func buildMacScannerScreen(
        type: DeeplinkFlowType,
        selectedVault: Vault?
    ) -> some View {
        #if os(macOS)
        MacScannerView(
            type: type,
            selectedVault: selectedVault
        )
        #else
        EmptyView()
        #endif
    }

    @ViewBuilder
    func buildMacAddressScannerScreen(
        selectedVault: Vault?,
        resultId: UUID
    ) -> some View {
        #if os(macOS)
        MacAddressScannerView(
            selectedVault: selectedVault,
            scannedResult: ScannerResultManager.shared.getBinding(for: resultId)
        )
        #else
        EmptyView()
        #endif
    }

    @ViewBuilder
    func buildGeneralQRImportScreen(
        type: DeeplinkFlowType,
        selectedVault: Vault?
    ) -> some View {
        GeneralQRImportMacView(
            type: type,
            selectedVault: selectedVault
        ) { _ in
            // Deeplink prefill is handled by HomeScreen via DeeplinkViewModel
            // (`handleSendDeeplinkAfterVaultSelection` / `processAddressOnlyDeeplink`),
            // which now plumb prefill onto `VaultAction.send` instead of mutating
            // a shared FunctionCallForm instance.
        }
    }

    @ViewBuilder
    func buildReviewYourVaultsScreen(
        vault: Vault,
        tssType: TssType,
        keygenCommittee: [String],
        email: String?,
        keyImportInput: KeyImportInput?,
        isInitiateDevice: Bool
    ) -> some View {
        ReviewYourVaultsScreen(
            vault: vault,
            tssType: tssType,
            keygenCommittee: keygenCommittee,
            email: email,
            keyImportInput: keyImportInput,
            isInitiateDevice: isInitiateDevice
        )
    }
}
