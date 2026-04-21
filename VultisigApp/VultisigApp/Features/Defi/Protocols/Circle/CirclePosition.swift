//
//  CirclePosition.swift
//  VultisigApp
//

import Foundation
import SwiftData

@Model
final class CirclePosition {
    @Attribute(.unique) var id: String

    var usdcBalance: Decimal
    var ethBalance: Decimal
    var lastUpdated: Date

    @Relationship(inverse: \Vault.circlePosition) var vault: Vault?

    init(
        usdcBalance: Decimal,
        ethBalance: Decimal,
        vault: Vault
    ) {
        self.usdcBalance = usdcBalance
        self.ethBalance = ethBalance
        self.lastUpdated = .now
        self.vault = vault
        self.id = "circle_\(vault.pubKeyECDSA)"
    }
}
