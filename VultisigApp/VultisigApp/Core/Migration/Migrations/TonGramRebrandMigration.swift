//
//  TonGramRebrandMigration.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 22/06/2026.
//

import SwiftData

/// Rebrands the persisted native TON coin to GRAM (ticker + logo) for existing
/// installs. New coins already get GRAM from `TokensStore`, but `Coin.ticker`
/// and `Coin.logo` are stored values that are never refreshed for coins already
/// in a vault, so without this migration existing holders keep seeing "TON".
/// The chain identity, address, balance and `priceProviderId` are untouched —
/// this is the display-only Toncoin → Gram rebrand.
struct TonGramRebrandMigration: @MainActor AppMigration {
    let version: Int = 1

    let description: String = "Rebranding native TON token to GRAM (ticker + logo)"

    @MainActor
    func migrate() throws {
        let modelContext = Storage.shared.modelContext

        var fetchVaultDescriptor = FetchDescriptor<Vault>()
        fetchVaultDescriptor.relationshipKeyPathsForPrefetching = [\.coins]

        guard let vaults = try modelContext?.fetch(fetchVaultDescriptor) else {
            return
        }

        for vault in vaults {
            for coin in vault.coins where coin.chain == .ton && coin.isNativeToken && coin.ticker == "TON" {
                coin.ticker = "GRAM"
                coin.logo = "gram"
            }
        }

        try Storage.shared.save()
    }
}
