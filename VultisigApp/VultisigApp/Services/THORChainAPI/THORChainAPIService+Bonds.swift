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
    func getChurns() async throws -> [ChurnsResponse] {
        let response = try await httpClient.request(
            THORChainBondsAPI.getChurns,
            responseType: [ChurnsResponse].self
        )
        return response.data
    }

    /// Calculate bond metrics for a specific node and bond address
    /// Based on the JavaScript implementation from the provided snippet
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

        // 6. Get recent churn timestamp
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

        // 8. Calculate APR and APY
        let apr = myBond > 0 && timeDiffInYears > 0 ? (myAward / myBond) / Decimal(timeDiffInYears) : 0

        // APY = (1 + APR/365)^365 - 1
        let aprDouble = Double(truncating: apr as NSNumber)
        let apy = pow(1 + aprDouble / 365, 365) - 1

        // 9. Calculate next churn time (approximate)
        // Churn interval is approximately 43,200 blocks (~2.5 days)
        let churnIntervalSeconds: TimeInterval = 43200 * 6  // blocks * seconds_per_block
        let timeSinceLastChurn = currentTime - recentChurnTimestamp
        let timeUntilNextChurn = churnIntervalSeconds - timeSinceLastChurn.truncatingRemainder(dividingBy: churnIntervalSeconds)
        let nextChurnTimestamp = currentTime + timeUntilNextChurn

        // 10. Get RUNE price in USD using existing network info method
        let networkInfo = try await getNetworkInfo()
        let runePriceInTor = Decimal(string: networkInfo.rune_price_in_tor ?? "0") ?? 0
        let runePriceUSD = runePriceInTor / 100_000_000  // Convert from TOR (1e8)

        return BondMetrics(
            myBond: myBond,
            myAward: myAward,
            apy: apy,
            nextChurnTimestamp: nextChurnTimestamp,
            runePriceUSD: runePriceUSD,
            nodeStatus: nodeData.status
        )
    }
}

/// Metrics calculated for a bond position
struct BondMetrics {
    let myBond: Decimal
    let myAward: Decimal
    let apy: Double
    let nextChurnTimestamp: TimeInterval
    let runePriceUSD: Decimal
    let nodeStatus: String
}
