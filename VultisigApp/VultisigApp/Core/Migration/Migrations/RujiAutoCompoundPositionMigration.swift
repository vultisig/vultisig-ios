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
/// position picker. Adding the coin is enough on its own: the card only
/// materialises once the vault actually holds the receipt, because the
/// interactor skips positions whose coin is absent from the vault.
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
