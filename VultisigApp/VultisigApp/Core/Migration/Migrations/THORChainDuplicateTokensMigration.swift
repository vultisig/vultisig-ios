//
//  THORChainDuplicateTokensMigration.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 27/11/2025.
//

import SwiftData

struct THORChainDuplicateTokensMigration: @MainActor AppMigration {
    let version: Int = 0

    let description: String = "Removing duplicate THORChain-like native tokens"

    @MainActor
    func migrate() throws {
        guard let modelContext = Storage.shared.modelContext else { return }

        var fetchVaultDescriptor = FetchDescriptor<Vault>()
        fetchVaultDescriptor.relationshipKeyPathsForPrefetching = [\.coins]

        let vaults = try modelContext.fetch(fetchVaultDescriptor)

        for vault in vaults {
            if let runeCoin = vault.runeCoin {
                removeAllNonNative(vault: vault, ticker: runeCoin.ticker)
            }

            if let mayaCoin = vault.nativeCoin(for: .mayaChain) {
                removeAllNonNative(vault: vault, ticker: mayaCoin.ticker)
            }
        }

        try Storage.shared.save()
    }

    private func removeAllNonNative(vault: Vault, ticker: String) {
        vault.coins.removeAll { $0.ticker == ticker && !$0.isNativeToken }
    }
}
