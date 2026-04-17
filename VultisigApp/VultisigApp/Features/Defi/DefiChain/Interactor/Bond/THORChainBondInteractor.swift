//
//  THORChainBondInteractor.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/11/2025.
//

import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "thorchain-bond-interactor")

struct THORChainBondInteractor: BondInteractor {
    private let thorchainAPIService = THORChainAPIService()

    let vultiNodeAddresses: [String] = []

    func fetchBondPositions(vault: Vault) async -> (active: [BondPosition], available: [BondNode]) {
        guard let runeCoin = vault.runeCoin else {
            return ([], [])
        }
        do {
            let networkInfo = try await thorchainAPIService.getNetworkBondInfo()
            let bondedNodes = try await thorchainAPIService.getBondedNodes(address: runeCoin.address)

            // Parallelize per-node metric calculations
            let activeNodes: [BondPosition] = await withTaskGroup(of: BondPosition?.self) { group in
                for node in bondedNodes.nodes {
                    group.addTask {
                        do {
                            let myBondMetrics = try await thorchainAPIService.calculateBondMetrics(
                                nodeAddress: node.address,
                                myBondAddress: runeCoin.address
                            )
                            let nodeState = BondNodeState(fromAPIStatus: myBondMetrics.nodeStatus) ?? .standby
                            let bondNode = BondNode(
                                coin: runeCoin.toCoinMeta(),
                                address: node.address,
                                state: nodeState
                            )
                            return BondPosition(
                                node: bondNode,
                                amount: myBondMetrics.myBond,
                                apy: myBondMetrics.apy,
                                nextReward: myBondMetrics.myAward,
                                nextChurn: networkInfo.nextChurnDate,
                                vault: vault
                            )
                        } catch {
                            logger.error("Error calculating metrics for node \(node.address): \(error)")
                            return nil
                        }
                    }
                }

                var results: [BondPosition] = []
                for await result in group {
                    if let position = result {
                        results.append(position)
                    }
                }
                return results
            }

            let bondedNodeAddresses = Set(bondedNodes.nodes.map(\.address))
            let availableNodesList = vultiNodeAddresses
                .filter { !bondedNodeAddresses.contains($0) }
                .map { BondNode(coin: runeCoin.toCoinMeta(), address: $0, state: .active) }

            let finalActiveNodes = activeNodes
            let finalAvailableNodes = Array(availableNodesList)

            // Only persist when we have data — avoid wiping stored positions on transient failures
            if !finalActiveNodes.isEmpty || bondedNodes.nodes.isEmpty {
                await savePositions(positions: finalActiveNodes, vault: vault)
            }

            return (finalActiveNodes, finalAvailableNodes)
        } catch {
            logger.error("Error fetching bond positions: \(error)")
            return ([], [])
        }
    }

    func canUnbond() async -> Bool {
        guard let network = try? await thorchainAPIService.getNetwork() else {
            return false
        }
        return !network.vaults_migrating
    }

    // swiftlint:disable:next async_without_await
    func canAddBond(vault _: Vault) async -> Bool {
        return true
    }
}

private extension THORChainBondInteractor {
    @MainActor
    func savePositions(positions: [BondPosition], vault: Vault) {
        do {
            try DefiPositionsStorageService().upsert(positions, for: vault)
        } catch {
            logger.error("An error occurred while saving bond positions: \(error)")
        }
    }
}
