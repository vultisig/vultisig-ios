//
//  MayaChainBondInteractor.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 23/11/2025.
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

struct MayaChainBondInteractor: BondInteractor {
    private let mayaChainAPIService = MayaChainAPIService()

    let vultiNodeAddresses: [String] = []

    func fetchBondPositions(vault: Vault) async throws -> (active: [BondPosition], available: [BondNode]) {
        guard let bondCoin = await bondCoinSnapshot(in: vault) else {
            return ([], [])
        }

        let networkInfo = try await mayaChainAPIService.getNetworkBondInfo()
        let bondedNodes = try await mayaChainAPIService.getBondedNodes(address: bondCoin.address)

        let cacaoAddress = bondCoin.address
        let cacaoCoinMeta = bondCoin.meta
        let nextChurn = networkInfo.nextChurnDate

        var drafts: [BondPositionDraft] = []
        var bondedNodeAddresses: Set<String> = []

        for node in bondedNodes.nodes {
            bondedNodeAddresses.insert(node.address)

            do {
                let metrics = try await mayaChainAPIService.calculateBondMetrics(
                    nodeAddress: node.address,
                    myBondAddress: cacaoAddress
                )
                let nodeState = BondNodeState(fromAPIStatus: metrics.nodeStatus) ?? .standby
                let bondNode = BondNode(
                    coin: cacaoCoinMeta,
                    address: node.address,
                    state: nodeState
                )
                drafts.append(
                    BondPositionDraft(
                        node: bondNode,
                        amount: metrics.myBond,
                        apy: metrics.apr,
                        nextReward: metrics.myAward,
                        nextChurn: nextChurn
                    )
                )
            } catch {
                logger.error("Error calculating metrics for node \(node.address): \(error)")
            }
        }

        let availableNodes = vultiNodeAddresses
            .filter { !bondedNodeAddresses.contains($0) }
            .map { BondNode(coin: cacaoCoinMeta, address: $0, state: .active) }

        // Only persist when we have data — avoid wiping stored positions on transient failures
        let shouldPersist = !drafts.isEmpty || bondedNodes.nodes.isEmpty

        return await materialize(
            drafts: drafts,
            available: availableNodes,
            vault: vault,
            persist: shouldPersist
        )
    }

    // swiftlint:disable:next async_without_await
    func canUnbond() async -> Bool {
        true
    }

    // swiftlint:disable:next async_without_await
    func canAddBond() async -> Bool {
        return true
    }
}

extension MayaChainBondInteractor {
    /// Reads the CACAO coin on the main actor and reduces it to value types.
    ///
    /// Internal rather than private so the coin selection is unit-testable —
    /// every other member of this file is private because nothing else needs
    /// to be reachable from outside it.
    @MainActor
    func bondCoinSnapshot(in vault: Vault) -> BondCoinSnapshot? {
        guard let cacaoCoin = vault.nativeCoin(for: .mayaChain) else { return nil }
        return BondCoinSnapshot(meta: cacaoCoin.toCoinMeta(), address: cacaoCoin.address)
    }
}

private extension MayaChainBondInteractor {
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
                logger.error("An error occurred while saving bonded positions: \(error)")
            }
        }
        return (active, available)
    }
}
