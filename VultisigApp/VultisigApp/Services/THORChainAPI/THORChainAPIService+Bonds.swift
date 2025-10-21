//
//  THORChainAPIService+Bonds.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 21/10/2025.
//

import Foundation

extension THORChainAPIService {
    func getBondedNodes(address: String) async throws -> BondedNodes {
        do {
            let response = try await httpClient.request(THORChainBondsAPI.getBondedNodes(address: address), responseType: BondedNodesResponse.self)
            let nodes: [RuneBondNode] = response.data.nodes.compactMap { node in
                guard let amount = Decimal(string: node.bond) else {
                    return nil
                }

                return RuneBondNode(status: node.status, address: node.address, bond: amount)
            }
            return BondedNodes(totalBonded: Decimal(string: response.data.totalBonded) ?? .zero, nodes: nodes)
        } catch {
            throw THORChainAPIError.invalidResponse
        }
    }

    /// Get detailed node information including bond providers and current award
    func getNodeDetails(nodeAddress: String) async throws -> NodeDetailsResponse {
        let response = try await httpClient.request(
            THORChainBondsAPI.getNodeDetails(nodeAddress: nodeAddress),
            responseType: NodeDetailsResponse.self
        )
        return response.data
    }

    /// Get recent churns history
    func getChurns() async throws -> [ChurnEntry] {
        let response = try await httpClient.request(
            THORChainBondsAPI.getChurns,
            responseType: [ChurnEntry].self
        )
        return response.data
    }

    /// Calculate bond metrics for a specific node and bond address
    func calculateBondMetrics(
        nodeAddress: String,
        myBondAddress: String
    ) async throws -> BondMetrics {
        // 1. Fetch node details
        let nodeData = try await getNodeDetails(nodeAddress: nodeAddress)
        let bondProviders = nodeData.bondProviders.providers

        // 2. Calculate my bond and total bond
        var myBond: Decimal = 0
        var totalBond: Decimal = 0

        for provider in bondProviders {
            let providerBond = Decimal(string: provider.bond) ?? 0
            if provider.bondAddress == myBondAddress {
                myBond = providerBond
            }
            totalBond += providerBond
        }

        // 3. Calculate ownership percentage
        let myBondOwnershipPercentage = totalBond > 0 ? myBond / totalBond : 0

        // 4. Calculate node operator fee (convert from basis points)
        let nodeOperatorFee = (Decimal(string: nodeData.bondProviders.nodeOperatorFee) ?? 0) / 10000

        // 5. Calculate current award after node operator fee
        let currentAward = (Decimal(string: nodeData.currentAward) ?? 0) * (1 - nodeOperatorFee)
        let myAward = myBondOwnershipPercentage * currentAward
        
        let network = try await getNetworkInfo()
        let apy = Double(network.bondingAPY ?? "0") ?? 0

        let nextChurnDate = try await estimateNextChurnETA(network: network)
        
        return BondMetrics(
            myBond: myBond,
            myAward: myAward,
            apy: apy,
            nextChurnDate: nextChurnDate,
            nodeStatus: nodeData.status
        )
    }
    
    func estimateNextChurnETA(network: THORChainNetworkInfo) async throws -> Date? {
        let health = try await getHealth()
        let churns = try await getChurns()

        guard let nextChurnHeight = Int(network.nextChurnHeight ?? "") else { return nil }
        let currentHeight = health.lastThorNode.height
        let currentTimestamp = TimeInterval(health.lastThorNode.timestamp)

        guard nextChurnHeight > currentHeight else { return nil }

        // Derive avg block time from churn history; fall back if unavailable
        let avgBlockTime = averageBlockTimeFromChurns(churns, pairs: 8) ?? 6.0 // seconds per block

        let remainingBlocks = nextChurnHeight - currentHeight
        let etaSeconds = Double(remainingBlocks) * avgBlockTime

        return Date(timeIntervalSince1970: currentTimestamp).addingTimeInterval(etaSeconds)
    }
    
    /// Derive a weighted average block time (seconds) from recent churn pairs.
    /// Uses totalSeconds / totalBlocks across the last `pairs` intervals.
    private func averageBlockTimeFromChurns(_ churns: [ChurnEntry], pairs: Int = 6) -> Double? {
        // Ensure newest → oldest by height (defensive)
        let sorted = churns.sorted {
            (Int($0.height) ?? 0) > (Int($1.height) ?? 0)
        }
        guard sorted.count >= 2 else { return nil }

        var totalSeconds: Double = 0
        var totalBlocks: Int = 0

        // Iterate adjacent pairs (latest with previous)
        for i in 0..<min(pairs, sorted.count - 1) {
            guard
                let hNew = Int(sorted[i].height),
                let hOld = Int(sorted[i+1].height),
                let tNewNs = Int64(sorted[i].date),
                let tOldNs = Int64(sorted[i+1].date)
            else { continue }

            let dBlocks = hNew - hOld
            if dBlocks <= 0 { continue }

            let dSeconds = Double(tNewNs - tOldNs) / 1_000_000_000.0
            if dSeconds <= 0 { continue }

            totalSeconds += dSeconds
            totalBlocks += dBlocks
        }

        guard totalBlocks > 0 else { return nil }
        return totalSeconds / Double(totalBlocks)
    }
}
