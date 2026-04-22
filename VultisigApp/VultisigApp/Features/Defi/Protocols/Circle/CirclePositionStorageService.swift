//
//  CirclePositionStorageService.swift
//  VultisigApp
//

import Foundation
import SwiftData

struct CirclePositionStorageService {
    @MainActor
    func upsert(usdcBalance: Decimal, ethBalance: Decimal, for vault: Vault) throws {
        if let existing = vault.circlePosition {
            existing.usdcBalance = usdcBalance
            existing.ethBalance = ethBalance
            existing.lastUpdated = .now
        } else {
            let position = CirclePosition(
                usdcBalance: usdcBalance,
                ethBalance: ethBalance,
                vault: vault
            )
            Storage.shared.insert(position)
        }
        try Storage.shared.save()
    }
}
