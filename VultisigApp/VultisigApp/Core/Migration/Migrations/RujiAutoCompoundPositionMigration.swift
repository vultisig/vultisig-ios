//
//  RujiAutoCompoundPositionMigration.swift
//  VultisigApp
//

import SwiftData

/// Opts every vault that already tracks the RUJI staking position into the sRUJI
/// one as well.
///
/// RUJI staking has two independent positions, and they are now two DeFi cards
/// keyed on two coins. Before the split, a vault holding the auto-compounding
/// position saw it under the single "RUJI" toggle — without this, that card
/// would silently vanish until the user found the new "sRUJI" entry in the
/// position picker.
///
/// Widening the position list is all this does; it deliberately does NOT insert
/// the sRUJI coin into `vault.coins` the way the picker's save does. THORChain
/// token discovery already adds `x/staking-x/ruji` for every vault that holds
/// it — which is why the receipt shows in the wallet list today — so the card
/// materialises on its own for exactly the vaults that have a position, and
/// vaults that never auto-compounded gain nothing to render. Writing the coin
/// in would instead put a zero-balance sRUJI row in the wallet list of every
/// RUJI staker.
///
/// Idempotency comes from `AppMigrationService` (Keychain-versioned, runs once)
/// and is reinforced by the contains-check, so a user who deliberately turns
/// sRUJI back off is not overridden.
struct RujiAutoCompoundPositionMigration: @MainActor AppMigration {
    /// Surfaced when the store cannot be read. Throwing leaves the migration
    /// version un-bumped so `AppMigrationService` retries on the next launch
    /// rather than marking the opt-in as done with no data.
    private enum MigrationError: Error {
        case missingModelContext
    }

    let version: Int = 3

    let description: String = "Enabling the sRUJI staking position for vaults that track RUJI"

    @MainActor
    func migrate() throws {
        guard let modelContext = Storage.shared.modelContext else {
            throw MigrationError.missingModelContext
        }

        var descriptor = FetchDescriptor<Vault>()
        descriptor.relationshipKeyPathsForPrefetching = [\.defiPositions]

        for vault in try modelContext.fetch(descriptor) {
            guard let positions = vault.defiPositions.first(where: { $0.chain == .thorChain }) else {
                continue
            }
            // Match on ticker, not on the whole `CoinMeta`: a persisted entry can
            // carry metadata (logo, price provider) that has since changed and
            // would no longer compare equal.
            let tickers = Set(positions.staking.map { $0.ticker.uppercased() })
            guard tickers.contains("RUJI"), !tickers.contains("SRUJI") else { continue }
            positions.staking.append(TokensStore.sruji)
        }

        try Storage.shared.save()
    }
}
