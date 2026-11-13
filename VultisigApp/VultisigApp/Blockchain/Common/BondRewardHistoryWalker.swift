//
//  BondRewardHistoryWalker.swift
//  VultisigApp
//

import Foundation

/// Builds a bond provider's reward history from per-churn node snapshots, the
/// same way for THORChain and MayaChain.
enum BondRewardHistoryWalker {
    /// This bond address's realized reward at each of the newest `limit`
    /// churns, newest first. `query` reads the node at one snapshot height
    /// (`churn - 1`), `BondRewardHistoryConfig.concurrency` at a time.
    ///
    /// `known` rewards (keyed by entry id) are already realized and saved: a
    /// past churn's reward never changes, so they are never queried again.
    ///
    /// A failed query is tried once more. The walk ends at the first churn the
    /// address was not yet a provider for, and after the first batch that still
    /// has a failure (nodes only keep recent state, so older heights would fail
    /// too). A failure leaves the history incomplete; it throws only when
    /// nothing at all could be loaded.
    static func walk(
        churns: [ChurnEntry],
        limit: Int,
        known: [Int: BondRewardHistoryEntry],
        query: @escaping @Sendable (_ snapshotHeight: Int, _ churnDate: Date) async -> BondRewardHistoryQueryResult
    ) async throws -> BondRewardHistory {
        var entries: [BondRewardHistoryEntry] = []
        var firstFailure: Error?

        for batch in queryTargets(churns, limit: limit).chunked(into: BondRewardHistoryConfig.concurrency) {
            // A cancelled caller must never read any result as trustworthy.
            try Task.checkCancellation()

            let results = try await withBoundedConcurrency(
                batch,
                maxConcurrent: BondRewardHistoryConfig.concurrency
            ) { target -> BondRewardHistoryQueryResult in
                if let saved = known[target.height + 1] {
                    return .found(saved)
                }
                // The gateway often fails a read of a retained height that a second read serves.
                let result = await query(target.height, target.date)
                guard case .failed = result else { return result }
                return await query(target.height, target.date)
            }

            for result in results {
                switch result {
                case .found(let entry):
                    entries.append(entry)
                case .notAProvider:
                    try Task.checkCancellation()
                    return BondRewardHistory(entries: entries, isComplete: firstFailure == nil)
                case .failed(let error):
                    firstFailure = firstFailure ?? error
                }
            }

            if firstFailure != nil { break }
        }

        try Task.checkCancellation()
        if let firstFailure, entries.isEmpty {
            throw firstFailure
        }
        return BondRewardHistory(entries: entries, isComplete: firstFailure == nil)
    }

    /// The snapshot height (`churn - 1`) and churn date of the newest `limit` churns, newest first.
    private static func queryTargets(_ churns: [ChurnEntry], limit: Int) -> [(height: Int, date: Date)] {
        churns
            .sorted { (Int($0.height) ?? 0) > (Int($1.height) ?? 0) }
            .prefix(limit)
            .compactMap { churn in
                guard
                    let churnHeight = Int(churn.height),
                    let dateNanos = Double(churn.date)
                else { return nil }
                return (height: churnHeight - 1, date: Date(timeIntervalSince1970: dateNanos / 1_000_000_000))
            }
    }
}
