//
//  THORChainBondInteractor.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/11/2025.
//

struct THORChainBondInteractor: BondInteractor {
    private let thorchainAPIService = THORChainAPIService()
    
    let vultiNodeAddresses: [String] = []
    
    func fetchBondPositions(vault: Vault) async -> (active: [BondPosition], available: [BondNode]) {
        guard let runeCoin = vault.runeCoin else {
            return ([], [])
        }
        do {
            // Fetch network-wide bond info once (APY and next churn date)
            let networkInfo = try await thorchainAPIService.getNetworkBondInfo()
            
            // Fetch bonded nodes for this address
            let bondedNodes = try await thorchainAPIService.getBondedNodes(address: runeCoin.address)
                        
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
                }
            }
            
            // Filter available nodes to exclude already bonded nodes
            let availableNodesList = vultiNodeAddresses
                .filter { !bondedNodeAddresses.contains($0) }
                .map { BondNode(coin: runeCoin.toCoinMeta(), address: $0, state: .active) }
            
            // Create local copies to safely pass to MainActor
            let finalActiveNodes = activeNodes
            let finalAvailableNodes = Array(availableNodesList)
            
            await savePositions(positions: finalActiveNodes, vault: vault)
            return (finalActiveNodes, finalAvailableNodes)
        } catch {
            return ([], [])
        }
    }
    
    func canUnbond() async -> Bool {
        guard let network = try? await thorchainAPIService.getNetwork() else {
            return false // Fail-safe: don't allow unbond if can't verify network status
        }
        return !network.vaults_migrating
    }
}

private extension THORChainBondInteractor {
    @MainActor
    func savePositions(positions: [BondPosition], vault: Vault) async {
        do {
            try DefiPositionsStorageService().upsert(positions, for: vault)
        } catch {
            print("An error occured while saving staked positions: \(error)")
        }
    }
}
