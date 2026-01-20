//
//  KeygenRoute.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 15/12/2025.
//

import Foundation

enum KeygenRoute: Hashable {
    case fastBackupOverview(tssType: TssType, vault: Vault, email: String)
    case secureBackupOverview(vault: Vault)
    case backupNow(tssType: TssType, backupType: VaultBackupType, isNewVault: Bool)
    case keyImportOverview(vault: Vault, email: String?, keyImportInput: KeyImportInput?, setupType: KeyImportSetupType)
    case peerDiscovery(tssType: TssType, vault: Vault, selectedTab: SetupVaultState, fastSignConfig: FastSignConfig?, keyImportInput: KeyImportInput?, setupType: KeyImportSetupType?)
    case fastVaultEmail(tssType: TssType, vault: Vault, selectedTab: SetupVaultState, fastVaultExist: Bool)
    case fastVaultSetHint(tssType: TssType, vault: Vault, selectedTab: SetupVaultState, fastVaultEmail: String, fastVaultPassword: String, fastVaultExist: Bool)
    case fastVaultSetPassword(tssType: TssType, vault: Vault, selectedTab: SetupVaultState, fastVaultEmail: String, fastVaultExist: Bool)
    case newWalletName(tssType: TssType, selectedTab: SetupVaultState, name: String)
    case joinKeysign(vault: Vault)
    case macScanner(type: DeeplinkFlowType, sendTx: SendTransaction, selectedVault: Vault?)
    case macAddressScanner(selectedVault: Vault?, resultId: UUID)
    case generalQRImport(type: DeeplinkFlowType, selectedVault: Vault?, sendTx: SendTransaction?)
}
