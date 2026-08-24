//
//  TonGramDefiPositionsMigration.swift
//  VultisigApp
//

import SwiftData

/// Extends the Toncoin → Gram rebrand to the persisted DeFi position records.
///
/// The first rebrand migration rewrote `vault.coins`, but a `CoinMeta` is stored
/// in two further places that outlive it: `DefiPositions.bonds/staking/lps` (the
/// per-vault position opt-in, read back by the position picker) and
/// `StakePosition.coin`/`.rewardCoin` (what the staked card paints). Neither is
/// refreshed on load — the position upsert keys existing rows by `CoinMeta` and
/// `StakePosition.apply(_:)` never rewrites the stored meta — so a vault that
/// selected its TON staking position before the rebrand keeps showing "TON"
/// indefinitely.
///
/// Display-only, like the rebrand itself: only `ticker` and `logo` change, and
/// every identifying field (chain, contract address, decimals, price provider)
/// is preserved. In particular `StakePosition.id` is derived from
/// `coin.chain.ticker` — the chain's protocol identifier, still "TON" — so no
/// unique key moves and no row is merged or orphaned.
struct TonGramDefiPositionsMigration: @MainActor AppMigration {
    /// Surfaced when the store cannot be read. Throwing leaves the migration
    /// version un-bumped so `AppMigrationService` retries on the next launch
    /// rather than marking the rebrand as done with no data.
    private enum MigrationError: Error {
        case missingModelContext
    }

    let version: Int = 4

    let description: String = "Rebranding persisted TON DeFi positions to GRAM (ticker + logo)"

    @MainActor
    func migrate() throws {
        guard let modelContext = Storage.shared.modelContext else {
            throw MigrationError.missingModelContext
        }

        var descriptor = FetchDescriptor<Vault>()
        descriptor.relationshipKeyPathsForPrefetching = [\.defiPositions, \.stakePositions]

        for vault in try modelContext.fetch(descriptor) {
            for positions in vault.defiPositions {
                if let bonds = Self.rebranded(positions.bonds) {
                    positions.bonds = bonds
                }
                if let staking = Self.rebranded(positions.staking) {
                    positions.staking = staking
                }
                if let lps = Self.rebranded(positions.lps) {
                    positions.lps = lps
                }
            }

            for position in vault.stakePositions {
                if let coin = Self.rebranded(position.coin) {
                    position.coin = coin
                }
                if let rewardCoin = position.rewardCoin, let rebranded = Self.rebranded(rewardCoin) {
                    position.rewardCoin = rebranded
                }
            }
        }

        try Storage.shared.save()
    }

    /// The rebranded meta, or `nil` when `meta` is not a pre-rebrand native TON
    /// and must be left exactly as it is. Matching on the *pre*-rebrand ticker is
    /// what makes the migration idempotent: after one pass nothing matches, so a
    /// re-run writes nothing.
    private static func rebranded(_ meta: CoinMeta) -> CoinMeta? {
        guard meta.chain == .ton, meta.isNativeToken, meta.ticker == "TON" else {
            return nil
        }
        return CoinMeta(
            chain: meta.chain,
            ticker: "GRAM",
            logo: "ton",
            decimals: meta.decimals,
            priceProviderId: meta.priceProviderId,
            contractAddress: meta.contractAddress,
            isNativeToken: meta.isNativeToken
        )
    }

    /// The array with every pre-rebrand native TON entry rewritten, or `nil` when
    /// none matched — so a vault with no TON position is never marked dirty.
    private static func rebranded(_ metas: [CoinMeta]) -> [CoinMeta]? {
        guard metas.contains(where: { rebranded($0) != nil }) else { return nil }
        return metas.map { rebranded($0) ?? $0 }
    }
}
