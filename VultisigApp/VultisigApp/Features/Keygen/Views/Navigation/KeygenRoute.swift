//
//  KeygenRoute.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 15/12/2025.
//

import Foundation

enum KeygenRoute: Hashable {
    case backupNow(tssType: TssType, backupType: VaultBackupType, isNewVault: Bool)
    case keyImportOverview(tssType: TssType, vault: Vault, email: String?, keyImportInput: KeyImportInput?, setupType: KeyImportSetupType)
    /// Pre-keygen explainer for the QBTC quantum-security flow. "Get
    /// started" forwards to `fastVaultPassword` or `peerDiscovery` with
    /// `singleKeygenType: .MLDSA`; completion fires via
    /// `Notification.Name.qbtcQuantumKeygenCompleted`.
    case quantumSecurityIntro(vault: Vault)
    case peerDiscovery(
        tssType: TssType,
        vault: Vault,
        selectedTab: SetupVaultState,
        fastSignConfig: FastSignConfig?,
        keyImportInput: KeyImportInput?,
        setupType: KeyImportSetupType?,
        singleKeygenType: SingleKeygenType?
    )
    case fastVaultPassword(
        tssType: TssType,
        vault: Vault,
        selectedTab: SetupVaultState,
        isExistingVault: Bool,
        singleKeygenType: SingleKeygenType?
    )
    case joinKeysign(vault: Vault)
    case macScanner(type: DeeplinkFlowType, sendTx: SendTransaction, selectedVault: Vault?)
    case macAddressScanner(selectedVault: Vault?, resultId: UUID)
    case generalQRImport(type: DeeplinkFlowType, selectedVault: Vault?, sendTx: SendTransaction?)
    case reviewYourVaults(
        vault: Vault,
        tssType: TssType,
        keygenCommittee: [String],
        email: String?,
        keyImportInput: KeyImportInput?,
        isInitiateDevice: Bool
    )
}
