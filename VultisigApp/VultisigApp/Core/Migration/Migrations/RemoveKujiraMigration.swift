//
//  RemoveKujiraMigration.swift
//  VultisigApp
//

import SwiftData

/// Removes persisted operational state for the retired Kujira chain.
///
/// `Chain.kujira` remains a compatibility-only identity so historical vault
/// JSON and SwiftData rows can still decode before this migration runs. The
/// migration deliberately matches on the chain identity rather than ticker:
/// KUJI/RKUJI assets on THORChain and the RUJI merge flow remain valid.
struct RemoveKujiraMigration: @MainActor AppMigration {
    // ponytail: parametrised so retiring another chain (Blast) reuses the same cleanup.
    var chain: Chain = .kujira
    private enum MigrationError: Error {
        case missingModelContext
    }

    var version: Int = 6
    var description: String { "Removing persisted state for the retired \(chain.rawValue) chain" }

    @MainActor
    func migrate() throws {
        guard let modelContext = Storage.shared.modelContext else {
            throw MigrationError.missingModelContext
        }

        var vaultDescriptor = FetchDescriptor<Vault>()
        vaultDescriptor.relationshipKeyPathsForPrefetching = [
            \.coins,
            \.hiddenTokens,
            \.defiPositions,
            \.bondPositions,
            \.stakePositions,
            \.lpPositions
        ]

        for vault in try modelContext.fetch(vaultDescriptor) {
            vault.defiChains.removeAll { $0 == chain }

            remove(vault.coins.filter { $0.chain == chain }, from: &vault.coins, context: modelContext)
            remove(
                vault.hiddenTokens.filter { $0.chain.caseInsensitiveCompare(chain.rawValue) == .orderedSame },
                from: &vault.hiddenTokens,
                context: modelContext
            )

            for positions in vault.defiPositions where positions.chain != chain {
                positions.bonds.removeAll { $0.chain == chain }
                positions.staking.removeAll { $0.chain == chain }
                positions.lps.removeAll { $0.chain == chain }
            }
            remove(
                vault.defiPositions.filter { $0.chain == chain },
                from: &vault.defiPositions,
                context: modelContext
            )

            remove(
                vault.bondPositions.filter { $0.node.coin.chain == chain },
                from: &vault.bondPositions,
                context: modelContext
            )
            remove(
                vault.stakePositions.filter {
                    $0.coin.chain == chain || $0.rewardCoin?.chain == chain
                },
                from: &vault.stakePositions,
                context: modelContext
            )
            remove(
                vault.lpPositions.filter {
                    $0.coin1.chain == chain || $0.coin2.chain == chain
                },
                from: &vault.lpPositions,
                context: modelContext
            )
        }

        for pending in try modelContext.fetch(FetchDescriptor<StoredPendingTransaction>())
        where pending.chain == chain {
            modelContext.delete(pending)
        }

        for override in try modelContext.fetch(FetchDescriptor<CustomRPCOverride>())
        where override.chainRaw.caseInsensitiveCompare(chain.rawValue) == .orderedSame {
            modelContext.delete(override)
        }

        try Storage.shared.save()
    }

    private func remove<Model: PersistentModel>(
        _ removed: [Model],
        from models: inout [Model],
        context: ModelContext
    ) {
        guard !removed.isEmpty else { return }
        let removedIDs = Set(removed.map(\.persistentModelID))
        models.removeAll { removedIDs.contains($0.persistentModelID) }
        for model in removed {
            context.delete(model)
        }
    }
}
