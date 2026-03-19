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

    /// Get recent churns history (with 5-minute cache)
    func getChurns() async throws -> [ChurnEntry] {
        // Check cache first
        if let cached = await cache.getCachedChurns() {
            return cached
        }

        // Fetch from network
        let response = try await httpClient.request(
            THORChainBondsAPI.getChurns,
            responseType: [ChurnEntry].self
        )
        let data = response.data

        // Cache the result
        await cache.cacheChurns(data)

        return data
    }

    /// Get churn interval from mimir (with 5-minute cache)
    func getChurnInterval() async throws -> String {
        // Check cache first
        if let cached = await cache.getCachedChurnInterval() {
            return cached
        }

        // Fetch from network (returns plain text)
        let response = try await httpClient.request(
            THORChainBondsAPI.getChurnInterval,
            responseType: String.self
        )
        let data = response.data

        // Cache the result
        await cache.cacheChurnInterval(data)

        return data
    }

    /// Get network-wide bond information (APY and next churn date)
    func getNetworkBondInfo() async throws -> NetworkBondInfo {
        let network = try await getNetworkInfo()
        let apy = Double(network.bondingAPY ?? "0") ?? 0
        let nextChurnDate = try await estimateNextChurnETA(network: network)

        return NetworkBondInfo(apy: apy, nextChurnDate: nextChurnDate)
    }

    /// Calculate bond metrics for a specific node and bond address
    /// Based on the JavaScript implementation - calculates APY per node
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

        // 6. Get recent churn timestamp to calculate APY
        let churns = try await getChurns()
        guard let mostRecentChurn = churns.first,
              let recentChurnTimestampNanos = Double(mostRecentChurn.date) else {
            throw THORChainAPIError.invalidResponse
        }

        // Convert from nanoseconds to seconds
        let recentChurnTimestamp = recentChurnTimestampNanos / 1_000_000_000

        // 7. Calculate time since last churn
        let currentTime = Date().timeIntervalSince1970
        let timeDiff = currentTime - recentChurnTimestamp
        let timeDiffInYears = timeDiff / (60 * 60 * 24 * 365.25)

        // 8. Calculate APR and APY per node (matching JavaScript implementation)
        let apr = myBond > 0 && timeDiffInYears > 0 ? (myAward / myBond) / Decimal(timeDiffInYears) : 0

        // APY = (1 + APR/365)^365 - 1
        let aprDouble = Double(truncating: apr as NSNumber)
        let apy = pow(1 + aprDouble / 365, 365) - 1

        return BondMetrics(
            myBond: myBond,
            myAward: myAward,
            apy: apy,
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
