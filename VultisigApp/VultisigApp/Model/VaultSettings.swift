//
//  VaultSettings.swift
//  VultisigApp
//

import Foundation
import SwiftData

@Model
final class VaultSettings {
    var notificationsEnabled: Bool = false
    var notificationsPrompted: Bool = false

    @Relationship(inverse: \Vault.settings) var vault: Vault?

    init(vault: Vault) {
        self.vault = vault
    }
}
