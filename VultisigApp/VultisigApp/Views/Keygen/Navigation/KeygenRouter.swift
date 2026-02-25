//
//  KeygenRouter.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 15/12/2025.
//

import SwiftUI

struct KeygenRouter {
    private let viewBuilder = KeygenRouteBuilder()

    @ViewBuilder
    func build(_ route: KeygenRoute) -> some View {
        switch route {
        case .backupNow(let tssType, let backupType, let isNewVault):
            viewBuilder.buildBackupNowScreen(
                tssType: tssType,
                backupType: backupType,
                isNewVault: isNewVault
            )
        case .keyImportOverview(let tssType, let vault, let email, let keyImportInput, let setupType):
            viewBuilder.buildKeyImportOverviewScreen(
                tssType: tssType,
                vault: vault,
                email: email,
                keyImportInput: keyImportInput,
                setupType: setupType
            )
        case .peerDiscovery(let tssType, let vault, let selectedTab, let fastSignConfig, let keyImportInput, let setupType):
            viewBuilder.buildPeerDiscoveryScreen(
                tssType: tssType,
                vault: vault,
                selectedTab: selectedTab,
                fastSignConfig: fastSignConfig,
                keyImportInput: keyImportInput,
                setupType: setupType
            )
        case .fastVaultEmail(let tssType, let vault, let selectedTab, let fastVaultExist):
            viewBuilder.buildFastVaultEmailScreen(
                tssType: tssType,
                vault: vault,
                selectedTab: selectedTab,
                fastVaultExist: fastVaultExist
            )
        case .fastVaultSetHint(let tssType, let vault, let selectedTab, let fastVaultEmail, let fastVaultPassword, let fastVaultExist):
            viewBuilder.buildFastVaultSetHintScreen(
                tssType: tssType,
                vault: vault,
                selectedTab: selectedTab,
                fastVaultEmail: fastVaultEmail,
                fastVaultPassword: fastVaultPassword,
                fastVaultExist: fastVaultExist
            )
        case .fastVaultSetPassword(let tssType, let vault, let selectedTab, let fastVaultEmail, let fastVaultExist):
            viewBuilder.buildFastVaultSetPasswordScreen(
                tssType: tssType,
                vault: vault,
                selectedTab: selectedTab,
                fastVaultEmail: fastVaultEmail,
                fastVaultExist: fastVaultExist
            )
        case .joinKeysign(let vault):
            viewBuilder.buildJoinKeysignScreen(vault: vault)
        case .macScanner(let type, let sendTx, let selectedVault):
            viewBuilder.buildMacScannerScreen(
                type: type,
                sendTx: sendTx,
                selectedVault: selectedVault
            )
        case .macAddressScanner(let selectedVault, let resultId):
            viewBuilder.buildMacAddressScannerScreen(
                selectedVault: selectedVault,
                resultId: resultId
            )
        case .generalQRImport(let type, let selectedVault, let sendTx):
            viewBuilder.buildGeneralQRImportScreen(
                type: type,
                selectedVault: selectedVault,
                sendTx: sendTx
            )
        case .reviewYourVaults(let vault, let tssType, let keygenCommittee, let email, let keyImportInput, let isInitiateDevice):
            viewBuilder.buildReviewYourVaultsScreen(
                vault: vault,
                tssType: tssType,
                keygenCommittee: keygenCommittee,
                email: email,
                keyImportInput: keyImportInput,
                isInitiateDevice: isInitiateDevice
            )
        }
    }
}
