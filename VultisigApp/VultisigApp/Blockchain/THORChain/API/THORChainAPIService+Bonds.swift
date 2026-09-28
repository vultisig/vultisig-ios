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

    /// Get detailed node information including bond providers and current award.
    ///
    /// `height` snapshots the node at a past block — used to read the award
    /// about to be paid at a specific churn (`height: churnHeight - 1`).
    /// Historical responses never change, so they're cached indefinitely by
    /// `nodeAddress + height`; the live snapshot (`height == nil`) is not
    /// cached here.
    func getNodeDetails(nodeAddress: String, height: Int? = nil) async throws -> NodeDetailsResponse {
        guard let height else {
            let response = try await httpClient.request(
                THORChainBondsAPI.getNodeDetails(nodeAddress: nodeAddress, height: nil),
                responseType: NodeDetailsResponse.self
            )
            return response.data
        }

        return try await historicalNodeDetailsCache.value(
            for: "\(nodeAddress)_\(height)",
            now: Date(),
            ttl: .infinity
        ) {
            let response = try await self.httpClient.request(
                THORChainBondsAPI.getNodeDetails(nodeAddress: nodeAddress, height: height),
                responseType: NodeDetailsResponse.self
            )
            return response.data
        }
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
        // 1. Fetch node details and this address's share of the live award
        let nodeData = try await getNodeDetails(nodeAddress: nodeAddress)
        let share = BondRewardMath.share(
            providers: nodeData.bondProviders.providers.map { ($0.bondAddress, Decimal(string: $0.bond) ?? 0) },
            nodeOperatorFeeBps: Decimal(string: nodeData.bondProviders.nodeOperatorFee) ?? 0,
            currentAward: Decimal(string: nodeData.currentAward) ?? 0,
            myBondAddress: myBondAddress
        ) ?? BondRewardMath.Share(myBond: 0, myAward: 0)
        let myBond = share.myBond
        let myAward = share.myAward

        // 2. Get recent churn timestamp to calculate APY
        let churns = try await getChurns()
        guard let mostRecentChurn = churns.first,
              let recentChurnTimestampNanos = Double(mostRecentChurn.date) else {
            throw THORChainAPIError.invalidResponse
        }

        // Convert from nanoseconds to seconds
        let recentChurnTimestamp = recentChurnTimestampNanos / 1_000_000_000

        // 3. Calculate time since last churn
        let currentTime = Date().timeIntervalSince1970
        let timeDiff = currentTime - recentChurnTimestamp
        let timeDiffInYears = timeDiff / (60 * 60 * 24 * 365.25)

        // 4. Calculate APR and APY per node (matching JavaScript implementation)
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

    /// This bond address's share of the award paid at each of the vault's
    /// last `limit` churns, newest first.
    ///
    /// Walks backward from the newest churn and stops at the first one where
    /// `myBondAddress` is not listed among `bond_providers` — the vault was
    /// not bonded yet at that snapshot, so earlier churns paid it nothing.
    /// Queries run in batches of `BondRewardHistoryConfig.concurrency`
    /// (bounded, not all `limit` at once); a confirmed gap found within a
    /// batch stops the NEXT batch from ever being scheduled, so a vault
    /// bonded for only a few churns costs a few requests, not `limit` of
    /// them — the batch itself still runs to completion, since concurrent
    /// queries can't be un-issued once in flight. Historical node-details
    /// responses are cached indefinitely per `nodeAddress + height` (see
    /// `getNodeDetails(nodeAddress:height:)`), but each `THORChainAPIService`
    /// instance owns its own cache — the sheet's view model currently
    /// constructs a fresh interactor/service, so it does not yet reuse the
    /// card's eager `limit: 1` fetch of this same height.
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
            // `withBoundedConcurrency` only stops scheduling WITHIN a batch
            // once cancelled — nothing otherwise stops this loop from still
            // starting every subsequent batch, since a cancelled `await`
            // returning normally is not itself a signal here.
            try Task.checkCancellation()

            let batchResults = try await withBoundedConcurrency(
                batch,
                maxConcurrent: BondRewardHistoryConfig.concurrency
            ) { query -> BondRewardHistoryQueryResult in
                do {
                    let node = try await self.getNodeDetails(nodeAddress: nodeAddress, height: query.height)
                    guard let share = BondRewardMath.share(
                        providers: node.bondProviders.providers.map { ($0.bondAddress, Decimal(string: $0.bond) ?? 0) },
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
                    // A successfully decoded snapshot without this address is
                    // the real "wasn't bonded yet" signal — stop here, before
                    // the next batch is ever scheduled. Still checked for
                    // cancellation first: this is a normal-looking return
                    // path, and a cancelled caller must never read ANY
                    // result — including a legitimate one — as trustworthy.
                    try Task.checkCancellation()
                    return entries
                case .failed(let error):
                    // A network/decode failure is NOT the same signal: silently
                    // treating it as "not a provider" would truncate (or empty
                    // out) otherwise-valid history. Propagate instead — the one
                    // eager card-row call already wraps this in `try?`, and the
                    // sheet's view model surfaces it as its own load error
                    // without touching the bonded list.
                    throw error
                }
            }
        }
        // Explicit even though every batch above already checks (and
        // `withBoundedConcurrency` itself fails closed on cancellation): the
        // gap this closes is between the last batch's processing finishing
        // and this function returning, so cancellation is checked after the
        // LAST batch too, not just before every batch.
        try Task.checkCancellation()
        return entries
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
