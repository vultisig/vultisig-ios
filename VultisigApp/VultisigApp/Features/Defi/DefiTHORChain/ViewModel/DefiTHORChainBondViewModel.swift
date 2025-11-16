//
//  DefiTHORChainBondViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/10/2025.
//

import Foundation

final class DefiTHORChainBondViewModel: ObservableObject {
    @Published private(set) var vault: Vault
    @Published private(set) var activeBondedNodes: [BondPosition] = []
    @Published private(set) var availableNodes: [BondNode] = []
    @Published private(set) var canUnbond: Bool = false
    
    var hasBondPositions: Bool {
        vault.defiPositions.contains { $0.chain == .thorChain && !$0.bonds.isEmpty }
    }
    
    private let thorchainAPIService = THORChainAPIService()
    
    // TODO: - ADD VULTI NODES
    let vultiNodeAddresses: [String] = []
    
    init(vault: Vault) {
        self.vault = vault
    }
    
    func update(vault: Vault) {
        self.vault = vault
    }
    
    @MainActor
    func refresh() async {
        guard hasBondPositions, let runeCoin = vault.runeCoin else {
            return
        }
        
        activeBondedNodes = vault.bondPositions
                
        do {
            // Fetch network-wide bond info once (APY and next churn date)
            let networkInfo = try await thorchainAPIService.getNetworkBondInfo()
            
            // Fetch bonded nodes for this address
            let bondedNodes = try await thorchainAPIService.getBondedNodes(address: runeCoin.address)
            
            // Keep unbond button enabled if something fails on network call
            let canUnbond = !((try? await thorchainAPIService.getNetwork().vaults_migrating) ?? false)
            
            // Map each bonded node to ActiveBondedNode with metrics
            var activeNodes: [BondPosition] = []
            var bondedNodeAddresses: Set<String> = []
            
            for node in bondedNodes.nodes {
                bondedNodeAddresses.insert(node.address)
                
                do {
                    // Calculate metrics for this node using shared network info
                    let myBondMetrics = try await thorchainAPIService.calculateBondMetrics(
                        nodeAddress: node.address,
                        myBondAddress: runeCoin.address
                    )
                    
                    // Parse node state from API status
                    let nodeState = BondNodeState(fromAPIStatus: myBondMetrics.nodeStatus) ?? .standby
                    
                    // Create BondNode
                    let bondNode = BondNode(
                        coin: runeCoin.toCoinMeta(),
                        address: node.address,
                        state: nodeState
                    )
                    
                    // Create ActiveBondedNode with calculated metrics
                    // Use per-node APY calculated from actual rewards (matching JS implementation)
                    let activeNode = BondPosition(
                        node: bondNode,
                        amount: myBondMetrics.myBond,
                        apy: myBondMetrics.apy,
                        nextReward: myBondMetrics.myAward,
                        nextChurn: networkInfo.nextChurnDate,
                        vault: vault
                    )
                    
                    activeNodes.append(activeNode)
                } catch {
                    print("Error calculating metrics for node \(node.address): \(error)")
                    // Continue with other nodes even if one fails
                    self.canUnbond = true
                }
            }
            
            // Filter available nodes to exclude already bonded nodes
            let availableNodesList = vultiNodeAddresses
                .filter { !bondedNodeAddresses.contains($0) }
                .map { BondNode(coin: runeCoin.toCoinMeta(), address: $0, state: .active) }
            
            // Create local copies to safely pass to MainActor
            let finalActiveNodes = activeNodes
            let finalAvailableNodes = Array(availableNodesList)
            
            savePositions(positions: finalActiveNodes)
            self.activeBondedNodes = finalActiveNodes
            self.availableNodes = finalAvailableNodes            
        } catch {}
    }
}

private extension DefiTHORChainBondViewModel {
    @MainActor
    func savePositions(positions: [BondPosition]) {
        do {
            try DefiPositionsStorageService().upsert(positions)
        } catch {
            print("An error occured while saving staked positions: \(error)")
        }
    }
}
