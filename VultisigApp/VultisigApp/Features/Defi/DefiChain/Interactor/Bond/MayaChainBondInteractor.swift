//
//  MayaChainBondInteractor.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 23/11/2025.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "mayachain-bond-interactor")

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
        guard let cacaoCoin = vault.coins.first(where: { $0.chain == .mayaChain && $0.isNativeToken }) else {
            return ([], [])
        }

        let networkInfo = try await mayaChainAPIService.getNetworkBondInfo()
        let bondedNodes = try await mayaChainAPIService.getBondedNodes(address: cacaoCoin.address)

        let cacaoAddress = cacaoCoin.address
        let cacaoCoinMeta = cacaoCoin.toCoinMeta()
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
    func canAddBond(vault _: Vault) async -> Bool {
        return true
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
