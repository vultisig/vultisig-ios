//
//  THORChainBondInteractor.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/11/2025.
//

import Foundation
import OSLog

private let logger = Log.defi.interactor

private struct BondPositionDraft: Sendable {
    let node: BondNode
    let amount: Decimal
    let apy: Double
    let nextReward: Decimal
    let nextChurn: Date?
}

struct THORChainBondInteractor: BondInteractor {
    private let thorchainAPIService = THORChainAPIService()

    let vultiNodeAddresses: [String] = []

    func fetchBondPositions(vault: Vault) async throws -> (active: [BondPosition], available: [BondNode]) {
        guard let bondCoin = await bondCoinSnapshot(in: vault) else {
            return ([], [])
        }
        let networkInfo = try await thorchainAPIService.getNetworkBondInfo()
        let bondedNodes = try await thorchainAPIService.getBondedNodes(address: bondCoin.address)

        let runeAddress = bondCoin.address
        let runeCoinMeta = bondCoin.meta
        let nextChurn = networkInfo.nextChurnDate

        // Parallelize per-node metric calculations into Sendable drafts —
        // BondPosition is a SwiftData @Model and cannot cross actor boundaries.
        let drafts: [BondPositionDraft] = await withTaskGroup(of: BondPositionDraft?.self) { group in
            for node in bondedNodes.nodes {
                group.addTask {
                    do {
                        let metrics = try await thorchainAPIService.calculateBondMetrics(
                            nodeAddress: node.address,
                            myBondAddress: runeAddress
                        )
                        let nodeState = BondNodeState(fromAPIStatus: metrics.nodeStatus) ?? .standby
                        let bondNode = BondNode(
                            coin: runeCoinMeta,
                            address: node.address,
                            state: nodeState
                        )
                        return BondPositionDraft(
                            node: bondNode,
                            amount: metrics.myBond,
                            apy: metrics.apy,
                            nextReward: metrics.myAward,
                            nextChurn: nextChurn
                        )
                    } catch {
                        logger.error("Error calculating metrics for node \(node.address): \(error)")
                        return nil
                    }
                }
            }

            var results: [BondPositionDraft] = []
            for await result in group {
                if let draft = result {
                    results.append(draft)
                }
            }
            return results
        }

        let bondedNodeAddresses = Set(bondedNodes.nodes.map(\.address))
        let availableNodes = vultiNodeAddresses
            .filter { !bondedNodeAddresses.contains($0) }
            .map { BondNode(coin: runeCoinMeta, address: $0, state: .active) }

        // Only persist when we have data — avoid wiping stored positions on transient failures
        let shouldPersist = !drafts.isEmpty || bondedNodes.nodes.isEmpty

        return await materialize(
            drafts: drafts,
            available: availableNodes,
            vault: vault,
            persist: shouldPersist
        )
    }

    func canUnbond() async -> Bool {
        guard let network = try? await thorchainAPIService.getNetwork() else {
            return false
        }
        return !network.vaults_migrating
    }

    // swiftlint:disable:next async_without_await
    func canAddBond() async -> Bool {
        return true
    }
}

extension THORChainBondInteractor {
    /// Reads the RUNE coin on the main actor and reduces it to value types.
    ///
    /// Internal rather than private so the coin selection is unit-testable —
    /// every other member of this file is private because nothing else needs
    /// to be reachable from outside it.
    @MainActor
    func bondCoinSnapshot(in vault: Vault) -> BondCoinSnapshot? {
        guard let runeCoin = vault.runeCoin else { return nil }
        return BondCoinSnapshot(meta: runeCoin.toCoinMeta(), address: runeCoin.address)
    }
}

private extension THORChainBondInteractor {
    @MainActor
    func materialize(
        drafts: [BondPositionDraft],
        available: [BondNode],
        vault: Vault,
        persist: Bool
    ) -> (active: [BondPosition], available: [BondNode]) {
        let active = drafts.map { draft in
            BondPosition(
                node: draft.node,
                amount: draft.amount,
                apy: draft.apy,
                nextReward: draft.nextReward,
                nextChurn: draft.nextChurn,
                vault: vault
            )
        }
        if persist {
            do {
                try DefiPositionsStorageService().upsert(active, for: vault)
            } catch {
                logger.error("An error occurred while saving bond positions: \(error)")
            }
        }
        return (active, available)
    }
}
