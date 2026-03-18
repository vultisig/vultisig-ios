//
//  ReferralCode.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 2025-08-25.
//

import Foundation
import SwiftData

@Model
final class ReferralCode: ObservableObject {
    @Attribute(.unique) var id: UUID = UUID()
    var code: String = ""
    var createdAt: Date = Date()

    @Relationship(inverse: \Vault.referralCode) var vault: Vault?

    init(code: String, vault: Vault) {
        self.code = code
        self.vault = vault
        self.createdAt = Date()
    }
}
