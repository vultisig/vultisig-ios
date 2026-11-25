//
//  BondRewardHistoryWalker.swift
//  VultisigApp
//

import Foundation
import OSLog

private let logger = Log.chain.other

/// Builds a bond provider's reward history from per-churn node snapshots, the
/// same way for THORChain and MayaChain.
enum BondRewardHistoryWalker {
    private typealias Target = (churnHeight: Int, snapshotHeight: Int, date: Date)

    /// This bond address's realized reward at each of the newest `limit`
    /// churns, newest first. `query` reads the node at one snapshot height
    /// (`churn - 1`), `BondRewardHistoryConfig.concurrency` at a time.
    ///
    /// `known` rewards (keyed by entry id) are already realized and saved: a
    /// past churn's reward never changes, so they are never queried again.
    /// Only churns within `BondRewardHistoryConfig.fetchWindow` of `now` are
    /// queried; an older churn is shown only when it is saved.
    ///
    /// A failed query is tried once more. The walk ends at the first churn the
    /// address was not a provider for and at the first churn that still fails,
    /// so the rows are the newest churns of one bond. Past the window, a gap
    /// (an unsaved churn too old to read) is crossed to the saved rows behind
    /// it unless `unbondHeights` shows an unbond from this node inside the gap.
    /// It throws only when a query failed and nothing at all could be loaded.
    static func walk(
        churns: [ChurnEntry],
        limit: Int,
        known: [Int: BondRewardHistoryEntry],
        now: Date,
        unbondHeights: @escaping @Sendable (_ fromHeight: Int, _ belowHeight: Int?) async throws -> [Int],
        query: @escaping @Sendable (_ snapshotHeight: Int, _ churnDate: Date) async -> BondRewardHistoryQueryResult
    ) async throws -> [BondRewardHistoryEntry] {
        let oldestQueryable = now.addingTimeInterval(-BondRewardHistoryConfig.fetchWindow)
        let targets = queryTargets(churns, limit: limit)
        let readable = targets.prefix { known[$0.churnHeight] != nil || $0.date >= oldestQueryable }

        var entries: [BondRewardHistoryEntry] = []

        for batch in Array(readable).chunked(into: BondRewardHistoryConfig.concurrency) {
            // A cancelled caller must never read any result as trustworthy.
            try Task.checkCancellation()

            let results = try await withBoundedConcurrency(
                batch,
                maxConcurrent: BondRewardHistoryConfig.concurrency
            ) { target -> BondRewardHistoryQueryResult in
                if let saved = known[target.churnHeight] {
                    return .found(saved)
                }
                // The gateway often fails a read of a retained height that a second read serves.
                let result = await query(target.snapshotHeight, target.date)
                guard case .failed = result else { return result }
                return await query(target.snapshotHeight, target.date)
            }

            for result in results {
                switch result {
                case .found(let entry):
                    entries.append(entry)
                case .notAProvider:
                    try Task.checkCancellation()
                    return entries
                case .failed(let error):
                    // This churn may be where the address stopped providing; older rows could be an earlier bond.
                    try Task.checkCancellation()
                    if entries.isEmpty { throw error }
                    return entries
                }
            }
        }

        try Task.checkCancellation()
        return try await entries + savedRowsAcrossGaps(
            targets[readable.count...],
            belowChurn: readable.last?.churnHeight,
            known: known,
            unbondHeights: unbondHeights
        )
    }

    /// The saved rows among `rest`, which starts at a gap and holds only churns
    /// too old to read. A gap is crossed unless the address unbonded from this
    /// node from the saved churn below it up to, not including, the known churn
    /// above it (`belowChurn` for the first gap; none when the newest churn is a
    /// gap): a row reads the block before its churn. One lookup, bounded to those
    /// ranges, covers every gap; when it fails, the walk ends at the first.
    private static func savedRowsAcrossGaps(
        _ rest: ArraySlice<Target>,
        belowChurn: Int?,
        known: [Int: BondRewardHistoryEntry],
        unbondHeights: @Sendable (_ fromHeight: Int, _ belowHeight: Int?) async throws -> [Int]
    ) async throws -> [BondRewardHistoryEntry] {
        let savedBelowGaps = zip(rest, rest.dropFirst())
            .filter { known[$0.0.churnHeight] == nil && known[$0.1.churnHeight] != nil }
        guard let lowestGapFloor = savedBelowGaps.last?.1.churnHeight else { return [] }

        let unbonds: [Int]
        do {
            unbonds = try await unbondHeights(lowestGapFloor, belowChurn)
        } catch {
            try Task.checkCancellation()
            logger.warning("bond unbond lookup failed, reward history ends at the first gap: \(error.localizedDescription, privacy: .public)")
            return []
        }
        try Task.checkCancellation()

        var rows: [BondRewardHistoryEntry] = []
        var newerKnownChurn = belowChurn ?? .max
        var isCrossingGap = false
        for target in rest {
            guard let saved = known[target.churnHeight] else {
                isCrossingGap = true
                continue
            }
            if isCrossingGap, unbonds.contains(where: { $0 >= target.churnHeight && $0 < newerKnownChurn }) {
                break
            }
            rows.append(saved)
            newerKnownChurn = target.churnHeight
            isCrossingGap = false
        }
        return rows
    }

    /// The height, snapshot height (`churn - 1`) and date of the newest `limit` churns, newest first.
    private static func queryTargets(_ churns: [ChurnEntry], limit: Int) -> [Target] {
        churns
            .sorted { (Int($0.height) ?? 0) > (Int($1.height) ?? 0) }
            .prefix(limit)
            .compactMap { churn in
                guard
                    let churnHeight = Int(churn.height),
                    let dateNanos = Double(churn.date)
                else { return nil }
                return (
                    churnHeight: churnHeight,
                    snapshotHeight: churnHeight - 1,
                    date: Date(timeIntervalSince1970: dateNanos / 1_000_000_000)
                )
            }
    }
}
