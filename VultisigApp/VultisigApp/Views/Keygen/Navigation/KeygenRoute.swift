//
//  KeygenRoute.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 15/12/2025.
//

enum KeygenRoute: Hashable {
    case fastBackupOverview(tssType: TssType, vault: Vault, email: String)
    case secureBackupOverview(vault: Vault)
    case backupNow(tssType: TssType, backupType: BackupType, isNewVault: Bool)
    case keyImportOverview(vault: Vault, email: String?, keyImportInput: KeyImportInput?)
    case peerDiscovery(tssType: TssType, vault: Vault?, selectedTab: SetupVaultState?, fastSignConfig: FastSignConfig?, keyImportInput: KeyImportInput?)
    case fastVaultSetHint(tssType: TssType, vault: Vault?, selectedTab: SetupVaultState, fastVaultEmail: String, fastVaultPassword: String, fastVaultExist: Bool)
    case fastVaultSetPassword(tssType: TssType, vault: Vault?, selectedTab: SetupVaultState, fastVaultEmail: String, fastVaultExist: Bool)
    case newWalletName(tssType: TssType, selectedTab: SetupVaultState, name: String)
}
