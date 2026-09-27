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

    /// Get detailed node information including bond providers and current award.
    ///
    /// `height` snapshots the node at a past block — used to read the award
    /// about to be paid at a specific churn (`height: churnHeight - 1`).
    /// Historical responses never change, so they're cached indefinitely by
    /// `nodeAddress + height`; the live snapshot (`height == nil`) is not
    /// cached here.
    func getNodeDetails(nodeAddress: String, height: Int? = nil) async throws -> MayaNodeResponse {
        guard let height else {
            let response = try await httpClient.request(
                MayaChainBondsAPI.getNodeDetails(nodeAddress: nodeAddress, height: nil),
                responseType: MayaNodeResponse.self
            )
            return response.data
        }

        return try await historicalNodeDetailsCache.value(
            for: "\(nodeAddress)_\(height)",
            now: Date(),
            ttl: .infinity
        ) {
            let response = try await self.httpClient.request(
                MayaChainBondsAPI.getNodeDetails(nodeAddress: nodeAddress, height: height),
                responseType: MayaNodeResponse.self
            )
            return response.data
        }
    }

    /// Get recent churns history (with 5-minute cache), mirroring THORChain's
    /// `getChurns()`.
    func getChurns() async throws -> [ChurnEntry] {
        if let cached = await cache.getCachedChurns() {
            return cached
        }

        let response = try await httpClient.request(
            MayaChainBondsAPI.getChurns,
            responseType: [ChurnEntry].self
        )
        let data = response.data
        await cache.cacheChurns(data)
        return data
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
        // 1. Fetch node details and this address's share of the live award
        let nodeData = try await getNodeDetails(nodeAddress: nodeAddress)
        let share = BondRewardMath.share(
            providers: nodeData.bondProviders.providers.map { ($0.bondAddress, $0.totalBond) },
            nodeOperatorFeeBps: Decimal(string: nodeData.bondProviders.nodeOperatorFee) ?? 0,
            currentAward: Decimal(string: nodeData.currentAward) ?? 0,
            myBondAddress: myBondAddress
        ) ?? BondRewardMath.Share(myBond: 0, myAward: 0)

        // 2. Get network info to estimate APR
        // For Maya, we'll use the network-wide bonding APY as the base
        let network = try await getNetwork()
        let networkAPR = Double(network.bondingAPY ?? "0") ?? 0

        return MayaBondMetrics(
            myBond: share.myBond,
            myAward: share.myAward,
            apr: networkAPR,
            nodeStatus: nodeData.status
        )
    }

    /// This bond address's share of the award paid at each of the vault's
    /// last `limit` churns, newest first. Mirrors
    /// `THORChainAPIService.getBondRewardHistory` — see it for the
    /// batched-stop-at-first-gap and caching rationale.
    func getBondRewardHistory(
        nodeAddress: String,
        myBondAddress: String,
        limit: Int = BondRewardHistoryConfig.limit
    ) async throws -> [BondRewardHistoryEntry] {
        let churns = try await getChurns()
        let recentChurns = churns
            .sorted { (Int($0.height) ?? 0) > (Int($1.height) ?? 0) }
            .prefix(limit)

        let queries: [(height: Int, date: Date)] = recentChurns.compactMap { churn in
            guard
                let churnHeight = Int(churn.height),
                let dateNanos = Double(churn.date)
            else { return nil }
            return (height: churnHeight - 1, date: Date(timeIntervalSince1970: dateNanos / 1_000_000_000))
        }

        var entries: [BondRewardHistoryEntry] = []
        for batch in queries.chunked(into: BondRewardHistoryConfig.concurrency) {
            // See the identical comment in THORChainAPIService.getBondRewardHistory.
            try Task.checkCancellation()

            let batchResults = await withBoundedConcurrency(
                batch,
                maxConcurrent: BondRewardHistoryConfig.concurrency
            ) { query -> BondRewardHistoryQueryResult in
                do {
                    let node = try await self.getNodeDetails(nodeAddress: nodeAddress, height: query.height)
                    guard let share = BondRewardMath.share(
                        providers: node.bondProviders.providers.map { ($0.bondAddress, $0.totalBond) },
                        nodeOperatorFeeBps: Decimal(string: node.bondProviders.nodeOperatorFee) ?? 0,
                        currentAward: Decimal(string: node.currentAward) ?? 0,
                        myBondAddress: myBondAddress
                    ) else {
                        return .notAProvider
                    }
                    return .found(BondRewardHistoryEntry(churnHeight: query.height + 1, churnDate: query.date, amount: share.myAward))
                } catch {
                    return .failed(error)
                }
            }

            for result in batchResults {
                switch result {
                case .found(let entry):
                    entries.append(entry)
                case .notAProvider:
                    return entries
                case .failed(let error):
                    // See the identical comment in THORChainAPIService.getBondRewardHistory.
                    throw error
                }
            }
        }
        return entries
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

    /// Check if a bond address is whitelisted on a node
    /// - Parameters:
    ///   - nodeAddress: Maya node address
    ///   - bondAddress: The potential bond provider's address
    /// - Returns: True if the address is whitelisted (present in bond_providers)
    func isAddressWhitelisted(nodeAddress: String, bondAddress: String) async throws -> Bool {
        let nodeDetails = try await getNodeDetails(nodeAddress: nodeAddress)
        return nodeDetails.bondProviders.providers.contains { $0.bondAddress == bondAddress }
    }

    /// Comprehensive bond eligibility check
    /// - Parameters:
    ///   - nodeAddress: Maya node address
    ///   - bondAddress: The potential bond provider's address
    /// - Returns: BondEligibility result with status and error message if ineligible
    func checkBondEligibility(nodeAddress: String, bondAddress: String) async throws -> MayaBondEligibility {
        let nodeDetails = try await getNodeDetails(nodeAddress: nodeAddress)

        // Check 1: Is user whitelisted?
        let isWhitelisted = nodeDetails.bondProviders.providers.contains { $0.bondAddress == bondAddress }
        guard isWhitelisted else {
            return MayaBondEligibility(
                canBond: false,
                nodeStatus: nodeDetails.status,
                currentProviders: nodeDetails.bondProviders.providers.count
            )
        }

        // Check 2: Does node have capacity?
        let maxProviders = 8
        let currentProviders = nodeDetails.bondProviders.providers.count
        guard currentProviders < maxProviders else {
            return MayaBondEligibility(
                canBond: false,
                nodeStatus: nodeDetails.status,
                currentProviders: currentProviders
            )
        }

        // All checks passed
        return MayaBondEligibility(
            canBond: true,
            nodeStatus: nodeDetails.status,
            currentProviders: currentProviders
        )
    }

    /// Get node status for unbond eligibility
    /// - Parameter nodeAddress: Maya node address
    /// - Returns: Node status info for unbonding
    func getNodeStatusForUnbond(nodeAddress: String) async throws -> MayaNodeUnbondStatus {
        let nodeDetails = try await getNodeDetails(nodeAddress: nodeAddress)
        let canUnbond = nodeDetails.status != "Active" // Can only unbond when node is churned out

        return MayaNodeUnbondStatus(
            nodeStatus: nodeDetails.status,
            canUnbond: canUnbond
        )
    }

    /// Get bonded LP units for a specific node, bond address, and pool asset
    /// - Parameters:
    ///   - nodeAddress: Maya node address
    ///   - bondAddress: The bond provider's address
    ///   - poolAsset: Pool asset identifier (e.g., "BTC.BTC", "ETH.ETH")
    /// - Returns: LP units bonded to this node for the specified pool, or nil if not found
    func getBondedLPUnits(
        nodeAddress: String,
        bondAddress: String,
        poolAsset: String
    ) async throws -> UInt64? {
        let nodeDetails = try await getNodeDetails(nodeAddress: nodeAddress)

        // Find the bond provider matching our address
        guard let provider = nodeDetails.bondProviders.providers.first(where: {
            $0.bondAddress == bondAddress
        }) else {
            return nil
        }

        // Get LP units for the specified pool
        guard let lpUnitsString = provider.pools[poolAsset],
              let lpUnits = UInt64(lpUnitsString) else {
            return nil
        }

        return lpUnits
    }

    /// Get all bonded LP units across all nodes for a bond address, grouped by pool
    /// - Parameter address: The bond provider's address
    /// - Returns: Dictionary of pool asset to total LP units bonded
    func getAllBondedLPUnitsByPool(address: String) async throws -> [String: UInt64] {
        let response = try await httpClient.request(
            MayaChainBondsAPI.getAllNodes,
            responseType: [MayaNodeResponse].self
        )
        let allNodes = response.data

        var totalBondedByPool: [String: UInt64] = [:]

        for node in allNodes {
            // Find all bond providers matching our address in this node
            let matchingProviders = node.bondProviders.providers.filter {
                $0.bondAddress == address
            }
            for provider in matchingProviders {
                // Sum units for each pool
                for (asset, unitsString) in provider.pools {
                    if let units = UInt64(unitsString) {
                        totalBondedByPool[asset, default: 0] += units
                    }
                }
            }
        }

        return totalBondedByPool
    }

    /// Get all bonded LP positions for a bond address on a specific node
    /// - Parameters:
    ///   - nodeAddress: Maya node address
    ///   - bondAddress: The bond provider's address
    /// - Returns: Dictionary of pool asset to LP units, or nil if not a provider
    func getAllBondedLPUnits(
        nodeAddress: String,
        bondAddress: String
    ) async throws -> [String: UInt64]? {
        let nodeDetails = try await getNodeDetails(nodeAddress: nodeAddress)

        // Find the bond provider matching our address
        guard let provider = nodeDetails.bondProviders.providers.first(where: {
            $0.bondAddress == bondAddress
        }) else {
            return nil
        }

        // Convert string values to UInt64
        var result: [String: UInt64] = [:]
        for (asset, unitsString) in provider.pools {
            if let units = UInt64(unitsString) {
                result[asset] = units
            }
        }

        return result.isEmpty ? nil : result
    }
}
