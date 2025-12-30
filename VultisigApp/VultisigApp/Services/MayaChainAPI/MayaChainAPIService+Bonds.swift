//
//  MayaChainAPIService+Bonds.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 23/11/2025.
//

import Foundation

extension MayaChainAPIService {
    /// Get all nodes and filter by bond address
    func getBondedNodes(address: String) async throws -> MayaBondedNodes {
        do {
            let response = try await httpClient.request(
                MayaChainBondsAPI.getAllNodes,
                responseType: [MayaNodeResponse].self
            )
            let allNodes = response.data

            // Filter nodes where the address has bond_providers matching our address
            var bondedNodes: [MayaBondNode] = []
            var totalBonded: Decimal = 0

            for node in allNodes {
                // Check if this node has bond providers with our address
                for provider in node.bondProviders.providers where provider.bondAddress == address {
                    // Calculate total bond from pools
                    let providerBond = provider.totalBond

                    let mayaNode = MayaBondNode(
                        status: node.status,
                        address: node.nodeAddress,
                        bond: providerBond
                    )
                    bondedNodes.append(mayaNode)
                    totalBonded += providerBond
                }
            }

            return MayaBondedNodes(totalBonded: totalBonded, nodes: bondedNodes)
        } catch {
            throw MayaChainAPIError.networkError(error)
        }
    }

    /// Get detailed node information including bond providers and current award
    func getNodeDetails(nodeAddress: String) async throws -> MayaNodeResponse {
        let response = try await httpClient.request(
            MayaChainBondsAPI.getNodeDetails(nodeAddress: nodeAddress),
            responseType: MayaNodeResponse.self
        )
        return response.data
    }

    /// Get network-wide bond information (APR and next churn date)
    func getNetworkBondInfo() async throws -> MayaNetworkBondInfo {
        let network = try await getNetwork()
        let apr = Double(network.bondingAPY ?? "0") ?? 0
        let nextChurnDate = try await estimateNextChurnETA(network: network)

        return MayaNetworkBondInfo(apr: apr, nextChurnDate: nextChurnDate)
    }

    /// Calculate bond metrics for a specific node and bond address
    /// Based on the MayaChain PRD - calculates APR per node
    func calculateBondMetrics(
        nodeAddress: String,
        myBondAddress: String
    ) async throws -> MayaBondMetrics {
        // 1. Fetch node details
        let nodeData = try await getNodeDetails(nodeAddress: nodeAddress)
        let bondProviders = nodeData.bondProviders.providers

        // 2. Calculate my bond and total bond from pools
        var myBond: Decimal = 0
        var totalBond: Decimal = 0

        for provider in bondProviders {
            let providerBond = provider.totalBond
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

        // 6. Get network info to estimate APR
        // For Maya, we'll use the network-wide bonding APY as the base
        let network = try await getNetwork()
        let networkAPR = Double(network.bondingAPY ?? "0") ?? 0

        return MayaBondMetrics(
            myBond: myBond,
            myAward: myAward,
            apr: networkAPR,
            nodeStatus: nodeData.status
        )
    }

    /// Estimate next churn ETA for MayaChain
    func estimateNextChurnETA(network: MayaNetworkInfo) async throws -> Date? {
        let health = try await getHealth()

        guard let nextChurnHeight = Int(network.nextChurnHeight ?? "") else { return nil }
        let currentHeight = health.lastMayaNode.height
        let currentTimestamp = TimeInterval(health.lastMayaNode.timestamp)

        guard nextChurnHeight > currentHeight else { return nil }

        // Maya has approximately 5 seconds per block
        let avgBlockTime: Double = 5.0

        let remainingBlocks = Int64(nextChurnHeight) - currentHeight
        let etaSeconds = Double(remainingBlocks) * avgBlockTime

        return Date(timeIntervalSince1970: currentTimestamp).addingTimeInterval(etaSeconds)
    }

    // MARK: - Bond Validation Methods

    /// Calculate CACAO value of LP units for a pool
    /// - Parameters:
    ///   - lpUnits: Amount of LP units to convert
    ///   - poolAsset: Pool asset identifier (e.g., "BTC.BTC", "ETH.ETH")
    /// - Returns: Estimated CACAO value in decimal format
    func calculateLPUnitsCacaoValue(
        lpUnits: UInt64,
        poolAsset: String
    ) async throws -> Decimal {
        let poolStats = try await getPoolStats()
        guard let pool = poolStats.first(where: { $0.asset == poolAsset }) else {
            throw MayaChainAPIError.invalidResponse
        }

        let totalPoolUnits = Decimal(string: pool.liquidityUnits) ?? 0
        let cacaoDepth = Decimal(string: pool.runeDepth) ?? 0

        guard totalPoolUnits > 0 else { return 0 }

        // Calculate: (lpUnits / totalPoolUnits) * cacaoDepth
        let cacaoValue = (Decimal(lpUnits) / totalPoolUnits) * cacaoDepth
        return cacaoValue / pow(10, 10) // Convert from base units to CACAO
    }

    /// Calculate minimum LP units needed to meet the 35K CACAO bond requirement
    /// - Parameter poolAsset: Pool asset identifier (e.g., "BTC.BTC", "ETH.ETH")
    /// - Returns: Minimum LP units needed to bond
    func calculateMinimumLPUnits(poolAsset: String) async throws -> UInt64 {
        let minBondCacao: Decimal = 35000 // Minimum bond requirement in CACAO
        let poolStats = try await getPoolStats()
        guard let pool = poolStats.first(where: { $0.asset == poolAsset }) else {
            throw MayaChainAPIError.invalidResponse
        }

        let totalPoolUnits = Decimal(string: pool.liquidityUnits) ?? 0
        let cacaoDepth = Decimal(string: pool.runeDepth) ?? 0

        guard cacaoDepth > 0 else { return 0 }

        // Calculate: (minBondCacao * 1e10 * totalPoolUnits) / cacaoDepth
        let minLPUnits = (minBondCacao * pow(10, 10) * totalPoolUnits) / cacaoDepth
        return UInt64(truncating: minLPUnits as NSNumber)
    }

    /// Validate if a node can accept more bond providers
    /// - Parameter nodeAddress: Maya node address
    /// - Returns: True if node has capacity for more bond providers
    func validateNodeBondCapacity(nodeAddress: String) async throws -> Bool {
        let nodeDetails = try await getNodeDetails(nodeAddress: nodeAddress)
        let currentProviders = nodeDetails.bondProviders.providers.count
        let maxProviders = 10 // Maximum bond providers per node (Mimir: MAXBONDPROVIDERS)
        return currentProviders < maxProviders
    }
}
