//
//  DefiTHORChainBondViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/10/2025.
//

import Foundation

final class DefiTHORChainBondViewModel: ObservableObject {
    @Published private(set) var vault: Vault
    @Published private(set) var activeBondedNodes: [ActiveBondedNode] = []
    @Published private(set) var availableNodes: [BondNode] = []
    @Published private(set) var isLoading: Bool = false

    private let thorchainAPIService = THORChainAPIService()
    
    let vultiNodeAddresses: [String] = [
        "thor1fpyaj39rdlc5f80kulq55tqlvku4t66gq5pvqk"
    ]

    init(vault: Vault) {
        self.vault = vault
    }

    func update(vault: Vault) {
        self.vault = vault
    }

    func refresh() async {
        guard let runeCoin = vault.coins.first(where: { $0.isRune }) else {
            return
        }

        await MainActor.run {
            isLoading = true
        }

        // Update balance
        await BalanceService.shared.updateBalance(for: runeCoin)

        do {
            // Fetch bonded nodes for this address
            let bondedNodes = try await thorchainAPIService.getBondedNodes(address: runeCoin.address)

            // Map each bonded node to ActiveBondedNode with metrics
            var activeNodes: [ActiveBondedNode] = []
            var bondedNodeAddresses: Set<String> = []

            for node in bondedNodes.nodes {
                bondedNodeAddresses.insert(node.address)

                do {
                    // Calculate metrics for this node
                    let metrics = try await thorchainAPIService.calculateBondMetrics(
                        nodeAddress: node.address,
                        myBondAddress: runeCoin.address
                    )

                    // Parse node state from API status
                    let nodeState = BondNodeState(fromAPIStatus: metrics.nodeStatus) ?? .standby

                    // Create BondNode
                    let bondNode = BondNode(
                        address: node.address,
                        state: nodeState
                    )

                    // Create ActiveBondedNode with calculated metrics
                    let activeNode = ActiveBondedNode(
                        node: bondNode,
                        amount: metrics.myBond,
                        apy: metrics.apy,
                        nextReward: metrics.myAward,
                        nextChurn: metrics.nextChurnTimestamp
                    )

                    activeNodes.append(activeNode)
                } catch {
                    print("Error calculating metrics for node \(node.address): \(error)")
                    // Continue with other nodes even if one fails
                }
            }

            // Filter available nodes to exclude already bonded nodes, keep 10 only for now
            let availableNodesList = vultiNodeAddresses
                .filter { !bondedNodeAddresses.contains($0) }
                .prefix(10)
                .map { BondNode(address: $0, state: .active) }

            await MainActor.run {
                self.activeBondedNodes = activeNodes
                self.availableNodes = availableNodesList
                self.isLoading = false
            }

        } catch {
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
}
