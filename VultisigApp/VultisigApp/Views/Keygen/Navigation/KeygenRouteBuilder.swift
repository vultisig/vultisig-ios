//
//  KeygenRouteBuilder.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 15/12/2025.
//

import SwiftUI

struct KeygenRouteBuilder {

    @ViewBuilder
    func buildFastBackupOverviewScreen(
        tssType: TssType,
        vault: Vault,
        email: String
    ) -> some View {
        FastBackupVaultOverview(
            tssType: tssType,
            vault: vault,
            email: email
        )
    }

    @ViewBuilder
    func buildSecureBackupOverviewScreen(vault: Vault) -> some View {
        SecureBackupVaultOverview(vault: vault)
    }

    @ViewBuilder
    func buildBackupNowScreen(
        tssType: TssType,
        backupType: VaultBackupType,
        isNewVault: Bool
    ) -> some View {
        VaultBackupNowScreen(
            tssType: tssType,
            backupType: backupType,
            isNewVault: isNewVault
        )
    }

    @ViewBuilder
    func buildKeyImportOverviewScreen(
        vault: Vault,
        email: String?,
        keyImportInput: KeyImportInput?,
        setupType: KeyImportSetupType
    ) -> some View {
        KeyImportOverviewScreen(
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
        keyImportInput: KeyImportInput?
    ) -> some View {
        PeerDiscoveryView(
            tssType: tssType,
            vault: vault,
            selectedTab: selectedTab,
            fastSignConfig: fastSignConfig,
            keyImportInput: keyImportInput
        )
    }

    @ViewBuilder
    func buildFastVaultEmailScreen(
        tssType: TssType,
        vault: Vault,
        selectedTab: SetupVaultState,
        fastVaultExist: Bool
    ) -> some View {
        FastVaultEmailView(
            tssType: tssType,
            vault: vault,
            selectedTab: selectedTab,
            fastVaultExist: fastVaultExist
        )
    }

    @ViewBuilder
    func buildFastVaultSetHintScreen(
        tssType: TssType,
        vault: Vault,
        selectedTab: SetupVaultState,
        fastVaultEmail: String,
        fastVaultPassword: String,
        fastVaultExist: Bool
    ) -> some View {
        FastVaultSetHintView(
            tssType: tssType,
            vault: vault,
            selectedTab: selectedTab,
            fastVaultEmail: fastVaultEmail,
            fastVaultPassword: fastVaultPassword,
            fastVaultExist: fastVaultExist
        )
    }

    @ViewBuilder
    func buildFastVaultSetPasswordScreen(
        tssType: TssType,
        vault: Vault,
        selectedTab: SetupVaultState,
        fastVaultEmail: String,
        fastVaultExist: Bool
    ) -> some View {
        FastVaultSetPasswordView(
            tssType: tssType,
            vault: vault,
            selectedTab: selectedTab,
            fastVaultEmail: fastVaultEmail,
            fastVaultExist: fastVaultExist
        )
    }

    @ViewBuilder
    func buildNewWalletNameScreen(
        tssType: TssType,
        selectedTab: SetupVaultState,
        name: String
    ) -> some View {
        NewWalletNameView(
            tssType: tssType,
            selectedTab: selectedTab,
            name: name
        )
    }

    @ViewBuilder
    func buildJoinKeysignScreen(vault: Vault) -> some View {
        JoinKeysignView(vault: vault)
    }

    @ViewBuilder
    func buildMacScannerScreen(
        type: DeeplinkFlowType,
        sendTx: SendTransaction,
        selectedVault: Vault?
    ) -> some View {
        #if os(macOS)
        MacScannerView(
            type: type,
            sendTx: sendTx,
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
        selectedVault: Vault?,
        sendTx: SendTransaction?
    ) -> some View {
        GeneralQRImportMacView(
            type: type,
            selectedVault: selectedVault
        ) { address in
            sendTx?.toAddress = address
        }
    }
}
