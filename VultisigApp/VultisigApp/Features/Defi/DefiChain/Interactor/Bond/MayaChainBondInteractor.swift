//
//  MayaChainBondInteractor.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 23/11/2025.
//

struct MayaChainBondInteractor: BondInteractor {
    private let mayaChainAPIService = MayaChainAPIService()

    let vultiNodeAddresses: [String] = []

    func fetchBondPositions(vault: Vault) async -> (active: [BondPosition], available: [BondNode]) {
        guard let cacaoCoin = vault.coins.first(where: { $0.chain == .mayaChain && $0.isNativeToken }) else {
            return ([], [])
        }

        do {
            // Fetch network-wide bond info once (APR and next churn date)
            let networkInfo = try await mayaChainAPIService.getNetworkBondInfo()

            // Fetch bonded nodes for this address
            let bondedNodes = try await mayaChainAPIService.getBondedNodes(address: cacaoCoin.address)

            // Map each bonded node to BondPosition with metrics
            var activeNodes: [BondPosition] = []
            var bondedNodeAddresses: Set<String> = []

            for node in bondedNodes.nodes {
                bondedNodeAddresses.insert(node.address)

                do {
                    // Calculate metrics for this node using shared network info
                    let myBondMetrics = try await mayaChainAPIService.calculateBondMetrics(
                        nodeAddress: node.address,
                        myBondAddress: cacaoCoin.address
                    )

                    // Parse node state from API status
                    let nodeState = BondNodeState(fromAPIStatus: myBondMetrics.nodeStatus) ?? .standby

                    // Create BondNode
                    let bondNode = BondNode(
                        coin: cacaoCoin.toCoinMeta(),
                        address: node.address,
                        state: nodeState
                    )

                    // Create BondPosition with calculated metrics
                    let activeNode = BondPosition(
                        node: bondNode,
                        amount: myBondMetrics.myBond,
                        apy: myBondMetrics.apr,
                        nextReward: myBondMetrics.myAward,
                        nextChurn: networkInfo.nextChurnDate,
                        vault: vault
                    )

                    activeNodes.append(activeNode)
                } catch {
                    print("Error calculating metrics for node \(node.address): \(error)")
                    // Continue with other nodes even if one fails
                }
            }

            // Filter available nodes to exclude already bonded nodes
            let availableNodesList = vultiNodeAddresses
                .filter { !bondedNodeAddresses.contains($0) }
                .map { BondNode(coin: cacaoCoin.toCoinMeta(), address: $0, state: .active) }

            // Create local copies to safely pass to MainActor
            let finalActiveNodes = activeNodes
            let finalAvailableNodes = Array(availableNodesList)

            await savePositions(positions: finalActiveNodes, vault: vault)
            return (finalActiveNodes, finalAvailableNodes)
        } catch {
            print("Error fetching Maya bond positions: \(error)")
            return ([], [])
        }
    }

    func canUnbond() -> Bool {
        // Maya allows unbonding when vaults are not migrating
        // For now, return true - can be enhanced with actual migration check if needed
        true
    }
}

private extension MayaChainBondInteractor {
    @MainActor
    func savePositions(positions: [BondPosition], vault: Vault) {
        do {
            try DefiPositionsStorageService().upsert(positions, for: vault)
        } catch {
            print("An error occurred while saving bonded positions: \(error)")
        }
    }
}
