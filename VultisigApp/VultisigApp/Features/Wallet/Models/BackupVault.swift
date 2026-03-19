//
//  BackupVault.swift
//  VultisigApp
//
//  Created by Johnny Luo on 17/4/2024.
//

import Foundation

enum VaultVersion: String, Codable {
    case v1
}

struct BackupVault: Codable {
    let version: VaultVersion
    let vault: Vault
}
